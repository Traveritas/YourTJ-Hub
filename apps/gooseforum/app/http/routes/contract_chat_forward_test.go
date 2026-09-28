package routes

import (
	"encoding/json"
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/chat/imUserChatConfigs"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/chat/messages"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/models/forum/users"
	"github.com/YourTongji/YourTJ-Hub/apps/gooseforum/app/service/chatservice"
)

func TestChatForwardMergedSnapshotAndRetry(t *testing.T) {
	conn, router := setupNotificationChatContractTest(t)
	sender := createHTTPContractUser(t, conn, contractTestID())
	actor := createHTTPContractUser(t, conn, contractTestID())
	target := createHTTPContractUser(t, conn, contractTestID())
	if err := conn.Model(&users.EntityComplete{}).Where("id = ?", sender.Id).Update("avatar_url", "/static/pic/3.webp").Error; err != nil {
		t.Fatal(err)
	}
	convID, err := chatservice.SendMessage(sender.Id, actor.Id, "first line", 1)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := chatservice.SendMessage(actor.Id, sender.Id, "second line [:sticker:smile:]", 1); err != nil {
		t.Fatal(err)
	}
	var source []messages.Entity
	conn.Where("conv_id = ?", convID).Order("id").Find(&source)
	token := contractSessionToken(t, actor)
	body := fmt.Sprintf(`{"convId":%d,"peerId":%d,"messageIds":[%d,%d],"mode":"merged","clientForwardId":"batch-1"}`, convID, target.Id, source[1].Id, source[0].Id)
	for range 2 {
		rec := serveJSON(router, "/api/forum/chat/forward", body, token)
		var envelope struct {
			Code   int `json:"code"`
			Result struct {
				ConvID     uint64   `json:"convId"`
				MessageIDs []uint64 `json:"messageIds"`
			} `json:"result"`
		}
		if rec.Code != 200 || json.Unmarshal(rec.Body.Bytes(), &envelope) != nil || envelope.Code != 0 || len(envelope.Result.MessageIDs) != 1 {
			t.Fatalf("forward: %d %s", rec.Code, rec.Body)
		}
		page, err := chatservice.GetMessages(target.Id, envelope.Result.ConvID, 0, 0, 30)
		if err != nil {
			t.Fatal(err)
		}
		data, err := json.Marshal(page)
		if err != nil {
			t.Fatal(err)
		}
		var response map[string]any
		if err := json.Unmarshal(data, &response); err != nil {
			t.Fatal(err)
		}
		item := response["list"].([]any)[0].(map[string]any)
		forward, ok := item["forwarded"].(map[string]any)
		if !ok {
			t.Fatalf("missing forwarded snapshot: %s", data)
		}
		entries := forward["messages"].([]any)
		if len(entries) != 2 || entries[0].(map[string]any)["content"] != "first line" {
			t.Fatalf("order/content: %s", data)
		}
		if entries[0].(map[string]any)["avatarUrl"] != "/static/pic/3.webp" {
			t.Fatalf("missing immutable public avatar: %s", data)
		}
		if err := conn.Model(&users.EntityComplete{}).Where("id = ?", sender.Id).Update("avatar_url", "/static/pic/4.webp").Error; err != nil {
			t.Fatal(err)
		}
	}
	var count int64
	conn.Model(&messages.Entity{}).Where("sender_id = ? AND conv_id != ?", actor.Id, convID).Count(&count)
	if count != 1 {
		t.Fatalf("duplicate forwards: %d", count)
	}
}

func TestChatForwardRejectsForeignSourcesAndBlockedRecipients(t *testing.T) {
	conn, router := setupNotificationChatContractTest(t)
	actor := createHTTPContractUser(t, conn, contractTestID())
	peer := createHTTPContractUser(t, conn, contractTestID())
	target := createHTTPContractUser(t, conn, contractTestID())
	outsider := createHTTPContractUser(t, conn, contractTestID())
	conv, _ := chatservice.SendMessage(peer.Id, actor.Id, "private", 1)
	foreign, _ := chatservice.SendMessage(peer.Id, outsider.Id, "foreign secret", 1)
	var own, other messages.Entity
	conn.Where("conv_id = ?", conv).First(&own)
	conn.Where("conv_id = ?", foreign).First(&other)
	good := chatservice.ForwardRequest{ConvID: conv, PeerID: target.Id, MessageIDs: []uint64{own.Id}, Mode: "merged", ClientForwardID: "negative"}
	for _, test := range []struct {
		name   string
		mutate func(*chatservice.ForwardRequest)
	}{
		{"foreign conversation", func(r *chatservice.ForwardRequest) { r.ConvID = foreign; r.MessageIDs = []uint64{other.Id} }},
		{"mixed sources", func(r *chatservice.ForwardRequest) { r.MessageIDs = []uint64{own.Id, other.Id} }},
		{"duplicate IDs", func(r *chatservice.ForwardRequest) { r.MessageIDs = []uint64{own.Id, own.Id} }},
		{"missing source", func(r *chatservice.ForwardRequest) { r.MessageIDs = []uint64{other.Id + 100000} }},
		{"self target", func(r *chatservice.ForwardRequest) { r.PeerID = actor.Id }},
		{"bad identity", func(r *chatservice.ForwardRequest) { r.ClientForwardID = "invalid/key" }},
		{"individual burst limit", func(r *chatservice.ForwardRequest) {
			r.Mode = "individual"
			r.MessageIDs = make([]uint64, 11)
			for i := range r.MessageIDs {
				r.MessageIDs[i] = uint64(i + 1)
			}
		}},
	} {
		t.Run(test.name, func(t *testing.T) {
			r := good
			test.mutate(&r)
			if _, err := chatservice.ForwardMessages(actor.Id, r); err == nil {
				t.Fatal("forward should fail")
			}
		})
	}
	if err := users.SetBlockedUser(target.Id, actor.Id, true); err != nil {
		t.Fatal(err)
	}
	if _, err := chatservice.ForwardMessages(actor.Id, good); err == nil {
		t.Fatal("blocked forward should fail")
	}
	var count int64
	conn.Model(&messages.Entity{}).Where("sender_id = ?", actor.Id).Count(&count)
	if count != 0 {
		t.Fatalf("rejected request leaked %d messages", count)
	}
	raw, err := json.Marshal(good)
	if err != nil {
		t.Fatal(err)
	}
	if rec := serveJSON(router, "/api/forum/chat/forward", string(raw), ""); rec.Code != 401 {
		t.Fatalf("anonymous status %d", rec.Code)
	}
}

