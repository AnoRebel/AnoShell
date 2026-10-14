package main

import "testing"

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
