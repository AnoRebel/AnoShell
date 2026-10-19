package main

import (
	"strings"
	"testing"
)

func TestResolveApp(t *testing.T) {
	cat := map[string][]appEntry{"terminal": {{Command: "kitty"}, {Command: "ghostty"}, {Command: "alacritty"}}}
	installed := func(set ...string) func(string) bool {
		return func(b string) bool { return strings.Contains(" "+strings.Join(set, " ")+" ", " "+b+" ") }
	}
	for _, c := range []struct {
		configured string
		have       []string
		want       string
	}{
		{"", []string{"kitty", "ghostty", "alacritty"}, "kitty"}, // the preferred default
		{"ghostty", []string{"kitty", "ghostty"}, "ghostty"},     // the user's pick
		{"kitty -1", []string{"kitty"}, "kitty -1"},              // with its arguments
		{"kitty", []string{"ghostty", "alacritty"}, "ghostty"},   // preferred missing: next installed
		{"wezterm", []string{"alacritty"}, "alacritty"},          // pick missing: first installed
	} {
		got, err := resolveApp("terminal", c.configured, cat, installed(c.have...))
		if err != nil || strings.Join(got, " ") != c.want {
			t.Errorf("%q with %v: %v %v, want %q", c.configured, c.have, got, err, c.want)
		}
	}
	if _, err := resolveApp("terminal", "", cat, installed()); err == nil {
		t.Error("no terminal installed should be an error")
	}
}
