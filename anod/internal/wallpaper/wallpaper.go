// Package wallpaper applies wallpapers and everything that follows from one:
// awww with an explicit, recorded resize mode; Material colours from matugen
// (written where the shell reads them); then an ordered list of hooks (pywal,
// swaync, cava, the user's own scripts), each with its own enable flag and
// timeout. It replaces switchwall.sh and the awww_randomize_multi.sh loop.
//
// Everything runs as argv — an image path or output name is never spliced
// into a shell string.
package wallpaper

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"

	"ano/anod/internal/gtkcss"
	"ano/anod/internal/palette"
)

// Hook is one step after the colours are generated.
type Hook struct {
	Name    string   `json:"name"`
	Enable  bool     `json:"enable"`
	Command []string `json:"command"` // argv; "{image}", "{mode}", "{colors}" are substituted per element
	Builtin string   `json:"builtin"` // "cava": recolour cava from pywal and signal it
	Timeout int      `json:"timeoutSeconds"`
}

// Settings are read from the shell config on every apply, so edits apply live.
type Settings struct {
	Resize     string // crop | fit | stretch | no
	Transition string
	DurationMs int
	Mode       string // dark | light
	SchemeType string // matugen scheme without the "scheme-" prefix
	Prefer     string // matugen --prefer
	FixedColor bool   // appearance.theme.colorMode fixed (or a static theme): skip colour hooks
	SkipColors bool   // another output's image already set the colours this cycle
	// ColorOutput: the output whose wallpaper sets the colours (a chosen or
	// the focused monitor); a wallpaper applied only to other outputs leaves
	// colours and hooks alone. "": every wallpaper set does.
	ColorOutput string
	Engine      string // "awww" (default) or "shell": the shell draws it, awww is skipped
	// PerWallpaper: colour picks remembered for the image (Pipeline.Choices)
	// replace the defaults above.
	PerWallpaper bool
	Gtk          bool // palette block in GTK 3/4 gtk.css (appearance.theme.gtk); off removes it
	Hooks        []Hook
}

// Request is one wallpaper change.
type Request struct {
	Image   string   `json:"image"`
	Outputs []string `json:"outputs"` // empty: every output
	// ColorsOnly redoes colours and hooks for an image already shown (the
	// light/dark switch): awww and the recorded state are left alone.
	ColorsOnly bool `json:"colorsOnly"`
	// Explicit colour options for this request, over the remembered ones.
	Choice
}

// Result reports what happened, step by step.
type Result struct {
	Image   string   `json:"image"`
	Outputs []string `json:"outputs,omitempty"` // empty: every output
	Resize  string   `json:"resize"`
	Colors  string   `json:"colors"`
	// The colour options used: defaults, then the image's remembered picks
	// (Custom), then the request's.
	Scheme Choice `json:"scheme"`
	Custom bool   `json:"custom"`
	// ColorImage: the image the colours were made from; "" when they weren't.
	ColorImage string       `json:"colorImage,omitempty"`
	Steps      []StepResult `json:"steps"`
}

type StepResult struct {
	Name     string `json:"name"`
	OK       bool   `json:"ok"`
	Skipped  string `json:"skipped,omitempty"`
	Error    string `json:"error,omitempty"`
	Duration int    `json:"ms"`
}

// Pipeline applies wallpapers. One at a time: a second request waits.
type Pipeline struct {
	ColorsPath string // $XDG_STATE_HOME/anoshell/generated/colors.json
	StatePath  string // $XDG_STATE_HOME/anoshell/wallpaper.json
	Logf       func(string, ...any)
	// Still returns a frame of a video (the palette cache's); colours and
	// hooks use it, since matugen and most hooks can't read a video.
	Still   func(ctx context.Context, path string) (string, error)
	Choices *Choices // per-wallpaper colour picks; nil: none
	// ColorCache: a directory of generated palettes by image and options, so
	// coming back to a wallpaper (the focused-monitor mode) skips matugen.
	ColorCache string
	GtkDirs    []string // ~/.config/gtk-3.0, gtk-4.0
	mu         sync.Mutex
}

