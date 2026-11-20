package main

import (
	"os"
	"reflect"
	"strings"
	"testing"
)

func TestTerminalArgs(t *testing.T) {
	cat, err := loadCatalog("../../..")
	if err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct {
		term string
		in   []string
		want []string
	}{
		{"kitty", []string{"-e", "btop"}, []string{"btop"}},
		{"/usr/bin/foot", []string{"-e", "ssh", "host"}, []string{"ssh", "host"}},
		{"ghostty", []string{"-e", "btop"}, []string{"-e", "btop"}},
		{"wezterm", []string{"-e", "btop"}, []string{"start", "--", "btop"}},
		{"gnome-terminal", []string{"-e", "btop"}, []string{"--", "btop"}},
		{"unknown-term", []string{"-e", "btop"}, []string{"-e", "btop"}},
		{"kitty", []string{"~/Downloads"}, []string{"~/Downloads"}},
	} {
		if got := terminalArgs(c.term, c.in, cat); !reflect.DeepEqual(got, c.want) {
			t.Errorf("%s %v = %v, want %v", c.term, c.in, got, c.want)
		}
	}
}

func TestLauncherArgv(t *testing.T) {
	home, _ := os.UserHomeDir()
	t.Setenv("ANO_TEST_DIR", "/opt/x")
	cases := []struct {
		m    map[string]any
		want string
	}{
		{map[string]any{}, "qs -c ano ipc call search toggle"},
		{map[string]any{"apps": map[string]any{"launcher": "custom", "launcherCommand": "  "}}, "qs -c ano ipc call search toggle"},
		{map[string]any{"apps": map[string]any{"launcher": "anoshell", "launcherCommand": "rofi -show drun"}}, "qs -c ano ipc call search toggle"},
		{map[string]any{"apps": map[string]any{"launcher": "custom", "launcherCommand": "~/.config/rofi/scripts/launcher.sh --x"}}, home + "/.config/rofi/scripts/launcher.sh --x"},
		{map[string]any{"apps": map[string]any{"launcher": "custom", "launcherCommand": "$ANO_TEST_DIR/run; rm -rf ~"}}, "/opt/x/run; rm -rf " + home},
	}
	for _, c := range cases {
		if got := strings.Join(launcherArgv(c.m), " "); got != c.want {
			t.Errorf("%v: got %q want %q", c.m, got, c.want)
		}
	}
}
