package keybinds

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
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

func copyTree(t *testing.T, src, dst string) {
	t.Helper()
	filepath.Walk(src, func(p string, fi os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, p)
		if fi.IsDir() {
			if fi.Name() == ".backups" {
				return filepath.SkipDir
			}
			return os.MkdirAll(filepath.Join(dst, rel), 0o755)
		}
		b, _ := os.ReadFile(p)
		return os.WriteFile(filepath.Join(dst, rel), b, fi.Mode().Perm())
	})
}

func sum(t *testing.T, p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return fmt.Sprintf("%x", sha256.Sum256(b))
}

// Migration on copies of the bundled configs: afterwards the compositor sees
// exactly the generated binds, the configs keep no bind of their own, and a
// revert restores them byte for byte.
func TestMigrateAndRevert(t *testing.T) {
	needLua(t)
	cfg := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", cfg)
	copyTree(t, filepath.Join(bundled, "hyprland"), filepath.Join(cfg, "hypr"))
	os.MkdirAll(filepath.Join(cfg, "niri"), 0o755)
	kdl, _ := os.ReadFile(filepath.Join(bundled, "niri", "ano.kdl"))
	os.WriteFile(filepath.Join(cfg, "niri", "config.kdl"), kdl, 0o644)
	p := DefaultPaths()
	before := map[string]string{p.HyprMain: sum(t, p.HyprMain), p.NiriMain: sum(t, p.NiriMain),
		filepath.Join(cfg, "hypr", "custom", "keybinds.lua"): sum(t, filepath.Join(cfg, "hypr", "custom", "keybinds.lua"))}

	d, err := LoadDefaults()
	if err != nil {
		t.Fatal(err)
	}
	res, err := Migrate(p, d, time.Date(2026, 10, 19, 5, 0, 0, 0, time.UTC), false)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("moved %v; %d overrides\n%s", res.Moved, res.Overrides, strings.Join(res.Report, "\n"))

	main, _ := os.ReadFile(p.HyprMain)
	for _, l := range strings.Split(string(main), "\n") {
		if strings.Contains(l, "hl.bind(") && !strings.HasPrefix(strings.TrimSpace(l), "--") {
			t.Errorf("bind left in hyprland.lua: %s", l)
		}
	}
	if !strings.Contains(string(main), IncludeHyprland) {
		t.Error("no include line in hyprland.lua")
	}
	if out, err := exec.Command("luac", "-p", p.HyprMain).CombinedOutput(); err != nil {
		t.Errorf("luac: %s", out)
	}
	// What Hyprland would now bind = the effective set for Hyprland.
	got, err := ReadHyprland(p.HyprMain)
	if err != nil {
		t.Fatal(err)
	}
	o, _ := LoadOverrides(p.Overrides)
	var want []Bind
	for _, b := range Effective(d, o) {
		if b.On("hyprland") {
			want = append(want, b)
		}
	}
	if len(got) != len(want) {
		t.Fatalf("hyprland binds after migration: %d, want %d", len(got), len(want))
	}
	nk, _ := os.ReadFile(p.NiriMain)
	if strings.Contains(string(nk), "\nbinds {") || !strings.Contains(string(nk), IncludeNiri) {
		t.Error("niri config still has its binds block, or no include")
	}
	if _, err := exec.LookPath("niri"); err == nil {
		if out, err := exec.Command("niri", "validate", "-c", p.NiriMain).CombinedOutput(); err != nil {
			t.Errorf("niri validate: %s", out)
		}
	}
	// Nothing changes for the user: each compositor still has every bind it had.
	origH, _ := ReadHyprland(filepath.Join(bundled, "hyprland", "hyprland.lua"))
	origN, _ := ReadNiri(filepath.Join(bundled, "niri", "ano.kdl"))
	genN, err := ReadNiri(p.NiriBinds)
	if err != nil {
		t.Fatal(err)
	}
	for comp, pair := range map[string][2][]Bind{"hyprland": {origH, got}, "niri": {origN, genN}} {
		for _, b := range pair[0] {
			found := false
			for _, g := range pair[1] {
				if g.Key() == b.Key() && Same(g, b) {
					found = true
					break
				}
			}
			if !found {
				t.Errorf("%s lost %s → %s", comp, b.Chord, b.Describe())
			}
		}
	}
	if _, err := Migrate(p, d, time.Now(), false); err == nil {
		t.Error("a second migration was allowed")
	}

	if _, err := Revert(p, false); err != nil {
		t.Fatal(err)
	}
	for f, s := range before {
		if sum(t, f) != s {
			t.Errorf("%s differs after revert", f)
		}
	}
}

