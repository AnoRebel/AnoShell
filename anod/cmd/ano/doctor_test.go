package main

import (
	"strings"
	"testing"

	"ano/anod/internal/config"
)

// The feature table must only gate on keys that exist and are bools (path=value: strings).
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
			want := "bool"
			if key, _, ok := strings.Cut(k, "="); ok {
				k, want = key, "string"
			}
			if typ, ok := s.Leaves[k]; !ok || typ != want {
				t.Errorf("%s: %q is %q in the schema, want %s", f.Name, k, typ, want)
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

func TestAnyBoolValue(t *testing.T) {
	m := map[string]any{"lock": map[string]any{"locker": "shell"}, "pet": map[string]any{"sound": true}}
	if !anyBool(m, "lock.locker=shell") || anyBool(m, "lock.locker=external") {
		t.Fatal("path=value compares the string")
	}
	if !anyBool(m, "lock.locker=external|pet.sound") || anyBool(m, "lock.missing=shell") {
		t.Fatal("alternatives and missing keys")
	}
}
