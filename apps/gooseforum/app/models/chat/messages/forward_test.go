package messages

import (
	"strings"
	"testing"
)

func TestForwardSnapshotBoundsAndFallback(t *testing.T) {
	bundle := &ForwardedBundle{Version: 1, Messages: []ForwardedEntry{{SenderName: "Alice", Content: "hello", CreatedAt: "2026-09-28T10:00:00Z", MsgType: 1}}}
	raw, err := bundle.Encode()
	if err != nil {
		t.Fatal(err)
	}
	if got := DisplayContent(raw, ForwardType); got != "[Chat history]\nAlice: hello" {
		t.Fatalf("fallback = %q", got)
	}
	if ParseForward(`{"version":2,"messages":[]}`) != nil {
		t.Fatal("unknown version accepted")
	}
	for _, content := range []string{"bad JSON", strings.Repeat("x", MaxForwardBytes+1), `{"version":1,"messages":[{"msgType":4}]}`} {
		if ParseForward(content) != nil {
			t.Fatal("invalid content accepted")
		}
	}
	bundle.Messages = make([]ForwardedEntry, 51)
	if _, err := bundle.Encode(); err == nil {
		t.Fatal("oversized entry count accepted")
	}
	if got := DisplayContent("literal text", 1); got != "literal text" {
		t.Fatal("ordinary text changed")
	}
}
