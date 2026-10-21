package main

import (
	"reflect"
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
