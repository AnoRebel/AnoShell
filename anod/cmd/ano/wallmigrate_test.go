package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestRotatorMigration(t *testing.T) {
	home := t.TempDir()
	hypr := filepath.Join(home, ".config/hypr/hyprland.lua")
	niri := filepath.Join(home, ".config/niri/config.kdl")
	os.MkdirAll(filepath.Dir(hypr), 0o755)
	os.MkdirAll(filepath.Dir(niri), 0o755)
	os.WriteFile(hypr, []byte("hl.on(\"x\", function()\n\thl.exec_cmd(\"~/.config/awww/scripts/awww_randomize_multi.sh ~/Pictures/hyprwallpapers 120\")\n\t-- hl.exec_cmd(\"awww_randomize.sh ~/old\")\nend)\n"), 0o644)
	os.WriteFile(niri, []byte("spawn-sh-at-startup \"~/.config/awww/scripts/awww_randomize_multi.sh ~/Pictures/hyprwallpapers\"\n"), 0o644)
	cfg := filepath.Join(home, ".config/anoshell/config.json")
	os.MkdirAll(filepath.Dir(cfg), 0o755)
	os.WriteFile(cfg, []byte(`{"bar":{"style":"pill"}}`), 0o644)

	edits := findRotatorAutostarts(home)
	if len(edits) != 2 || edits[0].Dir != "~/Pictures/hyprwallpapers" {
		t.Fatalf("edits: %+v", edits)
	}
	var lua rotatorEdit
	for _, e := range edits {
		if strings.HasSuffix(e.File, ".lua") {
			lua = e
		}
	}
	if lua.Interval != 120 || lua.Line != 2 {
		t.Fatalf("lua edit: %+v", lua)
	}
	backups, err := applyRotatorMigration(edits, cfg, time.Unix(0, 0))
	if err != nil || len(backups) != 3 {
		t.Fatalf("%v %v", backups, err)
	}
	h, _ := os.ReadFile(hypr)
	if !strings.Contains(string(h), "\t-- (anod rotates wallpapers now) hl.exec_cmd") {
		t.Fatalf("hypr not commented: %s", h)
	}
	n, _ := os.ReadFile(niri)
	if !strings.HasPrefix(string(n), "// (anod rotates wallpapers now) spawn-sh-at-startup") {
		t.Fatalf("niri not commented: %s", n)
	}
	var c map[string]any
	b, _ := os.ReadFile(cfg)
	json.Unmarshal(b, &c)
	r := c["background"].(map[string]any)["randomize"].(map[string]any)
	if r["enable"] != true || c["bar"] == nil {
		t.Fatalf("config: %s", b)
	}
	// Running it again finds nothing (the lines are comments now).
	if again := findRotatorAutostarts(home); len(again) != 0 {
		t.Fatalf("second pass: %+v", again)
	}
}