// State is what was applied last (read by the shell for glass alignment).
type State struct {
	Image   string            `json:"image"`
	Resize  string            `json:"resize"`
	Outputs map[string]string `json:"outputs"` // output -> image ("*": every output)
	Colors  string            `json:"colors"`  // the image the colours came from
	At      time.Time         `json:"at"`
}

var imageExt = regexp.MustCompile(`(?i)\.(jpe?g|png|webp|gif|bmp|avif|tiff?)$`)

// IsImage reports whether path looks like a still or animated image awww can show.
func IsImage(path string) bool { return imageExt.MatchString(path) }

func (p *Pipeline) logf(f string, a ...any) {
	if p.Logf != nil {
		p.Logf(f, a...)
	}
}

// Apply runs the whole chain for req with settings s.
func (p *Pipeline) Apply(ctx context.Context, req Request, s Settings) (Result, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	img, err := filepath.Abs(expandHome(req.Image))
	if err != nil {
		return Result{}, err
	}
	if fi, err := os.Stat(img); err != nil || fi.IsDir() {
		return Result{}, fmt.Errorf("not an image file: %s", req.Image)
	}
	if s.Resize == "" {
		s.Resize = "crop"
	}
	res := Result{Image: img, Outputs: req.Outputs, Resize: s.Resize, Colors: p.ColorsPath}
	if s.PerWallpaper && p.Choices != nil {
		if ch, ok := p.Choices.Get(img); ok {
			s, res.Custom = ch.over(s), true
		}
	}
	s = req.Choice.over(s)
	res.Scheme = Choice{SchemeType: s.SchemeType, Prefer: s.Prefer, Mode: s.Mode}
	src := img // what colours and hooks read
	if palette.IsVideo(img) {
		if s.Engine != "shell" && !req.ColorsOnly {
			return res, fmt.Errorf("video wallpapers need the shell-drawn background (background.engine: shell): %s", filepath.Base(img))
		}
		if p.Still == nil {
			return res, fmt.Errorf("no still frame for %s", filepath.Base(img))
		}
		if src, err = p.Still(ctx, img); err != nil || src == "" {
			return res, fmt.Errorf("no still frame for %s: %v", filepath.Base(img), err)
		}
	}

	// 1. awww (unless the shell draws the wallpaper itself)
	switch {
	case req.ColorsOnly:
		res.Steps = append(res.Steps, StepResult{Name: "awww", Skipped: "colours only"})
	case s.Engine == "shell":
		res.Steps = append(res.Steps, StepResult{Name: "awww", Skipped: "shell-drawn background"})
	default:
		step := p.run(ctx, "awww", 20*time.Second, awwwArgs(img, req.Outputs, s), nil)
		res.Steps = append(res.Steps, step)
		if !step.OK {
			return res, fmt.Errorf("awww: %s", step.Error)
		}
	}
	if !req.ColorsOnly {
		p.saveState(img, req.Outputs, s.Resize)
	}

	// Another output's wallpaper sets the colours: this one only shows.
	if s.ColorOutput != "" && !req.ColorsOnly && len(req.Outputs) > 0 && !contains(req.Outputs, s.ColorOutput) {
		s.SkipColors, s.Hooks = true, nil
		res.Steps = append(res.Steps, StepResult{Name: "matugen", Skipped: "colours come from " + s.ColorOutput})
	}

	// 2. colours (also in fixed mode: switching back then has them ready)
	if !s.SkipColors {
		st := p.matugen(ctx, src, s)
		res.Steps = append(res.Steps, st)
		if st.OK {
			res.ColorImage = img
			p.saveColors(img)
		}
		res.Steps = append(res.Steps, p.Gtk(s))
	}

	// 3. hooks, in order
	res.Steps = append(res.Steps, p.hooks(ctx, s, img, src, false)...)
	p.logSteps(res.Steps)
	return res, nil
}

// readsImage: a hook that follows the wallpaper image rather than
// colors.json ({image} in its argv, or the cava builtin, which reads pywal).
func readsImage(h Hook) bool {
	if h.Builtin == "cava" {
		return true
	}
	for _, a := range h.Command {
		if strings.Contains(a, "{image}") {
			return true
		}
	}
	return false
}

