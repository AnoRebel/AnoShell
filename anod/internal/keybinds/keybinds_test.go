package keybinds

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

const bundled = "../../../external"

func needLua(t *testing.T) {
	if _, err := exec.LookPath("lua"); err != nil {
		t.Skip("no lua")
	}
}

func TestNormalizeChord(t *testing.T) {
	for in, want := range map[string]string{
		"SUPER + SHIFT + left":                "Super+Shift+Left",
		"Mod+Shift+Left":                      "Super+Shift+Left",
		"CTRL + SUPER + T":                    "Super+Ctrl+T",
		"Ctrl+Mod+T":                          "Super+Ctrl+T",
		"SUPER, T":                            "Super+T",
		"SUPER + mouse_down":                  "Super+WheelScrollDown",
		"Mod+WheelScrollDown":                 "Super+WheelScrollDown",
		"SUPER + bracketleft":                 "Super+BracketLeft",
		"XF86AudioPlay":                       "XF86AudioPlay",
		"SUPER + Super_L":                     "Super+Super_L",
		"CTRL + SHIFT + ALT + SUPER + Delete": "Super+Ctrl+Alt+Shift+Delete",
	} {
		if got := NormalizeChord(in); got != want {
			t.Errorf("%q → %q, want %q", in, got, want)
		}
	}
	if hyprChord("Super+Ctrl+WheelScrollDown") != "SUPER + CTRL + mouse_down" || niriChord("Super+Shift+Q") != "Mod+Shift+Q" {
		t.Error("chord rendering")
	}
}

func eq(a, b Bind) bool {
	ja, _ := json.Marshal(a)
	jb, _ := json.Marshal(b)
	return string(ja) == string(jb)
}

// Rendering the bundled binds and reading them back gives the same binds.
func TestBundledRoundTrip(t *testing.T) {
	needLua(t)
	hp := filepath.Join(bundled, "hyprland", "hyprland.lua")
	h, err := ReadHyprland(hp)
	if err != nil {
		t.Fatal(err)
	}
	n, err := ReadNiri(filepath.Join(bundled, "niri", "ano.kdl"))
	if err != nil {
		t.Fatal(err)
	}
	if len(h) < 150 || len(n) < 100 {
		t.Fatalf("read %d hyprland and %d niri binds", len(h), len(n))
	}
	src, _ := os.ReadFile(hp)
	dir := t.TempDir()
	gl := filepath.Join(dir, "binds.lua")
	os.WriteFile(gl, []byte(HyprlandLua(h, Helpers(string(src), h))), 0o644)
	h2, err := ReadHyprland(gl)
	if err != nil {
		t.Fatal(err)
	}
	if len(h2) != len(h) {
		t.Fatalf("hyprland: %d binds back, want %d", len(h2), len(h))
	}
	for i := range h {
		if !eq(h[i], h2[i]) {
			a, _ := json.Marshal(h[i])
			b, _ := json.Marshal(h2[i])
			t.Errorf("hyprland bind %d:\n got %s\nwant %s", i, b, a)
		}
	}
	gk := filepath.Join(dir, "binds.kdl")
	os.WriteFile(gk, []byte(NiriKDL(n)), 0o644)
	n2, err := ReadNiri(gk)
	if err != nil {
		t.Fatal(err)
	}
	if len(n2) != len(n) {
		t.Fatalf("niri: %d binds back, want %d", len(n2), len(n))
	}
	for i := range n {
		if !eq(n[i], n2[i]) {
			a, _ := json.Marshal(n[i])
			b, _ := json.Marshal(n2[i])
			t.Errorf("niri bind %d:\n got %s\nwant %s", i, b, a)
		}
	}
}

// Every bundled bind is in the merged set for its compositor, or reported.
func TestMergeAccountsForEveryBind(t *testing.T) {
	needLua(t)
	h, _ := ReadHyprland(filepath.Join(bundled, "hyprland", "hyprland.lua"))
	n, _ := ReadNiri(filepath.Join(bundled, "niri", "ano.kdl"))
	out, conflicts := Merge(h, n)
	reported := map[string]bool{}
	for _, c := range conflicts {
		reported[c.Chord] = true
	}
	for comp, set := range map[string][]Bind{"hyprland": h, "niri": n} {
		kept := 0
		for _, b := range set {
			found := false
			for _, o := range out {
				if o.On(comp) && o.Key() == b.Key() && Same(o, b) {
					found = true
					break
				}
			}
			switch {
			case found:
				kept++
			case !reported[b.Chord]:
				t.Errorf("%s bind %s → %s is neither kept nor reported", comp, b.Chord, b.Describe())
			}
		}
		t.Logf("%s: %d of %d bundled binds kept as is", comp, kept, len(set))
	}
}
