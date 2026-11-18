package display

import (
	"strings"
	"testing"
)

func TestTerminalRules(t *testing.T) {
	if hyprTerminal(nil) != "" || hyprTerminal(&TerminalLook{Translucent: true, Blur: true}) != "" || hyprTerminal(&TerminalLook{Blur: false}) != "" {
		t.Fatal("hyprland: a rule only for translucent terminals with blur off")
	}
	h := hyprTerminal(&TerminalLook{Translucent: true})
	if !strings.Contains(h, `no_blur = true`) || !strings.Contains(h, `com\\.mitchellh\\.ghostty`) {
		t.Fatalf("hyprland rule: %s", h)
	}
	if niriTerminal(&TerminalLook{Translucent: true}) != "" || niriTerminal(&TerminalLook{Blur: true}) != "" {
		t.Fatal("niri: a rule only for translucent terminals with blur on")
	}
	n := niriTerminal(&TerminalLook{Translucent: true, Blur: true})
	if !strings.Contains(n, `match app-id=r#"^(kitty|foot|footclient|com\.mitchellh\.ghostty|Alacritty)$"#`) || !strings.Contains(n, "blur true") {
		t.Fatalf("niri rule: %s", n)
	}
}
