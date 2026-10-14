package main

import (
	"errors"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

func TestParseAheadBehind(t *testing.T) {
	a, b, err := parseAheadBehind("3\t5\n")
	if err != nil || a != 3 || b != 5 {
		t.Fatalf("got %d %d %v", a, b, err)
	}
	if _, _, err := parseAheadBehind("garbage"); err == nil {
		t.Fatal("want an error for malformed output")
	}
}

// A dry run prints the step and never executes it.
func TestRunnerDryRun(t *testing.T) {
	r := &runner{dry: true}
	if err := r.run("", "would fail", "/nonexistent/binary"); err != nil {
		t.Fatalf("dry run executed the command: %v", err)
	}
}

// The menu lists every action, and a finished run shows its output with the
// result line; a dry run lands on the review screen instead.
func TestTUIScreens(t *testing.T) {
	m := newTUI()
	m.Update(tea.WindowSizeMsg{Width: 100, Height: 40})
	menu := m.View().Content
	for _, a := range actions {
		if !strings.Contains(menu, a.title) {
			t.Errorf("menu is missing %q", a.title)
		}
	}
	m.cur = actions[2]
	m.Update(ranMsg{out: "→ build anod + ano\n  $ bash install.sh", dryRun: true})
	if m.scr != scrReview || !strings.Contains(m.View().Content, "bash install.sh") {
		t.Errorf("dry run: want the plan on the review screen, got screen %d", m.scr)
	}
	m.Update(ranMsg{out: "installed", err: errors.New("exit status 1")})
	if v := m.View().Content; m.scr != scrResult || !strings.Contains(v, "installed") || !strings.Contains(v, "exit status 1") {
		t.Errorf("result screen should show output and the error")
	}
}
