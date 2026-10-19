// Package display applies monitor settings live through the compositor,
// reverts them unless confirmed within a deadline (driven here, so a shell
// crash can't leave a bad mode on screen), persists confirmed settings to
// ano-managed include files, and keeps profiles keyed by the connected
// monitors (spec display-and-cursor, design D11).
package display

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Output is one monitor's settings.
type Output struct {
	Name      string  `json:"name"`
	Make      string  `json:"make,omitempty"`
	Model     string  `json:"model,omitempty"`
	Serial    string  `json:"serial,omitempty"`
	Width     int     `json:"width"`
	Height    int     `json:"height"`
	Refresh   float64 `json:"refresh"` // Hz
	Scale     float64 `json:"scale"`
	X         int     `json:"x"`
	Y         int     `json:"y"`
	Transform int     `json:"transform"` // 0–7, Hyprland's numbering
	VRR       bool    `json:"vrr"`
	Enabled   bool    `json:"enabled"`
	// Modes the monitor offers ("1920x1200@60.026"), for Settings; not applied.
	Modes []string `json:"modes,omitempty"`
}

// ID identifies the physical monitor (survives a port change).
func (o Output) ID() string { return o.Make + "|" + o.Model + "|" + o.Serial }

func (o Output) mode() string {
	r := strconv.FormatFloat(o.Refresh, 'f', 3, 64)
	r = strings.TrimRight(strings.TrimRight(r, "0"), ".")
	return fmt.Sprintf("%dx%d@%s", o.Width, o.Height, r)
}

// Backend talks to one compositor.
type Backend interface {
	Name() string
	Current() ([]Output, error)
	Apply([]Output) error
}

// Fingerprint names a set of connected monitors.
func Fingerprint(outs []Output) string {
	ids := make([]string, 0, len(outs))
	for _, o := range outs {
		ids = append(ids, o.ID())
	}
	sort.Strings(ids)
	return strings.Join(ids, ";")
}

// ── Hyprland ──────────────────────────────────────────────────────────

type Hyprland struct {
	Run func(args ...string) ([]byte, error)
}

func (h Hyprland) run(args ...string) ([]byte, error) {
	if h.Run != nil {
		return h.Run(args...)
	}
	return exec.Command("hyprctl", args...).Output()
}

func (Hyprland) Name() string { return "hyprland" }

func (h Hyprland) Current() ([]Output, error) {
	b, err := h.run("monitors", "all", "-j")
	if err != nil {
		return nil, err
	}
	var ms []struct {
		Name, Make, Model, Serial string
		Width, Height, X, Y       int
		RefreshRate, Scale        float64
		Transform                 int
		VRR                       bool     `json:"vrr"`
		Disabled                  bool     `json:"disabled"`
		AvailableModes            []string `json:"availableModes"`
	}
	if err := json.Unmarshal(b, &ms); err != nil {
		return nil, err
	}
	out := make([]Output, len(ms))
	for i, m := range ms {
		out[i] = Output{Name: m.Name, Make: m.Make, Model: m.Model, Serial: m.Serial, Width: m.Width, Height: m.Height,
			Refresh: m.RefreshRate, Scale: m.Scale, X: m.X, Y: m.Y, Transform: m.Transform, VRR: m.VRR, Enabled: !m.Disabled}
		for _, md := range m.AvailableModes {
			out[i].Modes = append(out[i].Modes, strings.TrimSuffix(md, "Hz"))
		}
	}
	return out, nil
}

// hyprMonitor is the hl.monitor{} call for o (also what ano-managed.lua holds).
func hyprMonitor(o Output) string {
	if !o.Enabled {
		return fmt.Sprintf(`hl.monitor({ output = %q, disabled = true })`, o.Name)
	}
	vrr := 0
	if o.VRR {
		vrr = 1
	}
	return fmt.Sprintf(`hl.monitor({ output = %q, mode = %q, position = "%dx%d", scale = %s, transform = %d, vrr = %d })`,
		o.Name, o.mode(), o.X, o.Y, strconv.FormatFloat(o.Scale, 'f', -1, 64), o.Transform, vrr)
}

func (h Hyprland) Apply(outs []Output) error {
	var calls []string
	for _, o := range outs {
		calls = append(calls, hyprMonitor(o))
	}
	_, err := h.run("eval", strings.Join(calls, "; "))
	return err
}

// ── niri ──────────────────────────────────────────────────────────────

