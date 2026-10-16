package main

import "testing"

func TestAwwwTransition(t *testing.T) {
	for _, c := range []struct{ typ, dir, want string }{
		{"crossfade", "right", "fade"},
		{"", "right", "fade"},
		{"bogus", "right", "fade"},
		{"zoom", "right", "grow"},
		{"slideRight", "right", "left"},
		{"slideRight", "left", "right"},
		{"slideRight", "down", "top"},
		{"slideRight", "up", "bottom"},
		{"none", "right", "none"},
		{"wave", "right", "wave"},
	} {
		if got := awwwTransition(c.typ, c.dir); got != c.want {
			t.Errorf("awwwTransition(%q, %q) = %q, want %q", c.typ, c.dir, got, c.want)
		}
	}
}
