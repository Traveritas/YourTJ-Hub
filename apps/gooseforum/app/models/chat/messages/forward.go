package messages

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

const ForwardType int8 = 4
const MaxForwardMessages = 50
const MaxForwardBytes = 64 << 10

// ForwardedBundle is an immutable copy, not a grant to the source conversation.
// It deliberately carries no conversation/message IDs or private notes.
type ForwardedBundle struct {
	Version  int              `json:"version"`
	Messages []ForwardedEntry `json:"messages"`
}
type ForwardedEntry struct {
	SenderName string `json:"senderName"`
	AvatarURL  string `json:"avatarUrl,omitempty"`
	Content    string `json:"content"`
	CreatedAt  string `json:"createdAt"`
	MsgType    int8   `json:"msgType"`
}

func ParseForward(content string) *ForwardedBundle {
	if len(content) > MaxForwardBytes {
		return nil
	}
	var value ForwardedBundle
	if json.Unmarshal([]byte(content), &value) != nil || value.Version != 1 || len(value.Messages) == 0 || len(value.Messages) > MaxForwardMessages {
		return nil
	}
	for _, entry := range value.Messages {
		if entry.MsgType < 1 || entry.MsgType > 3 {
			return nil
		}
	}
	return &value
}
func (bundle *ForwardedBundle) Encode() (string, error) {
	raw, err := json.Marshal(bundle)
	if err != nil {
		return "", err
	}
	if ParseForward(string(raw)) == nil {
		return "", errors.New("invalid or oversized forwarded messages")
	}
	return string(raw), nil
}
func (bundle *ForwardedBundle) Text() string {
	var text strings.Builder
	text.WriteString("[Chat history]")
	for _, entry := range bundle.Messages {
		fmt.Fprintf(&text, "\n%s: %s", entry.SenderName, entry.Content)
	}
	return text.String()
}
func DisplayContent(content string, msgType int8) string {
	if msgType != ForwardType {
		return content
	}
	if bundle := ParseForward(content); bundle != nil {
		return bundle.Text()
	}
	return "[Chat history unavailable]"
}