type Niri struct {
	Run func(args ...string) ([]byte, error)
}

func (n Niri) run(args ...string) ([]byte, error) {
	if n.Run != nil {
		return n.Run(args...)
	}
	return exec.Command("niri", args...).Output()
}

func (Niri) Name() string { return "niri" }

var niriTransforms = []string{"normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"}

func (n Niri) Current() ([]Output, error) {
	b, err := n.run("msg", "-j", "outputs")
	if err != nil {
		return nil, err
	}
	var ms map[string]struct {
		Name, Make, Model string
		Serial            *string
		Modes             []struct {
			Width, Height int
			RefreshRate   int `json:"refresh_rate"` // mHz
		}
		CurrentMode *int `json:"current_mode"`
		VRREnabled  bool `json:"vrr_enabled"`
		Logical     *struct {
			X, Y      int
			Scale     float64
			Transform string
		}
	}
	if err := json.Unmarshal(b, &ms); err != nil {
		return nil, err
	}
	var out []Output
	for name, m := range ms {
		o := Output{Name: name, Make: m.Make, Model: m.Model, VRR: m.VRREnabled}
		if m.Serial != nil {
			o.Serial = *m.Serial
		}
		for _, md := range m.Modes {
			o.Modes = append(o.Modes, fmt.Sprintf("%dx%d@%.3f", md.Width, md.Height, float64(md.RefreshRate)/1000))
		}
		if m.CurrentMode != nil && *m.CurrentMode < len(m.Modes) {
			md := m.Modes[*m.CurrentMode]
			o.Width, o.Height, o.Refresh = md.Width, md.Height, float64(md.RefreshRate)/1000
		}
		if m.Logical != nil {
			o.Enabled = true
			o.X, o.Y, o.Scale = m.Logical.X, m.Logical.Y, m.Logical.Scale
			switch m.Logical.Transform { // niri's JSON names
			case "_90":
				o.Transform = 1
			case "_180":
				o.Transform = 2
			case "_270":
				o.Transform = 3
			case "Flipped":
				o.Transform = 4
			case "Flipped90":
				o.Transform = 5
			case "Flipped180":
				o.Transform = 6
			case "Flipped270":
				o.Transform = 7
			}
		}
		out = append(out, o)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

func (n Niri) Apply(outs []Output) error {
	for _, o := range outs {
		base := []string{"msg", "output", o.Name}
		if !o.Enabled {
			if _, err := n.run(append(base, "off")...); err != nil {
				return err
			}
			continue
		}
		vrr := "off"
		if o.VRR {
			vrr = "on"
		}
		for _, a := range [][]string{
			{"on"},
			{"mode", o.mode()},
			{"scale", strconv.FormatFloat(o.Scale, 'f', -1, 64)},
			{"transform", niriTransforms[o.Transform&7]},
			{"position", "set", strconv.Itoa(o.X), strconv.Itoa(o.Y)},
			{"vrr", vrr},
		} {
			if _, err := n.run(append(base, a...)...); err != nil {
				return fmt.Errorf("niri msg output %s %s: %w", o.Name, strings.Join(a, " "), err)
			}
		}
	}
	return nil
}

// niriOutput is the KDL block for ano-managed.kdl.
func niriOutput(o Output) string {
	var b strings.Builder
	fmt.Fprintf(&b, "output %q {\n", o.Name)
	if !o.Enabled {
		b.WriteString("    off\n}\n")
		return b.String()
	}
	fmt.Fprintf(&b, "    mode %q\n    scale %s\n    transform %q\n    position x=%d y=%d\n",
		fmt.Sprintf("%dx%d@%.3f", o.Width, o.Height, o.Refresh), strconv.FormatFloat(o.Scale, 'f', -1, 64),
		niriTransforms[o.Transform&7], o.X, o.Y)
	if o.VRR {
		b.WriteString("    variable-refresh-rate\n")
	}
	b.WriteString("}\n")
	return b.String()
}

// ── Service ───────────────────────────────────────────────────────────

// Profile is a saved arrangement for one set of monitors.
type Profile struct {
	Name        string   `json:"name"`
	Fingerprint string   `json:"fingerprint"`
	Outputs     []Output `json:"outputs"`
}

type Service struct {
	Backend  Backend
	Deadline time.Duration // to confirm a risky change (15 s)
	HyprFile string        // ~/.config/hypr/ano-managed.lua
	NiriFile string        // ~/.config/niri/ano-managed.kdl
	Profiles string        // ~/.config/anoshell/display-profiles.json
	Notify   func(event string, data any)
	Logf     func(string, ...any)
	// Cursor returns the configured cursor (cursor.theme/size), nil if unset.
	Cursor      func() *Cursor
	GtkSettings []string                                // gtk-3.0/4.0 settings.ini (only existing keys are updated)
	Exec        func(name string, args ...string) error // runs hyprctl/gsettings (tests swap it)

	mu       sync.Mutex
	cursor   *Cursor // set by SetCursor before the config catches up
	previous []Output
	pending  []Output
	timer    *time.Timer
	until    time.Time
}

// Pending is the change waiting for confirmation, if any.
type Pending struct {
	Outputs  []Output `json:"outputs"`
	Deadline string   `json:"deadline"`
	Seconds  int      `json:"seconds"`
}

func (s *Service) logf(f string, a ...any) {
	if s.Logf != nil {
		s.Logf("display: "+f, a...)
	}
}

func (s *Service) notify(ev string, data any) {
	if s.Notify != nil {
		s.Notify(ev, data)
	}
}

// Risky says whether a change can leave the screen unusable (mode, scale,
// rotation, disabling): those need confirmation. Moving or VRR don't.
func Risky(old, new []Output) bool {
	byName := map[string]Output{}
	for _, o := range old {
		byName[o.Name] = o
	}
	for _, n := range new {
		o, ok := byName[n.Name]
		if !ok {
			continue
		}
		if n.Enabled != o.Enabled || n.Width != o.Width || n.Height != o.Height || n.Scale != o.Scale ||
			n.Transform != o.Transform || int(n.Refresh+0.5) != int(o.Refresh+0.5) {
			return true
		}
	}
	return false
}

// Apply changes the outputs live. A risky change waits for Confirm until the
// deadline, then the previous settings come back; a safe one is kept now.
func (s *Service) Apply(outs []Output) (*Pending, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.timer != nil {
		return nil, errors.New("another display change is waiting for confirmation")
	}
	cur, err := s.Backend.Current()
	if err != nil {
		return nil, err
	}
	if !anyEnabled(merge(cur, outs)) {
		return nil, errors.New("refusing to turn every monitor off")
	}
	if err := s.Backend.Apply(outs); err != nil {
		s.Backend.Apply(cur) // best effort back to where we were
		return nil, err
	}
	if !Risky(cur, outs) {
		return nil, s.persist(merge(cur, outs))
	}
	d := s.Deadline
	if d <= 0 {
		d = 15 * time.Second
	}
	s.previous, s.pending, s.until = cur, outs, time.Now().Add(d)
	s.timer = time.AfterFunc(d, s.expire)
	p := &Pending{Outputs: outs, Deadline: s.until.Format(time.RFC3339), Seconds: int(d.Seconds())}
	s.notify("display_pending", p)
	return p, nil
}

func (s *Service) expire() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.timer != nil {
		s.logf("not confirmed: reverting")
		s.revertLocked()
	}
}

// revertLocked (mu held) puts the previous settings back.
func (s *Service) revertLocked() {
	s.timer.Stop()
	if err := s.Backend.Apply(s.previous); err != nil {
		s.logf("revert: %v", err)
	}
	s.timer, s.pending = nil, nil
	s.notify("display_reverted", map[string]any{})
}

// Confirm keeps the pending change and persists it.
func (s *Service) Confirm() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.timer == nil {
		return errors.New("nothing to confirm")
	}
	s.timer.Stop()
	s.timer = nil
	all := merge(s.previous, s.pending)
	s.pending = nil
	s.notify("display_confirmed", map[string]any{})
	return s.persist(all)
}

