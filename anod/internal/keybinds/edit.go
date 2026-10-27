package keybinds

import (
	"fmt"
	"regexp"
	"strings"
)

var (
	intArg      = regexp.MustCompile(`^-?\d+$`)
	relArg      = regexp.MustCompile(`^[er]?[+-]\d+$`)
	shellArgRE  = regexp.MustCompile(`^[A-Za-z0-9_.:/@%+=,-]+$`)
	argCheckers = map[string]func([]string) error{
		"workspace.focus":          oneArg(intArg, "a workspace number"),
		"window.toWorkspace":       oneArg(intArg, "a workspace number"),
		"window.toWorkspaceSilent": oneArg(intArg, "a workspace number"),
		"workspace.relative":       oneArg(relArg, "e+1, e-1, r+1, +1 …"),
		"exec": func(a []string) error {
			if len(a) != 1 || strings.TrimSpace(a[0]) == "" || strings.ContainsAny(a[0], "\n\r") {
				return fmt.Errorf("want one command line")
			}
			return nil
		},
		"shell": func(a []string) error { // qs ipc call target method [args]: plain words only
			if len(a) < 2 {
				return fmt.Errorf("want a target and a method")
			}
			for _, w := range a {
				if !shellArgRE.MatchString(w) {
					return fmt.Errorf("%q: shell action words are letters, digits and . : / @ %% + = , - _", w)
				}
			}
			return nil
		},
	}
)

func oneArg(re *regexp.Regexp, what string) func([]string) error {
	return func(a []string) error {
		if len(a) != 1 || !re.MatchString(a[0]) {
			return fmt.Errorf("want %s", what)
		}
		return nil
	}
}

// checkArgs refuses arguments the renderers can't put safely into Lua/KDL.
// CheckArgs reports whether b's arguments suit its action.
func CheckArgs(b Bind) error { return checkArgs(b) }

func checkArgs(b Bind) error {
	if b.Action == "hyprland" || b.Action == "niri" {
		if len(b.Args) != 1 || strings.TrimSpace(b.Args[0]) == "" {
			return fmt.Errorf("a native action needs its text")
		}
		return nil
	}
	if f := argCheckers[b.Action]; f != nil {
		return f(b.Args)
	}
	if len(b.Args) != 0 {
		return fmt.Errorf("%s takes no argument", b.Action)
	}
	return nil
}

// ConflictError names the binds a new chord would replace (Settings offers Replace/Cancel).
type ConflictError struct{ Existing []Bind }

func (e *ConflictError) Error() string {
	s := "already bound:"
	for _, b := range e.Existing {
		s += " " + b.Describe() + ";"
	}
	return s
}

// Set binds chord to b (b == nil removes the chord). Without replace, a
// chord already in use returns *ConflictError and changes nothing.
func Set(d Defaults, o Overrides, chord, submap string, b *Bind, replace bool) (Overrides, error) {
	chord = NormalizeChord(chord)
	if chord == "" {
		return o, fmt.Errorf("empty chord")
	}
	key := submap + "\x00" + chord
	if b != nil && !replace {
		if used := ChordUsers(Effective(d, o), chord, submap); len(used) > 0 {
			return o, &ConflictError{used}
		}
	}
	var keep []Bind
	for _, x := range o.Binds {
		x.Chord = NormalizeChord(x.Chord)
		if x.Key() != key {
			keep = append(keep, x)
		}
	}
	o.Binds = keep
	var rm []string
	for _, c := range o.Remove {
		if NormalizeChord(c) != chord {
			rm = append(rm, c)
		}
	}
	o.Remove = rm
	if b == nil {
		if submap == "" {
			o.Remove = append(o.Remove, chord)
		}
		return o, nil
	}
	nb := *b
	nb.Chord, nb.Submap = chord, submap
	if _, ok := Catalogue[nb.Action]; !ok && nb.Action != "hyprland" && nb.Action != "niri" {
		return o, fmt.Errorf("unknown action %q", nb.Action)
	}
	if err := checkArgs(nb); err != nil {
		return o, fmt.Errorf("%s: %w", nb.Action, err)
	}
	o.Binds = append(o.Binds, nb)
	return o, nil
}

// Reset drops the user's change to chord ("" = every change).
func Reset(o Overrides, chord string) Overrides {
	if chord == "" {
		return Overrides{}
	}
	chord = NormalizeChord(chord)
	var keep []Bind
	for _, x := range o.Binds {
		if NormalizeChord(x.Chord) != chord {
			keep = append(keep, x)
		}
	}
	var rm []string
	for _, c := range o.Remove {
		if NormalizeChord(c) != chord {
			rm = append(rm, c)
		}
	}
	return Overrides{Binds: keep, Remove: rm}
}
