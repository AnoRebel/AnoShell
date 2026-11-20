package display

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// ── sway ──────────────────────────────────────────────────────────────
// GET_OUTPUTS to read, `output <name> …` commands to apply, `output` lines in
// ~/.config/sway/ano-managed.conf to keep (sway reads it once the user's config
// includes it). sway parses a command string, so names are checked first.

type Sway struct {
	Run func(args ...string) ([]byte, error)
}

func (s Sway) run(args ...string) ([]byte, error) {
	if s.Run != nil {
		return s.Run(args...)
	}
	return exec.Command("swaymsg", args...).Output()
}

func (Sway) Name() string { return "sway" }

var swayName = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

func (s Sway) Current() ([]Output, error) {
	b, err := s.run("-r", "-t", "get_outputs")
	if err != nil {
		return nil, err
	}
	var list []struct {
		Name, Make, Model, Serial string
		Active                    bool
		Scale                     float64
		Transform                 string
		Rect                      struct{ X, Y int }
		CurrentMode               *struct {
			Width, Height, Refresh int
		} `json:"current_mode"`
		Modes []struct {
			Width, Height, Refresh int
		}
		AdaptiveSync string `json:"adaptive_sync_status"`
	}
	if err := json.Unmarshal(b, &list); err != nil {
		return nil, err
	}
	var out []Output
	for _, m := range list {
		o := Output{Name: m.Name, Make: m.Make, Model: m.Model, Serial: m.Serial, Enabled: m.Active,
			X: m.Rect.X, Y: m.Rect.Y, Scale: m.Scale, VRR: m.AdaptiveSync == "enabled"}
		if o.Scale <= 0 {
			o.Scale = 1
		}
		for i, t := range niriTransforms { // sway's names are niri's
			if t == m.Transform {
				o.Transform = i
			}
		}
		for _, md := range m.Modes {
			o.Modes = append(o.Modes, fmt.Sprintf("%dx%d@%.3f", md.Width, md.Height, float64(md.Refresh)/1000))
		}
		if m.CurrentMode != nil {
			o.Width, o.Height, o.Refresh = m.CurrentMode.Width, m.CurrentMode.Height, float64(m.CurrentMode.Refresh)/1000
		}
		out = append(out, o)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func (s Sway) Apply(outs []Output) error {
	var cmds []string
	for _, o := range outs {
		c, err := swayOutput(o)
		if err != nil {
			return err
		}
		cmds = append(cmds, c)
	}
	if len(cmds) == 0 {
		return nil
	}
	_, err := s.run(strings.Join(cmds, "; "))
	return err
}

// swayOutput is one `output` command (also a line of the managed file).
func swayOutput(o Output) (string, error) {
	if !swayName.MatchString(o.Name) {
		return "", fmt.Errorf("bad output name %q", o.Name)
	}
	if !o.Enabled {
		return "output " + o.Name + " disable", nil
	}
	if o.Width <= 0 || o.Height <= 0 || o.Refresh < 0 || o.Scale <= 0 {
		return "", fmt.Errorf("bad mode for %s", o.Name)
	}
	vrr := "off"
	if o.VRR {
		vrr = "on"
	}
	// A refresh of 0 (a custom or headless mode): sway picks the rate.
	mode := fmt.Sprintf("%dx%d", o.Width, o.Height)
	if o.Refresh > 0 {
		mode += "@" + strconv.FormatFloat(o.Refresh, 'f', 3, 64) + "Hz"
	}
	return fmt.Sprintf("output %s enable mode %s scale %s transform %s position %d %d adaptive_sync %s",
		o.Name, mode, strconv.FormatFloat(o.Scale, 'f', -1, 64),
		niriTransforms[o.Transform&7], o.X, o.Y, vrr), nil
}