func TestSetConflictReset(t *testing.T) {
	d := Defaults{Binds: []Bind{
		{Chord: "Super+Space", Action: "shell", Args: []string{"search", "toggle"}},
		{Chord: "Super+Q", Action: "window.close"},
	}}
	var o Overrides
	launcher := &Bind{Action: "shell", Args: []string{"search", "toggle"}}
	// Super+Q is taken: conflict, nothing changes.
	if _, err := Set(d, o, "SUPER + Q", "", launcher, false); err == nil {
		t.Fatal("no conflict reported")
	} else if ce, ok := err.(*ConflictError); !ok || ce.Existing[0].Action != "window.close" {
		t.Fatalf("conflict: %v", err)
	}
	// Rebind the launcher to Super+D, and drop it from Super+Space.
	o, err := Set(d, o, "Super+D", "", launcher, false)
	if err != nil {
		t.Fatal(err)
	}
	o, _ = Set(d, o, "Super+Space", "", nil, false)
	eff := Effective(d, o)
	if len(ChordUsers(eff, "Super+D", "")) != 1 || len(ChordUsers(eff, "Super+Space", "")) != 0 {
		t.Fatalf("effective: %+v", eff)
	}
	// Replace wins over a conflict.
	if o, err = Set(d, o, "Super+Q", "", &Bind{Action: "exec", Args: []string{"kitty"}}, true); err != nil {
		t.Fatal(err)
	}
	if u := ChordUsers(Effective(d, o), "Super+Q", ""); len(u) != 1 || u[0].Action != "exec" {
		t.Fatalf("replace: %+v", u)
	}
	// Reset one, then all: back to the defaults.
	o = Reset(o, "Super+Q")
	if u := ChordUsers(Effective(d, o), "Super+Q", ""); len(u) != 1 || u[0].Action != "window.close" {
		t.Fatal("reset one")
	}
	if eff := Effective(d, Reset(o, "")); len(eff) != len(d.Binds) {
		t.Fatal("reset all")
	}
}

// Parentheses in strings and comments don't fool the stripper, and a bind
// sharing its line with other code stops the migration instead of guessing.
func TestStripHyprBinds(t *testing.T) {
	src := strings.Join([]string{
		`hl.bind("SUPER + A", hl.dsp.exec_cmd("notify-send '(beta'"))`, // 1
		`hl.config({ general = { gaps_in = 5 } })`,                     // 2
		`hl.exec_once("waybar")`,                                       // 3
		`hl.bind("SUPER + B", hl.dsp.exec_cmd("echo")) -- :)`,          // 4
		`hl.bind("SUPER + C",`,                                         // 5
		`	hl.dsp.exec_cmd("say ':('"))`,                                // 6
		`local x = 1 hl.bind("SUPER + D", hl.dsp.window.close())`,      // 7
	}, "\n")
	out, n, err := stripHyprBinds(strings.Join(strings.Split(src, "\n")[:6], "\n"), []int{1, 4, 6})
	if err != nil || n != 3 {
		t.Fatalf("n=%d err=%v", n, err)
	}
	if out != "hl.config({ general = { gaps_in = 5 } })\nhl.exec_once(\"waybar\")" {
		t.Errorf("left:\n%s", out)
	}
	if _, _, err := stripHyprBinds(src, []int{7}); err == nil {
		t.Error("a bind sharing its line with other code was cut")
	}
	if got := maskLua(`a("(") -- (` + "\n" + `--[[ ( ]] b([[)]])`); strings.Count(got, "(") != 2 || strings.Count(got, ")") != 2 {
		t.Errorf("mask: %q", got)
	}
}

func TestSetRejectsBadArgs(t *testing.T) {
	d := Defaults{}
	for _, b := range []Bind{
		{Action: "workspace.focus"},
		{Action: "workspace.focus", Args: []string{"3 })"}},
		{Action: "workspace.relative", Args: []string{"next"}},
		{Action: "exec", Args: []string{""}},
		{Action: "shell", Args: []string{"bar", "toggle; rm -rf ~"}},
		{Action: "window.close", Args: []string{"x"}},
	} {
		if _, err := Set(d, Overrides{}, "Super+K", "", &b, false); err == nil {
			t.Errorf("accepted %+v", b)
		}
	}
	if _, err := Set(d, Overrides{}, "Super+K", "", &Bind{Action: "workspace.focus", Args: []string{"3"}}, false); err != nil {
		t.Error(err)
	}
}