func TestChatForwardIndividualAtomicRetryAndNestedBounds(t *testing.T) {
	conn, _ := setupNotificationChatContractTest(t)
	actor := createHTTPContractUser(t, conn, contractTestID())
	peer := createHTTPContractUser(t, conn, contractTestID())
	target := createHTTPContractUser(t, conn, contractTestID())
	conv, _ := chatservice.SendMessage(peer.Id, actor.Id, "first", 1)
	if _, err := chatservice.SendMessage(actor.Id, peer.Id, "second", 1); err != nil {
		t.Fatal(err)
	}
	var source []messages.Entity
	conn.Where("conv_id = ?", conv).Order("id").Find(&source)
	req := chatservice.ForwardRequest{ConvID: conv, PeerID: target.Id, MessageIDs: []uint64{source[1].Id, source[0].Id}, Mode: "individual", ClientForwardID: "atomic"}
	// An insert failure in the second message must roll back the first message,
	// the new conversation, memberships, and counters together.
	conn.Exec(`CREATE TRIGGER fail_forward BEFORE INSERT ON messages WHEN NEW.content = 'second' BEGIN SELECT RAISE(ABORT, 'injected failure'); END`)
	if _, err := chatservice.ForwardMessages(actor.Id, req); err == nil {
		t.Fatal("expected insert failure")
	}
	var leaked int64
	conn.Model(&messages.Entity{}).Where("sender_id = ? AND conv_id != ?", actor.Id, conv).Count(&leaked)
	if leaked != 0 {
		t.Fatal("partial delivery escaped rollback")
	}
	conn.Exec(`DROP TRIGGER fail_forward`)
	first, err := chatservice.ForwardMessages(actor.Id, req)
	if err != nil {
		t.Fatal(err)
	}
	retry, err := chatservice.ForwardMessages(actor.Id, req)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(first, retry) {
		t.Fatalf("retry changed identity: %#v %#v", first, retry)
	}
	var sent []messages.Entity
	conn.Where("conv_id = ?", first.ConvID).Order("id").Find(&sent)
	if len(sent) != 2 || sent[0].Content != "first" || sent[1].Content != "second" {
		t.Fatalf("wrong individual copy: %#v", sent)
	}
	var membership imUserChatConfigs.Entity
	conn.Where("user_id = ? AND conv_id = ?", target.Id, first.ConvID).First(&membership)
	if membership.UnreadCount != 2 {
		t.Fatalf("retry inflated unread count: %d", membership.UnreadCount)
	}
	req.Mode = "merged"
	req.ClientForwardID = "nested"
	merged, err := chatservice.ForwardMessages(actor.Id, req)
	if err != nil {
		t.Fatal(err)
	}
	again, err := chatservice.ForwardMessages(target.Id, chatservice.ForwardRequest{ConvID: merged.ConvID, PeerID: peer.Id, MessageIDs: merged.MessageIDs, Mode: "merged", ClientForwardID: "flatten"})
	if err != nil {
		t.Fatal(err)
	}
	var nested messages.Entity
	conn.First(&nested, again.MessageIDs[0])
	bundle := messages.ParseForward(nested.Content)
	if bundle == nil || len(bundle.Messages) != 2 || bundle.Messages[1].Content != "second" {
		t.Fatalf("nested snapshot not flattened: %s", nested.Content)
	}
	// Changing the source author's profile must not mutate an acknowledged copy.
	conn.Model(&peer).Where("id = ?", peer.Id).Update("nickname", strings.Repeat("x", messages.MaxForwardBytes))
	replay, err := chatservice.ForwardMessages(actor.Id, req)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(merged, replay) {
		t.Fatal("profile change changed acknowledged message")
	}
}
