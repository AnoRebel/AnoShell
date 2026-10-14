package config

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func schema(t *testing.T) *Schema {
	t.Helper()
	s, err := LoadSchema()
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func load(t *testing.T, name string) map[string]any {
	t.Helper()
	m, err := Load(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestValidateTypes(t *testing.T) {
	got := map[string]string{}
	for _, is := range schema(t).Validate(load(t, "types.json")) {
		got[is.Key] = is.Level + ": " + is.Msg
	}
	want := map[string]string{
		"bar.showBackground": "error: expected bool, got string",
		"bar.autoHide.delay": "error: expected int, got real",
		"dock":               "error: expected an object, got int",
		"bogus":              "warning: unknown key (not in the schema; the shell ignores it)",
	}
	if len(got) != len(want) {
		t.Errorf("issues = %v", got)
	}
	for k, w := range want {
		if got[k] != w {
			t.Errorf("%s: got %q, want %q", k, got[k], w)
		}
	}
}

func TestBundledConfigIsValid(t *testing.T) {
	m, err := Load("../../../config.json")
	if err != nil {
		t.Fatal(err)
	}
	for _, is := range schema(t).Validate(m) {
		t.Errorf("bundled config.json: %s", is)
	}
}

func TestValidateHintsRenamedKeys(t *testing.T) {
	for _, is := range schema(t).Validate(load(t, "legacy.json")) {
		if is.Key == "hud.enabled" && !strings.Contains(is.Msg, "renamed to hud.enable") {
			t.Errorf("hint = %s", is.Msg)
		}
	}
}

func TestMigrate(t *testing.T) {
	m := load(t, "legacy.json")
	log := Migrate(m, schema(t), false)
	if v, _ := Get(m, "hud.enable"); v != false {
		t.Errorf("hud.enable = %v", v)
	}
	if _, ok := Get(m, "hud.enabled"); ok {
		t.Error("hud.enabled kept")
	}
	if v, _ := Get(m, "anoSpot.enable"); v != true {
		t.Error("activSpot not moved")
	}
	if v, _ := Get(m, "appearance.theme.name"); v != "nord" {
		t.Errorf("theme.name = %v", v)
	}
	// bar.bars is dropped because top-level bars already exists.
	if _, ok := Get(m, "bar.bars"); ok {
		t.Error("bar.bars kept")
	}
	if v, _ := Get(m, "bar.autoHide.enable"); v != true {
		t.Errorf("autoHide.enable = %v", v)
	}
	if v, _ := Get(m, "bar.showBackground"); v != false {
		t.Errorf("showBackground = %v", v)
	}
	b0 := m["bars"].([]any)[0].(map[string]any)
	if b0["autoHide"] != nil || b0["showBackground"] != nil {
		t.Errorf("bars[0] overrides kept: %v", b0)
	}
	// Unknown keys stay unless pruning was asked for.
	if _, ok := Get(m, "bar.modulesLeft"); !ok {
		t.Error("unknown key removed without --prune-unknown")
	}
	if len(log) != 6 {
		t.Errorf("log = %v", log)
	}
	// Idempotent.
	if again := Migrate(m, schema(t), false); len(again) != 0 {
		t.Errorf("second run changed: %v", again)
	}
	Migrate(m, schema(t), true)
	if _, ok := Get(m, "bar.modulesLeft"); ok {
		t.Error("prune kept unknown key")
	}
	if _, ok := Get(m, "bar.autoHide.enable"); !ok {
		t.Error("prune removed a known key")
	}
}

func TestMigrateFileWritesBackup(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "config.json")
	orig, _ := os.ReadFile("testdata/legacy.json")
	os.WriteFile(p, orig, 0o644)
	now := time.Date(2026, 10, 14, 13, 5, 9, 0, time.UTC)

	backup, log, err := MigrateFile(p, schema(t), false, false, now)
	if err != nil {
		t.Fatal(err)
	}
	if backup != p+".bak-20261014-130509" {
		t.Errorf("backup = %s", backup)
	}
	if b, _ := os.ReadFile(backup); string(b) != string(orig) {
		t.Error("backup differs from original")
	}
	var out map[string]any
	b, _ := os.ReadFile(p)
	if err := json.Unmarshal(b, &out); err != nil || len(log) == 0 {
		t.Fatalf("rewritten file: %v %v", err, log)
	}
	if _, ok := Get(out, "hud.enabled"); ok {
		t.Error("file not migrated")
	}

	// Nothing to do: no new backup.
	backup, log, _ = MigrateFile(p, schema(t), false, false, now.Add(time.Second))
	if backup != "" || len(log) != 0 {
		t.Errorf("no-op run wrote %q %v", backup, log)
	}
	// Dry run reports but doesn't touch the file.
	os.WriteFile(p, orig, 0o644)
	_, log, _ = MigrateFile(p, schema(t), false, true, now)
	if b, _ := os.ReadFile(p); string(b) != string(orig) || len(log) == 0 {
		t.Error("dry run modified the file")
	}
}

func TestMergeAndGetters(t *testing.T) {
	base, _ := Parse([]byte(`{"a":{"b":1,"c":true},"arr":[1,2]}`))
	over, _ := Parse([]byte(`{"a":{"b":2},"arr":[3]}`))
	m := Merge(base, over)
	if Int(m, "a.b", 0) != 2 || !Bool(m, "a.c", false) || len(m["arr"].([]any)) != 1 {
		t.Errorf("merge = %v", m)
	}
	if String(m, "a.missing", "d") != "d" {
		t.Error("default not used")
	}
}
