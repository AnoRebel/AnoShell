package display

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// fake is a compositor that remembers what was applied.
type fake struct {
	mu      sync.Mutex
	outs    []Output
	applied [][]Output
}

func (f *fake) Name() string { return "hyprland" }
func (f *fake) Current() ([]Output, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]Output{}, f.outs...), nil
}
func (f *fake) Apply(o []Output) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.applied = append(f.applied, o)
	f.outs = merge(f.outs, o)
	return nil
}

var edp = Output{Name: "eDP-1", Make: "AU Optronics", Model: "0x6693", Width: 1920, Height: 1200, Refresh: 60.026, Scale: 1.5, Enabled: true}

func newSvc(t *testing.T, b Backend) (*Service, string) {
	d := t.TempDir()
	return &Service{Backend: b, Deadline: 100 * time.Millisecond, HyprFile: filepath.Join(d, "hypr", "ano-managed.lua"),
		NiriFile: filepath.Join(d, "niri", "ano-managed.kdl"), Profiles: filepath.Join(d, "anoshell", "display-profiles.json")}, d
}

func TestUnconfirmedScaleReverts(t *testing.T) {
	f := &fake{outs: []Output{edp}}
	s, dir := newSvc(t, f)
	main := filepath.Join(dir, "hypr", "hyprland.lua")
	os.MkdirAll(filepath.Dir(main), 0o755)
	os.WriteFile(main, []byte("-- the user's config\n"), 0o644)
	before := sha256.Sum256([]byte("-- the user's config\n"))

	bigger := edp
	bigger.Scale = 1.25
	p, err := s.Apply([]Output{bigger})
	if err != nil || p == nil {
		t.Fatalf("a scale change must wait for confirmation: %v %v", p, err)
	}
	if cur, _ := f.Current(); cur[0].Scale != 1.25 {
		t.Fatal("not applied live")
	}
	time.Sleep(250 * time.Millisecond)
	if cur, _ := f.Current(); cur[0].Scale != 1.5 {
		t.Fatalf("not reverted: scale %v", cur[0].Scale)
	}
	if s.PendingChange() != nil {
		t.Error("still pending after the revert")
	}
	if _, err := os.Stat(s.HyprFile); err == nil {
		t.Error("an unconfirmed change was persisted")
	}
	b, _ := os.ReadFile(main)
	if sha256.Sum256(b) != before {
		t.Error("the user's config changed")
	}
}

