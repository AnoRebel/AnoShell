package looks

import (
	"encoding/json"
	"path/filepath"
	"runtime"
	"testing"
)

func TestBundledLooksAreValid(t *testing.T) {
	_, here, _, _ := runtime.Caller(0)
	files, _ := filepath.Glob(filepath.Join(filepath.Dir(here), "../../../looks/*.json"))
	if len(files) < 4 {
		t.Fatalf("want the 4 built-in looks, found %d", len(files))
	}
	for _, f := range files {
		if e := Check(f); len(e.Errors) > 0 {
			t.Errorf("%s: %v", f, e.Errors)
		}
	}
}

func TestValidateRejects(t *testing.T) {
	var v any
	json.Unmarshal([]byte(`{"id":"x","name":"X","shape":{"radiusScale":9},"material":{"kind":"wood"},
		"texture":{"shader":"fire"},"typography":{"main":"@weird","title":3},"motion":{"bounce":{},"settle":{"damping":2}}}`), &v)
	if got := Validate(v, "y"); len(got) != 8 {
		t.Fatalf("want 8 errors, got %d: %q", len(got), got)
	}
	if got := Validate([]any{}, "x"); len(got) != 1 {
		t.Fatal("a non-object must fail")
	}
}
