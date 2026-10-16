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
	Engine     string // "awww" (default) or "shell": the shell draws it, awww is skipped
	Hooks      []Hook
}

// Request is one wallpaper change.
type Request struct {
	Image   string   `json:"image"`
	Outputs []string `json:"outputs"` // empty: every output
	// ColorsOnly redoes colours and hooks for an image already shown (the
	// light/dark switch): awww and the recorded state are left alone.
	ColorsOnly bool `json:"colorsOnly"`
}

// Result reports what happened, step by step.
type Result struct {
	Image   string       `json:"image"`
	Outputs []string     `json:"outputs,omitempty"` // empty: every output
	Resize  string       `json:"resize"`
	Colors  string       `json:"colors"`
	Steps   []StepResult `json:"steps"`
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
	Still func(ctx context.Context, path string) (string, error)
	mu    sync.Mutex
}

// State is what was applied last (read by the shell for glass alignment).
type State struct {
	Image   string            `json:"image"`
	Resize  string            `json:"resize"`
	Outputs map[string]string `json:"outputs"` // output -> image
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

	// 2. colours (also in fixed mode: switching back then has them ready)
	if !s.SkipColors {
		res.Steps = append(res.Steps, p.matugen(ctx, src, s))
	}

	// 3. hooks, in order
	env := []string{"ANO_WALLPAPER=" + img, "ANO_THEME_MODE=" + s.Mode, "ANO_COLORS=" + p.ColorsPath}
	for _, h := range s.Hooks {
		name := h.Name
		if name == "" {
			name = strings.Join(h.Command, " ")
		}
		switch {
		case !h.Enable:
			res.Steps = append(res.Steps, StepResult{Name: name, Skipped: "disabled"})
			continue
		case s.FixedColor:
			res.Steps = append(res.Steps, StepResult{Name: name, Skipped: "fixed colour mode"})
			continue
		}
		timeout := time.Duration(h.Timeout) * time.Second
		if timeout <= 0 {
			timeout = 20 * time.Second
		}
		if h.Builtin == "cava" {
			res.Steps = append(res.Steps, p.cava(name))
			continue
		}
		if len(h.Command) == 0 {
			res.Steps = append(res.Steps, StepResult{Name: name, Skipped: "no command"})
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
			res.Steps = append(res.Steps, StepResult{Name: name, Skipped: "not installed: " + argv[0]})
			continue
		}
		res.Steps = append(res.Steps, p.run(ctx, name, timeout, argv, env))
	}
	for _, st := range res.Steps {
		switch {
		case st.Skipped != "":
			p.logf("wallpaper: %s skipped (%s)", st.Name, st.Skipped)
		case !st.OK:
			p.logf("wallpaper: %s failed after %dms: %s", st.Name, st.Duration, st.Error)
		default:
			p.logf("wallpaper: %s ok (%dms)", st.Name, st.Duration)
		}
	}
	return res, nil
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
	c, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	out, err := exec.CommandContext(c, "matugen", "image", img, "--mode", mode, "--type", "scheme-"+scheme,
		"--prefer", prefer, "--json", "hex", "--dry-run").Output()
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
	st.OK = true
	return st
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