// hooks runs s.Hooks in order. theme: the colours came from a static theme,
// not img, so hooks that read the image are skipped.
func (p *Pipeline) hooks(ctx context.Context, s Settings, img, src string, theme bool) []StepResult {
	var steps []StepResult
	env := []string{"ANO_WALLPAPER=" + img, "ANO_THEME_MODE=" + s.Mode, "ANO_COLORS=" + p.ColorsPath}
	for _, h := range s.Hooks {
		name := h.Name
		if name == "" {
			name = strings.Join(h.Command, " ")
		}
		switch {
		case !h.Enable:
			steps = append(steps, StepResult{Name: name, Skipped: "disabled"})
			continue
		case s.FixedColor:
			steps = append(steps, StepResult{Name: name, Skipped: "fixed colour mode"})
			continue
		case theme && readsImage(h):
			steps = append(steps, StepResult{Name: name, Skipped: "reads the wallpaper, not the theme"})
			continue
		}
		timeout := time.Duration(h.Timeout) * time.Second
		if timeout <= 0 {
			timeout = 20 * time.Second
		}
		if h.Builtin == "cava" {
			steps = append(steps, p.cava(name))
			continue
		}
		if len(h.Command) == 0 {
			steps = append(steps, StepResult{Name: name, Skipped: "no command"})
			continue
		}
		argv := make([]string, len(h.Command))
		for i, a := range h.Command {
			a = strings.ReplaceAll(a, "{image}", src)
			a = strings.ReplaceAll(a, "{mode}", s.Mode)
			a = strings.ReplaceAll(a, "{colors}", p.ColorsPath)
			argv[i] = a
		}
		argv[0] = expandHome(argv[0])
		if _, err := exec.LookPath(argv[0]); err != nil {
			steps = append(steps, StepResult{Name: name, Skipped: "not installed: " + argv[0]})
			continue
		}
		steps = append(steps, p.run(ctx, name, timeout, argv, env))
	}
	return steps
}

// ApplyPalette makes a ready palette (a static theme's colors.json content)
// the colours the way a wallpaper's are: colors.json, GTK, then the hooks
// that don't read the wallpaper image — so apps follow a static theme too.
// mode is the theme's dark/light.
func (p *Pipeline) ApplyPalette(ctx context.Context, colors []byte, mode string, s Settings) (Result, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	s.FixedColor, s.Mode = false, mode
	res := Result{Colors: p.ColorsPath, Scheme: Choice{Mode: mode}}
	st := StepResult{Name: "colors"}
	if err := writeAtomic(p.ColorsPath, colors); err != nil {
		st.Error = err.Error()
		res.Steps = append(res.Steps, st)
		return res, err
	}
	st.OK = true
	p.saveColors("") // not from an image: a later wallpaper recolour isn't skipped as "already done"
	res.Steps = append(res.Steps, st, p.Gtk(s))
	img := p.LoadState().Image
	res.Steps = append(res.Steps, p.hooks(ctx, s, img, img, true)...)
	p.logSteps(res.Steps)
	return res, nil
}

func (p *Pipeline) logSteps(steps []StepResult) {
	for _, st := range steps {
		switch {
		case st.Skipped != "":
			p.logf("wallpaper: %s skipped (%s)", st.Name, st.Skipped)
		case !st.OK:
			p.logf("wallpaper: %s failed after %dms: %s", st.Name, st.Duration, st.Error)
		default:
			p.logf("wallpaper: %s ok (%dms)", st.Name, st.Duration)
		}
	}
}

func awwwArgs(img string, outputs []string, s Settings) []string {
	a := []string{"awww", "img", "--resize", s.Resize}
	if s.Transition != "" {
		a = append(a, "--transition-type", s.Transition)
		if s.DurationMs > 0 {
			a = append(a, "--transition-duration", fmt.Sprintf("%.2f", float64(s.DurationMs)/1000))
		}
	}
	if len(outputs) > 0 {
		a = append(a, "--outputs", strings.Join(outputs, ","))
	}
	return append(a, "--", img)
}

