package main

import (
	"testing"

	"ano/anod/internal/config"
)

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

// scrolling.* comes from config.Load, which decodes numbers as json.Number.
func TestScrollingFromLoadedConfig(t *testing.T) {
	m, err := config.Parse([]byte(`{"scrolling":{"columnWidth":0.5,"workspaces":[{"id":3,"direction":"down"}],"apps":[{"app":"foot","width":0.7}]}}`))
	if err != nil {
		t.Fatal(err)
	}
	s := scrollingFrom(m)
	if s == nil || s.ColumnWidth != 0.5 || len(s.Workspaces) != 1 || s.Workspaces[0].ID != 3 || len(s.Apps) != 1 || s.Apps[0].Width != 0.7 {
		t.Fatalf("scrollingFrom = %+v", s)
	}
}
