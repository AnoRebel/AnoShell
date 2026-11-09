package keybinds

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// A bind niri doesn't accept is reported and the old file stays.
func TestGenerateRejectsBadNiriBind(t *testing.T) {
	if _, err := exec.LookPath("niri"); err != nil {
		t.Skip("no niri")
	}
	dir := t.TempDir()
	p := Paths{HyprBinds: filepath.Join(dir, "h.lua"), NiriBinds: filepath.Join(dir, "n.kdl")}
	good := []Bind{{Chord: "Mod+T", Action: "niri", Args: []string{"spawn \"foot\""}}}
	if _, _, err := Generate(p, good, ""); err != nil {
		t.Fatalf("good binds: %v", err)
	}
	before, _ := os.ReadFile(p.NiriBinds)
	bad := []Bind{{Chord: "Mod+T", Action: "niri", Args: []string{"not-an-action"}}}
	_, _, err := Generate(p, bad, "")
	if err == nil || !strings.Contains(err.Error(), "not-an-action") {
		t.Fatalf("want an error naming the bind, got %v", err)
	}
	after, _ := os.ReadFile(p.NiriBinds)
	if string(after) != string(before) {
		t.Fatal("bad binds were written")
	}
}