// matugen writes {role: hex, darkmode} atomically where the shell reads it.
func (p *Pipeline) matugen(ctx context.Context, img string, s Settings) StepResult {
	start := time.Now()
	st := StepResult{Name: "matugen"}
	if _, err := exec.LookPath("matugen"); err != nil {
		st.Skipped = "not installed: matugen"
		return st
	}
	scheme := s.SchemeType
	if scheme == "" {
		scheme = "tonal-spot"
	}
	prefer := s.Prefer
	if prefer == "" {
		prefer = "saturation"
	}
	mode := s.Mode
	if mode != "light" {
		mode = "dark"
	}
	cached := p.cacheFile(img, scheme, prefer, mode)
	if b, err := os.ReadFile(cached); cached != "" && err == nil {
		if err := writeAtomic(p.ColorsPath, b); err == nil {
			st.OK = true
			st.Duration = int(time.Since(start).Milliseconds())
			return st
		}
	}
	c, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	args := []string{"image", img, "--mode", mode, "--type", "scheme-" + scheme,
		"--prefer", prefer, "--json", "hex", "--dry-run"}
	if cfg := p.MatugenConfig(); cfg != "" {
		args = append([]string{"-c", cfg}, args...)
	}
	out, err := exec.CommandContext(c, "matugen", args...).Output()
	st.Duration = int(time.Since(start).Milliseconds())
	if err != nil {
		st.Error = err.Error()
		return st
	}
	colors, err := FlattenMatugen(out, mode == "dark")
	if err != nil {
		st.Error = err.Error()
		return st
	}
	if err := writeAtomic(p.ColorsPath, colors); err != nil {
		st.Error = err.Error()
		return st
	}
	if cached != "" {
		_ = writeAtomic(cached, colors)
	}
	st.OK = true
	return st
}

// Gtk writes the palette block into each GTK dir's gtk.css, or removes it
// when s.Gtk is off. Fixed colour mode leaves app colours as they are.
func (p *Pipeline) Gtk(s Settings) StepResult {
	start := time.Now()
	st := StepResult{Name: "gtk"}
	if s.FixedColor {
		st.Skipped = "fixed colour mode"
		return st
	}
	var colors map[string]string
	if s.Gtk {
		b, err := os.ReadFile(p.ColorsPath)
		if err == nil {
			var raw map[string]any
			err = json.Unmarshal(b, &raw)
			colors = map[string]string{}
			for k, v := range raw {
				if c, ok := v.(string); ok {
					colors[k] = c
				}
			}
		}
		if err != nil {
			st.Error = err.Error()
			return st
		}
	}
	for _, dir := range p.GtkDirs {
		var err error
		if s.Gtk {
			err = gtkcss.Apply(dir, gtkcss.Block(colors, filepath.Base(dir) == "gtk-4.0"))
		} else {
			err = gtkcss.Remove(dir)
		}
		if err != nil {
			st.Error = err.Error()
			return st
		}
	}
	st.OK = true
	st.Duration = int(time.Since(start).Milliseconds())
	return st
}

// cacheFile names img's palette for these options: path, size and mtime, so
// an edited image is generated again. "" without a cache dir.
// ponytail: never pruned; a few KB per wallpaper and option set.
// matugenMinimalConfig is all matugen 4 accepts: both tables, even empty.
const matugenMinimalConfig = "# Written by anod: only colours are read (--dry-run --json).\n[config]\n\n[templates]\n"

// MatugenConfig returns an anod-owned matugen config, so a user's own
// ~/.config/matugen/config.toml (which matugen 4 rejects without a [config]
// table, and whose templates we don't want) never breaks colour generation.
// "" (matugen's default lookup) when it can't be written.
func (p *Pipeline) MatugenConfig() string {
	if p.ColorsPath == "" {
		return ""
	}
	path := filepath.Join(filepath.Dir(p.ColorsPath), "matugen.toml")
	if b, err := os.ReadFile(path); err == nil && string(b) == matugenMinimalConfig {
		return path
	}
	if err := writeAtomic(path, []byte(matugenMinimalConfig)); err != nil {
		return ""
	}
	return path
}