// Revert undoes the pending change now.
func (s *Service) Revert() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.timer == nil {
		return errors.New("nothing to revert")
	}
	s.revertLocked()
	return nil
}

func (s *Service) PendingChange() *Pending {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.timer == nil {
		return nil
	}
	return &Pending{Outputs: s.pending, Deadline: s.until.Format(time.RFC3339), Seconds: int(time.Until(s.until).Seconds())}
}

func anyEnabled(outs []Output) bool {
	for _, o := range outs {
		if o.Enabled {
			return true
		}
	}
	return false
}

// merge overlays changes on the full set, by output name.
func merge(all, changes []Output) []Output {
	out := append([]Output{}, all...)
	for _, c := range changes {
		found := false
		for i := range out {
			if out[i].Name == c.Name {
				id := out[i]
				out[i] = c
				out[i].Make, out[i].Model, out[i].Serial = id.Make, id.Model, id.Serial
				found = true
			}
		}
		if !found {
			out = append(out, c)
		}
	}
	return out
}

// persist writes the managed include file and the profile for this set.
func (s *Service) persist(all []Output) error {
	if err := s.writeManaged(all); err != nil {
		return err
	}
	return s.saveProfile("Last used", all)
}

// writeManaged writes this compositor's ano-managed file: the cursor and the
// monitors. Only that file: the user's own config is never touched.
func (s *Service) writeManaged(all []Output) error {
	c := s.cursor
	if c == nil && s.Cursor != nil {
		c = s.Cursor()
	}
	var b strings.Builder
	switch s.Backend.Name() {
	case "hyprland":
		b.WriteString("-- Generated by anod (Settings → Displays). Do not edit; dofile'd from hyprland.lua.\n")
		if c != nil {
			b.WriteString(hyprCursor(*c))
		}
		for _, o := range all {
			b.WriteString(hyprMonitor(o) + "\n")
		}
		return writeAtomic(s.HyprFile, b.String())
	case "niri":
		b.WriteString("// Generated by anod (Settings → Displays). Do not edit; included from config.kdl.\n")
		if c != nil {
			b.WriteString(niriCursor(*c))
		}
		for _, o := range all {
			b.WriteString(niriOutput(o))
		}
		return writeAtomic(s.NiriFile, b.String())
	}
	return nil
}

