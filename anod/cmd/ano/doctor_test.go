package main

import (
	"strings"
	"testing"

	"ano/anod/internal/config"
)

// The feature table must only gate on keys that exist and are bools.
func TestFeatureKeysExistInSchema(t *testing.T) {
	s, err := config.LoadSchema()
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range features {
		if f.When == "" {
			continue
		}
		for _, k := range strings.Split(f.When, "|") {
			if typ, ok := s.Leaves[k]; !ok || typ != "bool" {
				t.Errorf("%s: %q is %q in the schema, want bool", f.Name, k, typ)
			}
		}
	}
}

func TestDoctorFailsWithoutRequiredDeps(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	failed := false
	for _, c := range runChecks() {
		if c.Name == "required: qs" && c.Level == "fail" {
			failed = true
		}
	}
	if !failed {
		t.Error("missing qs not reported as a failure")
	}
}