func (p *Pipeline) cacheFile(img, scheme, prefer, mode string) string {
	fi, err := os.Stat(img)
	if p.ColorCache == "" || err != nil {
		return ""
	}
	h := sha256.Sum256([]byte(fmt.Sprintf("%s\x00%d\x00%d\x00%s\x00%s\x00%s", img, fi.Size(), fi.ModTime().UnixNano(), scheme, prefer, mode)))
	return filepath.Join(p.ColorCache, hex.EncodeToString(h[:16])+".json")
}

func contains(list []string, v string) bool {
	for _, x := range list {
		if x == v {
			return true
		}
	}
	return false
}

// ColorImage is the image the colours follow: the colour output's wallpaper
// when one is set and known, else the one they were last made from.
func (p *Pipeline) ColorImage(s Settings) string {
	st := p.LoadState()
	if s.ColorOutput != "" {
		if img := st.Outputs[s.ColorOutput]; img != "" {
			return img
		}
		if img := st.Outputs["*"]; img != "" {
			return img
		}
	}
	if st.Colors != "" {
		return st.Colors
	}
	return st.Image
}

func (p *Pipeline) saveColors(img string) {
	if p.StatePath == "" {
		return
	}
	s := p.LoadState()
	s.Colors = img
	b, _ := json.MarshalIndent(s, "", "  ")
	_ = writeAtomic(p.StatePath, b)
}

// FlattenMatugen turns matugen 4's JSON dump into {role: hex, darkmode}.
func FlattenMatugen(dump []byte, dark bool) ([]byte, error) {
	var d struct {
		Colors map[string]struct {
			Default struct {
				Color string `json:"color"`
			} `json:"default"`
		} `json:"colors"`
	}
	if err := json.Unmarshal(dump, &d); err != nil {
		return nil, fmt.Errorf("matugen output: %w", err)
	}
	if len(d.Colors) == 0 {
		return nil, errors.New("matugen output has no colors")
	}
	flat := map[string]any{"darkmode": dark}
	for role, v := range d.Colors {
		flat[role] = v.Default.Color
	}
	return json.MarshalIndent(flat, "", "  ")
}

// cava recolours ~/.config/cava/config from pywal's colors and asks a running
// cava to reload (SIGUSR2). Without pywal colours or a cava config, it skips.
func (p *Pipeline) cava(name string) StepResult {
	start := time.Now()
	st := StepResult{Name: name}
	home, _ := os.UserHomeDir()
	walFile := filepath.Join(home, ".cache/wal/colors.json")
	cfgFile := filepath.Join(home, ".config/cava/config")
	b, err := os.ReadFile(walFile)
	if err != nil {
		st.Skipped = "no pywal colours"
		return st
	}
	cfg, err := os.ReadFile(cfgFile)
	if err != nil {
		st.Skipped = "no cava config"
		return st
	}
	var wal struct {
		Special map[string]string `json:"special"`
		Colors  map[string]string `json:"colors"`
	}
	if err := json.Unmarshal(b, &wal); err != nil {
		st.Error = err.Error()
		return st
	}
	out := RecolourCava(cfg, wal.Special["background"], wal.Special["foreground"], wal.Colors)
	if err := writeAtomic(cfgFile, out); err != nil {
		st.Error = err.Error()
		return st
	}
	signalByName("cava", syscall.SIGUSR2)
	st.OK = true
	st.Duration = int(time.Since(start).Milliseconds())
	return st
}