// ── Profiles ──────────────────────────────────────────────────────────

func (s *Service) loadProfiles() ([]Profile, error) {
	var ps []Profile
	b, err := os.ReadFile(s.Profiles)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return ps, json.Unmarshal(b, &ps)
}

// saveProfile stores outs under name for their monitor set ("Last used"
// entries are per set, so plugging the dock back in restores that layout).
func (s *Service) saveProfile(name string, outs []Output) error {
	ps, err := s.loadProfiles()
	if err != nil {
		return err
	}
	fp := Fingerprint(outs)
	kept := ps[:0]
	for _, p := range ps {
		if !(p.Fingerprint == fp && p.Name == name) {
			kept = append(kept, p)
		}
	}
	kept = append(kept, Profile{Name: name, Fingerprint: fp, Outputs: outs})
	b, _ := json.MarshalIndent(kept, "", "  ")
	return writeAtomic(s.Profiles, string(b)+"\n")
}

// SaveProfile names the current arrangement.
func (s *Service) SaveProfile(name string) error {
	cur, err := s.Backend.Current()
	if err != nil {
		return err
	}
	return s.saveProfile(name, cur)
}

func (s *Service) ListProfiles() ([]Profile, error) { return s.loadProfiles() }

// OutputsChanged applies the profile saved for the monitors now connected
// (a named one before "Last used"), and says which one it applied.
func (s *Service) OutputsChanged() (string, error) {
	cur, err := s.Backend.Current()
	if err != nil {
		return "", err
	}
	ps, err := s.loadProfiles()
	if err != nil {
		return "", err
	}
	fp := Fingerprint(cur)
	var pick *Profile
	for i := range ps {
		if ps[i].Fingerprint != fp {
			continue
		}
		if pick == nil || pick.Name == "Last used" {
			pick = &ps[i]
		}
	}
	if pick == nil {
		return "", nil
	}
	if err := s.Backend.Apply(pick.Outputs); err != nil {
		return "", err
	}
	s.notify("display_profile", map[string]any{"name": pick.Name})
	return pick.Name, nil
}

func writeAtomic(path, text string) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err := f.WriteString(text); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(f.Name(), path)
}

// DryRun reads the real monitors but only records what it would apply
// (ANOD_DISPLAY_DRYRUN=1: test the Settings flow without touching the screen).
type DryRun struct {
	Backend
	mu    sync.Mutex
	state []Output
	Logf  func(string, ...any)
}

func (d *DryRun) Current() ([]Output, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.state == nil {
		cur, err := d.Backend.Current()
		if err != nil {
			return nil, err
		}
		d.state = cur
	}
	return append([]Output{}, d.state...), nil
}

func (d *DryRun) Apply(outs []Output) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.Logf != nil {
		d.Logf("display (dry run): would apply %+v", outs)
	}
	d.state = merge(d.state, outs)
	return nil
}