func TestConfirmPersists(t *testing.T) {
	f := &fake{outs: []Output{edp}}
	s, _ := newSvc(t, f)
	s.Deadline = time.Minute
	bigger := edp
	bigger.Scale = 1.25
	if _, err := s.Apply([]Output{bigger}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Apply([]Output{edp}); err == nil {
		t.Error("a second change while one is pending was allowed")
	}
	if err := s.Confirm(); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(s.HyprFile)
	if err != nil || !strings.Contains(string(b), `hl.monitor({ output = "eDP-1", mode = "1920x1200@60.026", position = "0x0", scale = 1.25, transform = 0, vrr = 0 })`) {
		t.Fatalf("persisted: %s %v", b, err)
	}
	ps, _ := s.ListProfiles()
	if len(ps) != 1 || ps[0].Fingerprint != "AU Optronics|0x6693|" || ps[0].Outputs[0].Scale != 1.25 {
		t.Fatalf("profile: %+v", ps)
	}
}

func TestSafeChangeAndGuards(t *testing.T) {
	f := &fake{outs: []Output{edp}}
	s, _ := newSvc(t, f)
	moved := edp
	moved.X = 100
	if p, err := s.Apply([]Output{moved}); err != nil || p != nil {
		t.Fatalf("moving is safe and applies at once: %v %v", p, err)
	}
	off := edp
	off.Enabled = false
	if _, err := s.Apply([]Output{off}); err == nil {
		t.Error("turning the only monitor off was allowed")
	}
}

func TestProfilesFollowTheMonitors(t *testing.T) {
	ext := Output{Name: "HDMI-A-1", Make: "Dell", Model: "U2720Q", Serial: "ABC", Width: 3840, Height: 2160, Refresh: 60, Scale: 2, X: 1280, Enabled: true}
	f := &fake{outs: []Output{edp, ext}}
	s, _ := newSvc(t, f)
	if err := s.SaveProfile("Desk"); err != nil {
		t.Fatal(err)
	}
	f.outs = []Output{edp, func() Output { e := ext; e.X, e.Scale = 0, 1; return e }()} // unplugged and back, at defaults
	name, err := s.OutputsChanged()
	if err != nil || name != "Desk" {
		t.Fatalf("profile: %q %v", name, err)
	}
	if cur, _ := f.Current(); cur[1].X != 1280 || cur[1].Scale != 2 {
		t.Fatalf("Desk not restored: %+v", cur[1])
	}
	f.outs = []Output{edp}
	if name, _ := s.OutputsChanged(); name != "" {
		t.Errorf("a profile for another set applied: %q", name)
	}
}

func TestBackendsRead(t *testing.T) {
	b, _ := os.ReadFile("testdata/hypr_monitors.json")
	outs, err := Hyprland{Run: func(...string) ([]byte, error) { return b, nil }}.Current()
	if err != nil || len(outs) != 1 || outs[0].Name != "eDP-1" || outs[0].Scale != 1.5 || !outs[0].Enabled || outs[0].Make == "" {
		t.Fatalf("hyprland: %+v %v", outs, err)
	}
	niriJSON := `{"eDP-1":{"name":"eDP-1","make":"AU Optronics","model":"0x6693","serial":null,
	 "modes":[{"width":1920,"height":1200,"refresh_rate":60026,"is_preferred":true}],"current_mode":0,
	 "vrr_supported":false,"vrr_enabled":false,"logical":{"x":0,"y":0,"width":1280,"height":800,"scale":1.5,"transform":"_90"}}}`
	n, err := Niri{Run: func(...string) ([]byte, error) { return []byte(niriJSON), nil }}.Current()
	if err != nil || len(n) != 1 || n[0].Refresh != 60.026 || n[0].Transform != 1 || n[0].Scale != 1.5 {
		t.Fatalf("niri: %+v %v", n, err)
	}
	var calls []string
	Niri{Run: func(a ...string) ([]byte, error) { calls = append(calls, strings.Join(a, " ")); return nil, nil }}.Apply(n)
	if strings.Join(calls, "\n") != "msg output eDP-1 on\nmsg output eDP-1 mode 1920x1200@60.026\nmsg output eDP-1 scale 1.5\nmsg output eDP-1 transform 90\nmsg output eDP-1 position set 0 0\nmsg output eDP-1 vrr off" {
		t.Errorf("niri calls:\n%s", strings.Join(calls, "\n"))
	}
	if !strings.Contains(niriOutput(n[0]), `mode "1920x1200@60.026"`) {
		t.Error(niriOutput(n[0]))
	}
}

func TestCursor(t *testing.T) {
	// A theme dir with a 2-image XCursor arrow.
	dir := t.TempDir()
	td := filepath.Join(dir, "Test", "cursors")
	os.MkdirAll(td, 0o755)
	os.WriteFile(filepath.Join(dir, "Test", "index.theme"), []byte("[Icon Theme]\nName=Test Cursors\n"), 0o644)
	os.MkdirAll(filepath.Join(dir, "NotCursors"), 0o755)
	var xc bytes.Buffer
	le := binary.LittleEndian
	w := func(v uint32) { binary.Write(&xc, le, v) }
	xc.WriteString("Xcur")
	w(16)
	w(0x10000)
	w(2)
	pos := uint32(16 + 2*12)
	w(0xfffd0002)
	w(24)
	w(pos)
	w(0xfffd0002)
	w(48)
	w(pos + 36 + 24*24*4)
	for _, sz := range []uint32{24, 48} {
		w(36)
		w(0xfffd0002)
		w(sz)
		w(1)
		w(sz)
		w(sz)
		w(1)
		w(1)
		w(0)
		for i := uint32(0); i < sz*sz; i++ {
			w(0x80800000) // half-transparent premultiplied red
		}
	}
	os.WriteFile(filepath.Join(td, "left_ptr"), xc.Bytes(), 0o644)

	themes := CursorThemes([]string{dir})
	if len(themes) != 1 || themes[0].Name != "Test" || themes[0].Title != "Test Cursors" {
		t.Fatalf("themes: %+v", themes)
	}
	pngData, err := Preview(themes[0].Path, 40)
	if err != nil {
		t.Fatal(err)
	}
	img, err := png.Decode(bytes.NewReader(pngData))
	if err != nil || img.Bounds().Dx() != 48 {
		t.Fatalf("preview: %v %v", img.Bounds(), err)
	}
	if c := color.NRGBAModel.Convert(img.At(0, 0)).(color.NRGBA); c.A != 0x80 || c.R != 0xff {
		t.Errorf("pixel not un-premultiplied: %+v", c)
	}

	// Applying: hyprctl + gsettings run, settings.ini keys updated in place,
	// the managed file carries XCURSOR_*.
	f := &fake{outs: []Output{edp}}
	s, d := newSvc(t, f)
	ini := filepath.Join(d, "settings.ini")
	os.WriteFile(ini, []byte("[Settings]\ngtk-theme-name=X\ngtk-cursor-theme-name=Old\ngtk-cursor-theme-size=16\n"), 0o644)
	s.GtkSettings = []string{ini, filepath.Join(d, "missing.ini")}
	var ran []string
	s.Exec = func(n string, a ...string) error { ran = append(ran, n+" "+strings.Join(a, " ")); return nil }
	if err := s.SetCursor(Cursor{Theme: "Test", Size: 32}); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(strings.Join(ran, "\n"), "hyprctl setcursor Test 32") || !strings.Contains(strings.Join(ran, "\n"), "cursor-size 32") {
		t.Errorf("ran: %v", ran)
	}
	b, _ := os.ReadFile(ini)
	if string(b) != "[Settings]\ngtk-theme-name=X\ngtk-cursor-theme-name=Test\ngtk-cursor-theme-size=32\n" {
		t.Errorf("ini: %q", b)
	}
	if _, err := os.Stat(filepath.Join(d, "missing.ini")); err == nil {
		t.Error("created a settings.ini that wasn't there")
	}
	m, _ := os.ReadFile(s.HyprFile)
	if !strings.Contains(string(m), `hl.env("XCURSOR_SIZE", "32")`) || !strings.Contains(string(m), `output = "eDP-1"`) {
		t.Errorf("managed: %s", m)
	}
	if err := s.SetCursor(Cursor{Theme: "../x", Size: 32}); err == nil {
		t.Error("bad theme name accepted")
	}
}

func TestProfilesFollowIdentityAndIgnorePending(t *testing.T) {
	a := Output{Name: "DP-1", Make: "Dell", Model: "A", Serial: "1", Width: 1920, Height: 1080, Refresh: 60, Scale: 1, Enabled: true}
	b := Output{Name: "DP-2", Make: "Dell", Model: "A", Serial: "2", Width: 1920, Height: 1080, Refresh: 60, Scale: 1, X: 1920, Enabled: true}
	// Saved with a on DP-1 at 0 and b on DP-2 at 1920; now the cables are swapped.
	got := byIdentity([]Output{a, b}, []Output{{Name: "DP-2", Make: "Dell", Model: "A", Serial: "1"}, {Name: "DP-1", Make: "Dell", Model: "A", Serial: "2"}})
	if got[0].Name != "DP-2" || got[0].X != 0 || got[1].Name != "DP-1" || got[1].X != 1920 {
		t.Fatalf("by identity: %+v", got)
	}
	f := &fake{outs: []Output{edp}}
	s, _ := newSvc(t, f)
	s.Deadline = time.Minute
	s.SaveProfile("Desk")
	bigger := edp
	bigger.Scale = 1.25
	s.Apply([]Output{bigger})
	if name, _ := s.OutputsChanged(); name != "" {
		t.Errorf("a pending change was overridden by profile %q", name)
	}
	s.Revert()
}

func TestKeyboard(t *testing.T) {
	f := &fake{outs: []Output{edp}}
	s, _ := newSvc(t, f)
	var ran []string
	s.Exec = func(n string, a ...string) error { ran = append(ran, n+" "+strings.Join(a, " ")); return nil }
	if err := s.SetKeyboard(Keyboard{Layouts: "us,fr", Variants: ",azerty"}); err != nil {
		t.Fatal(err)
	}
	want := `hyprctl eval hl.config({ input = { kb_layout = "us,fr", kb_variant = ",azerty" } })`
	if len(ran) != 1 || ran[0] != want {
		t.Errorf("ran: %v", ran)
	}
	m, _ := os.ReadFile(s.HyprFile)
	if !strings.Contains(string(m), `kb_layout = "us,fr"`) || !strings.Contains(string(m), `output = "eDP-1"`) {
		t.Errorf("managed: %s", m)
	}
	if err := s.SetKeyboard(Keyboard{Layouts: `us"})os.exit()--`}); err == nil {
		t.Error("bad layouts accepted")
	}
	if got := niriKeyboard(Keyboard{Layouts: "us,fr", Variants: ",azerty"}); !strings.Contains(got, `layout "us,fr"`) || !strings.Contains(got, `variant ",azerty"`) {
		t.Errorf("niri: %s", got)
	}
}