// RecolourCava rewrites background/foreground and gradient_color_1..8 lines
// (color2..color9), as awww_randomize_multi.sh did with sed.
func RecolourCava(cfg []byte, bg, fg string, colors map[string]string) []byte {
	repl := map[string]string{}
	if bg != "" {
		repl["background"] = bg
	}
	if fg != "" {
		repl["foreground"] = fg
	}
	for i := 1; i <= 8; i++ {
		if c := colors[fmt.Sprintf("color%d", i+1)]; c != "" {
			repl[fmt.Sprintf("gradient_color_%d", i)] = c
		}
	}
	var buf bytes.Buffer
	sc := bufio.NewScanner(bytes.NewReader(cfg))
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	for sc.Scan() {
		line := sc.Text()
		if k, _, ok := strings.Cut(line, "="); ok {
			key := strings.TrimSpace(k)
			if v, hit := repl[key]; hit && !strings.HasPrefix(strings.TrimSpace(line), "#") && !strings.HasPrefix(strings.TrimSpace(line), ";") {
				line = fmt.Sprintf("%s = '%s'", key, v)
			}
		}
		buf.WriteString(line)
		buf.WriteByte('\n')
	}
	return buf.Bytes()
}

// run executes argv with a timeout in its own process group.
func (p *Pipeline) run(ctx context.Context, name string, timeout time.Duration, argv, env []string) StepResult {
	start := time.Now()
	st := StepResult{Name: name}
	c, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	cmd := exec.CommandContext(c, argv[0], argv[1:]...)
	cmd.Env = append(os.Environ(), env...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	// A hook that leaves a background child holding stderr must not block
	// Wait (and the pipeline lock) after the hook itself exits.
	cmd.WaitDelay = 2 * time.Second
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	err := cmd.Run()
	st.Duration = int(time.Since(start).Milliseconds())
	switch {
	case c.Err() == context.DeadlineExceeded:
		st.Error = fmt.Sprintf("timed out after %s", timeout)
	case err != nil:
		msg := strings.TrimSpace(stderr.String())
		if len(msg) > 300 {
			msg = msg[:300]
		}
		st.Error = strings.TrimSpace(err.Error() + ": " + msg)
	default:
		st.OK = true
	}
	return st
}

func (p *Pipeline) saveState(img string, outputs []string, resize string) {
	if p.StatePath == "" {
		return
	}
	s := p.LoadState()
	if s.Outputs == nil {
		s.Outputs = map[string]string{}
	}
	for _, o := range outputs {
		s.Outputs[o] = img
	}
	if len(outputs) == 0 {
		s.Outputs = map[string]string{"*": img}
	}
	s.Image, s.Resize, s.At = img, resize, time.Now()
	b, _ := json.MarshalIndent(s, "", "  ")
	_ = writeAtomic(p.StatePath, b)
}

// LoadState returns the last applied wallpaper (zero State if none).
func (p *Pipeline) LoadState() State {
	var s State
	if b, err := os.ReadFile(p.StatePath); err == nil {
		_ = json.Unmarshal(b, &s)
	}
	return s
}

// writeAtomic replaces path's contents via a temp file and rename. A symlink
// is written through (a dotfiles link stays a link) and an existing file's
// mode is kept (new files get 0644).
func writeAtomic(path string, data []byte) error {
	if real, err := filepath.EvalSymlinks(path); err == nil {
		path = real
	}
	mode := os.FileMode(0o644)
	if fi, err := os.Stat(path); err == nil {
		mode = fi.Mode().Perm()
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".tmp-*")
	if err != nil {
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return err
	}
	tmp.Close()
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return os.Rename(tmp.Name(), path)
}

func expandHome(p string) string {
	if p == "~" || strings.HasPrefix(p, "~/") {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, strings.TrimPrefix(p, "~"))
	}
	return p
}

// signalByName signals every process of ours whose comm is name.
func signalByName(name string, sig syscall.Signal) {
	ents, _ := os.ReadDir("/proc")
	uid := os.Getuid()
	for _, e := range ents {
		pid := 0
		if _, err := fmt.Sscanf(e.Name(), "%d", &pid); err != nil || pid <= 0 {
			continue
		}
		comm, err := os.ReadFile(filepath.Join("/proc", e.Name(), "comm"))
		if err != nil || strings.TrimSpace(string(comm)) != name {
			continue
		}
		if fi, err := os.Stat(filepath.Join("/proc", e.Name())); err == nil {
			if st, ok := fi.Sys().(*syscall.Stat_t); ok && int(st.Uid) != uid {
				continue
			}
		}
		_ = syscall.Kill(pid, sig)
	}
}
