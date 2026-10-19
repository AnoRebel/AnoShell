package keybinds

import "os"

// Active is what the running compositor binds right now: ano's effective set
// once migrated, else what its own config says (read like the importer).
// Unbound lists the shipped shell actions nothing triggers.
func Active(p Paths, comp string) (binds []Bind, unbound []Bind, err error) {
	d, err := LoadDefaults()
	if err != nil {
		return nil, nil, err
	}
	if Migrated(p) {
		o, err := LoadOverrides(p.Overrides)
		if err != nil {
			return nil, nil, err
		}
		for _, b := range Effective(d, o) {
			if b.On(comp) {
				binds = append(binds, b)
			}
		}
	} else {
		switch comp {
		case "hyprland":
			if _, err := os.Stat(p.HyprMain); err == nil {
				binds, err = ReadHyprland(p.HyprMain)
				if err != nil {
					return nil, nil, err
				}
			}
		case "niri":
			if _, err := os.Stat(p.NiriMain); err == nil {
				binds, err = ReadNiri(p.NiriMain)
				if err != nil {
					return nil, nil, err
				}
			}
		}
	}
	have := map[string]bool{}
	for _, b := range binds {
		if b.Action == "shell" {
			have[b.Describe()] = true
		}
	}
	seen := map[string]bool{}
	for _, b := range d.Binds {
		if b.Action == "shell" && !have[b.Describe()] && !seen[b.Describe()] {
			seen[b.Describe()] = true
			unbound = append(unbound, b)
		}
	}
	return binds, unbound, nil
}
