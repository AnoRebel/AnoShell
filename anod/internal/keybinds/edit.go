package keybinds

import "fmt"

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
