package keybinds

import (
	_ "embed"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

//go:embed defaults.json
var defaultsJSON []byte

// Defaults is the shipped set (built by cmd/keybinds-import from ano/external).
type Defaults struct {
	Helpers string `json:"hyprlandHelpers"`
	Binds   []Bind `json:"binds"`
}

func LoadDefaults() (Defaults, error) {
	var d Defaults
	return d, json.Unmarshal(defaultsJSON, &d)
}

// Overrides is the user's keybinds.json: binds added or replacing a chord,
// and chords removed. New shipped defaults on other chords still apply.
type Overrides struct {
	Binds  []Bind   `json:"binds,omitempty"`
	Remove []string `json:"remove,omitempty"`
}

func configHome() string {
	if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {
		return d
	}
	h, _ := os.UserHomeDir()
	return filepath.Join(h, ".config")
}

// Paths are the files ano owns or touches.
type Paths struct {
	Overrides string // ~/.config/anoshell/keybinds.json
	HyprBinds string // ~/.config/hypr/ano-managed-binds.lua
	NiriBinds string // ~/.config/niri/ano-managed-binds.kdl
	HyprMain  string // ~/.config/hypr/hyprland.lua
	NiriMain  string // ~/.config/niri/config.kdl
}

func DefaultPaths() Paths {
	c := configHome()
	return Paths{
		Overrides: filepath.Join(c, "anoshell", "keybinds.json"),
		HyprBinds: filepath.Join(c, "hypr", "ano-managed-binds.lua"),
		NiriBinds: filepath.Join(c, "niri", "ano-managed-binds.kdl"),
		HyprMain:  filepath.Join(c, "hypr", "hyprland.lua"),
		NiriMain:  filepath.Join(c, "niri", "config.kdl"),
	}
}

func LoadOverrides(path string) (Overrides, error) {
	var o Overrides
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return o, nil
	}
	if err != nil {
		return o, err
	}
	return o, json.Unmarshal(b, &o)
}

func SaveOverrides(path string, o Overrides) error {
	b, err := json.MarshalIndent(o, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return writeAtomic(path, append(b, '\n'), 0o644)
}

// Effective is the defaults with the user's overrides applied. A user bind
// replaces the defaults on its chord (in its submap) on the compositors it
// applies to; on the other one the default stays. Removed chords go.
func Effective(d Defaults, o Overrides) []Bind {
	drop := map[string]bool{}
	for _, c := range o.Remove {
		drop["\x00"+NormalizeChord(c)] = true
	}
	user := make([]Bind, len(o.Binds))
	covers := map[string]map[string]bool{} // key → compositors the user binds there
	for i, b := range o.Binds {
		b.Chord = NormalizeChord(b.Chord)
		user[i] = b
		if covers[b.Key()] == nil {
			covers[b.Key()] = map[string]bool{}
		}
		for _, c := range []string{"hyprland", "niri"} {
			if b.On(c) {
				covers[b.Key()][c] = true
			}
		}
	}
	var out []Bind
	for _, b := range d.Binds {
		if drop[b.Key()] {
			continue
		}
		if cv := covers[b.Key()]; cv != nil {
			var keep []string
			for _, c := range []string{"hyprland", "niri"} {
				if b.On(c) && !cv[c] {
					keep = append(keep, c)
				}
			}
			if len(keep) == 0 {
				continue
			}
			if len(keep) == 1 && b.Action != "hyprland" && b.Action != "niri" {
				b.Only = keep[0]
			}
		}
		out = append(out, b)
	}
	return append(out, user...)
}

// Generate writes both managed bind files (only when their text changed)
// and reports which changed.
func Generate(p Paths, binds []Bind, helpers string) (hyprChanged, niriChanged bool, err error) {
	write := func(path, text string) (bool, error) {
		if old, err := os.ReadFile(path); err == nil && string(old) == text {
			return false, nil
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return false, err
		}
		return true, writeAtomic(path, []byte(text), 0o644)
	}
	if hyprChanged, err = write(p.HyprBinds, HyprlandLua(binds, helpers)); err != nil {
		return
	}
	niriChanged, err = write(p.NiriBinds, NiriKDL(binds))
	return
}

// Migrated reports whether the compositor configs include ano's binds.
func Migrated(p Paths) bool {
	_, err := os.Stat(manifestPath(p))
	return err == nil
}

// Reload makes the running compositor pick up the generated binds: Hyprland
// re-reads its config; niri watches included files itself. Before migration
// the files aren't included, so there is nothing to reload.
func Reload() error {
	if !Migrated(DefaultPaths()) {
		return nil
	}
	if os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "" {
		return exec.Command("hyprctl", "reload").Run()
	}
	return nil
}

func writeAtomic(path string, data []byte, perm os.FileMode) error {
	f, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err := f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err := f.Chmod(perm); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(f.Name(), path)
}

// ChordUsers lists the effective binds that a new bind on chord would replace.
func ChordUsers(binds []Bind, chord, submap string) []Bind {
	key := submap + "\x00" + NormalizeChord(chord)
	var out []Bind
	for _, b := range binds {
		if b.Key() == key {
			out = append(out, b)
		}
	}
	return out
}

// IncludeHyprland is the one line migration adds to hyprland.lua.
const IncludeHyprland = `pcall(dofile, (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/ano-managed-binds.lua") -- ano keybinds (ano keybinds migrate --revert undoes this)`

// IncludeNiri is the one line migration adds at the end of config.kdl.
const IncludeNiri = `include optional=true "ano-managed-binds.kdl" // ano keybinds (ano keybinds migrate --revert undoes this)`

func hasLine(src, line string) bool {
	for _, l := range strings.Split(src, "\n") {
		if strings.TrimSpace(l) == line {
			return true
		}
	}
	return false
}
