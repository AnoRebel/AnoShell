package atelier

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"

	"ano/anod/internal/keybinds"
)

// A rice's keybinds layer is code: binds can run commands, and the
// compositor reloads them. Only catalogue actions with checked arguments
// are kept; raw Lua/KDL binds, per-bind compositor properties, submaps and
// hyprlandHelpers (raw Lua) are dropped and reported.

// KeybindSummary is one bind the keybinds layer would set.
type KeybindSummary struct {
	Chord   string `json:"chord"`
	Action  string `json:"action"` // catalogue id, or "unbind"
	Label   string `json:"label"`
	Command string `json:"command,omitempty"` // exec binds: the command line
}

var chordRe = regexp.MustCompile(`^[A-Za-z0-9_+\-]+$`)

// riceKeybinds reads and sanitises a rice's keybinds.json. dropped says
// what was left out and why; an unreadable file is an error.
func riceKeybinds(path string) (o keybinds.Overrides, summary []KeybindSummary, dropped []string, err error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return o, nil, nil, err
	}
	var in keybinds.Overrides
	d := json.NewDecoder(bytes.NewReader(b))
	d.DisallowUnknownFields()
	if err := d.Decode(&in); err != nil {
		return o, nil, nil, fmt.Errorf("keybinds.json: %v", err)
	}
	summary = []KeybindSummary{}
	if strings.TrimSpace(in.HyprHelpers) != "" {
		dropped = append(dropped, "hyprlandHelpers (raw Lua) is never applied from a rice")
	}
	for _, x := range in.Binds {
		_, known := keybinds.Catalogue[x.Action]
		switch {
		case !chordRe.MatchString(x.Chord):
			dropped = append(dropped, fmt.Sprintf("%q: not a plain chord", x.Chord))
		case !known || x.Raw:
			dropped = append(dropped, fmt.Sprintf("%s: %q is raw compositor code, not a catalogue action", x.Chord, x.Action))
		case x.Hypr != nil || x.Niri != nil || x.Submap != "":
			dropped = append(dropped, fmt.Sprintf("%s: compositor-specific bind properties and submaps aren't applied from a rice", x.Chord))
		case keybinds.CheckArgs(x) != nil:
			dropped = append(dropped, fmt.Sprintf("%s: %v", x.Chord, keybinds.CheckArgs(x)))
		default:
			x.Chord = keybinds.NormalizeChord(x.Chord)
			o.Binds = append(o.Binds, x)
			s := KeybindSummary{Chord: x.Chord, Action: x.Action, Label: x.Describe()}
			if x.Action == "exec" {
				s.Command = x.Args[0]
			}
			summary = append(summary, s)
		}
	}
	for _, c := range in.Remove {
		if !chordRe.MatchString(c) {
			dropped = append(dropped, fmt.Sprintf("remove %q: not a plain chord", c))
			continue
		}
		c = keybinds.NormalizeChord(c)
		o.Remove = append(o.Remove, c)
		summary = append(summary, KeybindSummary{Chord: c, Action: "unbind", Label: "unbound"})
	}
	return o, summary, dropped, nil
}

// auditKeybinds runs the per-line rules over the commands the binds run;
// a finding's file names the chord and line 1 is the command line.
func auditKeybinds(summary []KeybindSummary, hosts, commands []string) []Finding {
	out := []Finding{}
	add := func(rule, file string, line int, detail string) {
		sev := "warn"
		if highRules[rule] {
			sev = "high"
		}
		out = append(out, Finding{rule, file, line, detail, sev})
	}
	for _, s := range summary {
		if s.Command == "" {
			continue
		}
		file := "keybinds.json (" + s.Chord + ")"
		auditText(file, "sh", []byte(s.Command), hosts, commands, add)
		if f := strings.Fields(s.Command); len(f) > 0 {
			name := f[0]
			if i := strings.LastIndexByte(name, '/'); i >= 0 {
				name = name[i+1:]
			}
			if !harmlessCommands[name] && !declared(name, commands) {
				add("undeclared-command", file, 1, fmt.Sprintf("binds a key to %q, which the rice doesn't declare", name))
			}
		}
	}
	return out
}
