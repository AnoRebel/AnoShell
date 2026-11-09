// Package autostart launches the user's startup applications
// (autostart.entries) once per graphical session, on Hyprland and niri alike.
//
// An entry is {desktopId | command, enabled, delayMs}: a desktop entry id
// (firefox, org.kde.kdeconnect.daemon) looked up in the XDG application and
// autostart folders, or a command line run with `sh -c`. Each starts in its
// own systemd scope (systemd-run --user --scope) when a user manager is
// there, else in a new session (setsid), the way the shell's DefaultApps
// launches apps. A marker in $XDG_RUNTIME_DIR remembers the session, so
// anod restarting does not launch everything again.
package autostart

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"
)

// MaxDelay caps delayMs (10 minutes).
const MaxDelay = 600_000

type Entry struct {
	DesktopID string `json:"desktopId,omitempty"`
	Command   string `json:"command,omitempty"`
	Enabled   bool   `json:"enabled"`
	DelayMs   int    `json:"delayMs"`
}

// Key identifies an entry across edits of the list.
func (e Entry) Key() string {
	if e.DesktopID != "" {
		return "desktop:" + e.DesktopID
	}
	return "command:" + e.Command
}

// Parse reads autostart.entries (as decoded from JSON). Entries with neither a
// desktopId nor a command are dropped; enabled defaults to true; delayMs is
// clamped to 0…MaxDelay.
func Parse(v any) []Entry {
	list, _ := v.([]any)
	var out []Entry
	for _, item := range list {
		m, ok := item.(map[string]any)
		if !ok {
			continue
		}
		e := Entry{Enabled: true}
		e.DesktopID, _ = m["desktopId"].(string)
		e.DesktopID = strings.TrimSuffix(strings.TrimSpace(e.DesktopID), ".desktop")
		e.Command, _ = m["command"].(string)
		e.Command = strings.TrimSpace(e.Command)
		if e.DesktopID != "" {
			e.Command = ""
		}
		if e.DesktopID == "" && e.Command == "" {
			continue
		}
		if b, ok := m["enabled"].(bool); ok {
			e.Enabled = b
		}
		e.DelayMs = min(max(toInt(m["delayMs"]), 0), MaxDelay)
		out = append(out, e)
	}
	return out
}

func toInt(v any) int {
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case json.Number:
		if i, err := n.Int64(); err == nil {
			return int(i)
		}
		f, _ := n.Float64()
		return int(f)
	}
	return 0
}

// ─── Desktop entries ─────────────────────────────────────────────────────

// DesktopFile is the part of a .desktop file autostart needs.
type DesktopFile struct {
	ID       string   `json:"id"`
	Path     string   `json:"path"`
	Name     string   `json:"name"`
	Icon     string   `json:"icon"`
	Exec     string   `json:"exec"`
	Terminal bool     `json:"terminal"`
	Hidden   bool     `json:"hidden"` // Hidden=true: the entry is deleted
	OnlyShow []string `json:"onlyShowIn,omitempty"`
	NotShow  []string `json:"notShowIn,omitempty"`
}

// ReadDesktop parses the [Desktop Entry] group of a .desktop file.
func ReadDesktop(path string) (DesktopFile, error) {
	f, err := os.Open(path)
	if err != nil {
		return DesktopFile{}, err
	}
	defer f.Close()
	d := DesktopFile{ID: strings.TrimSuffix(filepath.Base(path), ".desktop"), Path: path}
	in := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || line[0] == '#' {
			continue
		}
		if line[0] == '[' {
			in = line == "[Desktop Entry]"
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !in || !ok {
			continue
		}
		k, v = strings.TrimSpace(k), strings.TrimSpace(v)
		switch k {
		case "Name":
			d.Name = v
		case "Icon":
			d.Icon = v
		case "Exec":
			d.Exec = v
		case "Terminal":
			d.Terminal = v == "true"
		case "Hidden":
			d.Hidden = v == "true"
		case "OnlyShowIn":
			d.OnlyShow = splitList(v)
		case "NotShowIn":
			d.NotShow = splitList(v)
		}
	}
	return d, sc.Err()
}

func splitList(v string) []string {
	var out []string
	for _, s := range strings.Split(v, ";") {
		if s = strings.TrimSpace(s); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// validID: a desktop id is a file name, never a path.
var validID = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._+-]*$`)

// FindDesktop looks an id up in dirs (each holding <id>.desktop files), first match wins.
func FindDesktop(id string, dirs []string) (DesktopFile, error) {
	if !validID.MatchString(id) {
		return DesktopFile{}, fmt.Errorf("%q is not a desktop entry id", id)
	}
	for _, d := range dirs {
		p := filepath.Join(d, id+".desktop")
		if fi, err := os.Stat(p); err == nil && fi.Mode().IsRegular() {
			return ReadDesktop(p)
		}
	}
	return DesktopFile{}, fmt.Errorf("no desktop entry %q", id)
}

// SearchDirs: the XDG application folders, then the autostart folders.
func SearchDirs() []string {
	home, _ := os.UserHomeDir()
	dataHome := os.Getenv("XDG_DATA_HOME")
	if dataHome == "" {
		dataHome = filepath.Join(home, ".local", "share")
	}
	dataDirs := os.Getenv("XDG_DATA_DIRS")
	if dataDirs == "" {
		dataDirs = "/usr/local/share:/usr/share"
	}
	dirs := []string{filepath.Join(dataHome, "applications")}
	for _, d := range strings.Split(dataDirs, ":") {
		if filepath.IsAbs(d) {
			dirs = append(dirs, filepath.Join(d, "applications"))
		}
	}
	return append(dirs, AutostartDirs()...)
}

// AutostartDirs: $XDG_CONFIG_HOME/autostart, then $XDG_CONFIG_DIRS/autostart.
func AutostartDirs() []string {
	home, _ := os.UserHomeDir()
	cfg := os.Getenv("XDG_CONFIG_HOME")
	if cfg == "" {
		cfg = filepath.Join(home, ".config")
	}
	cfgDirs := os.Getenv("XDG_CONFIG_DIRS")
	if cfgDirs == "" {
		cfgDirs = "/etc/xdg"
	}
	dirs := []string{filepath.Join(cfg, "autostart")}
	for _, d := range strings.Split(cfgDirs, ":") {
		if filepath.IsAbs(d) {
			dirs = append(dirs, filepath.Join(d, "autostart"))
		}
	}
	return dirs
}

// ListDir reads the .desktop files of one folder (for showing
// ~/.config/autostart read-only).
func ListDir(dir string) []DesktopFile {
	matches, _ := filepath.Glob(filepath.Join(dir, "*.desktop"))
	var out []DesktopFile
	for _, p := range matches {
		if d, err := ReadDesktop(p); err == nil {
			out = append(out, d)
		}
	}
	return out
}

// ExecArgv splits a desktop Exec value into argv (the Desktop Entry spec's
// quoting) and drops the field codes (%f, %U, %i, …; %% is a percent).
func ExecArgv(execLine string) ([]string, error) {
	var args []string
	var cur strings.Builder
	have, quoted := false, false
	for i := 0; i < len(execLine); i++ {
		c := execLine[i]
		switch {
		case quoted && c == '\\' && i+1 < len(execLine):
			i++
			cur.WriteByte(execLine[i])
		case c == '"':
			quoted, have = !quoted, true
		case !quoted && (c == ' ' || c == '\t'):
			if have {
				args = append(args, cur.String())
				cur.Reset()
				have = false
			}
		default:
			cur.WriteByte(c)
			have = true
		}
	}
	if quoted {
		return nil, errors.New("unterminated quote in Exec")
	}
	if have {
		args = append(args, cur.String())
	}
	var out []string
	for _, a := range args {
		a = stripFieldCodes(a)
		if a != "" {
			out = append(out, a)
		}
	}
	if len(out) == 0 {
		return nil, errors.New("empty Exec")
	}
	return out, nil
}

func stripFieldCodes(a string) string {
	var b strings.Builder
	for i := 0; i < len(a); i++ {
		if a[i] == '%' && i+1 < len(a) {
			i++
			if a[i] == '%' {
				b.WriteByte('%')
			}
			continue
		}
		b.WriteByte(a[i])
	}
	return b.String()
}

// Resolve turns an entry into the command line to start and a display name.
// A desktop entry that wants a terminal runs through `ano run terminal -e`.
func Resolve(e Entry, dirs []string) (argv []string, name string, err error) {
	if e.DesktopID == "" {
		return []string{"sh", "-c", e.Command}, e.Command, nil
	}
	d, err := FindDesktop(e.DesktopID, dirs)
	if err != nil {
		return nil, e.DesktopID, err
	}
	name = d.Name
	if name == "" {
		name = d.ID
	}
	argv, err = ExecArgv(d.Exec)
	if err != nil {
		return nil, name, fmt.Errorf("%s: %v", d.Path, err)
	}
	if d.Terminal {
		argv = append([]string{"ano", "run", "terminal", "-e"}, argv...)
	}
	return argv, name, nil
}

// ─── Once per session ────────────────────────────────────────────────────

// Marker remembers which session the entries were launched in. The runtime
// directory goes when the user's last session ends; the session id covers a
// quick log out and back in that keeps it.
type Marker struct{ Path string }

// Claim reports whether session is new to the marker, and records it.
// An empty session (no graphical session) is never claimed.
func (m Marker) Claim(session string) (bool, error) {
	if session == "" {
		return false, nil
	}
	if b, err := os.ReadFile(m.Path); err == nil && strings.TrimSpace(string(b)) == session {
		return false, nil
	}
	if err := os.MkdirAll(filepath.Dir(m.Path), 0o700); err != nil {
		return false, err
	}
	return true, os.WriteFile(m.Path, []byte(session+"\n"), 0o600)
}

// ─── Launching ───────────────────────────────────────────────────────────

// Status of one entry in this anod's lifetime.
type Status struct {
	At    time.Time `json:"at"`
	Error string    `json:"error,omitempty"`
}

type Launcher struct {
	Dirs []string // desktop entry search path (SearchDirs when nil)
	Logf func(string, ...any)
	// Start runs argv detached (tests replace it).
	Start func(argv []string, newSession bool) error

	once    sync.Once
	systemd bool
	mu      sync.Mutex
	status  map[string]Status
}

func (l *Launcher) logf(f string, a ...any) {
	if l.Logf != nil {
		l.Logf(f, a...)
	}
}

func (l *Launcher) dirs() []string {
	if l.Dirs != nil {
		return l.Dirs
	}
	return SearchDirs()
}

// Systemd: a user manager is there to put each app in its own scope.
func (l *Launcher) Systemd() bool {
	l.once.Do(func() {
		if _, err := exec.LookPath("systemd-run"); err == nil {
			l.systemd = exec.Command("systemctl", "--user", "show-environment").Run() == nil
		}
	})
	return l.systemd
}

var unitUnsafe = regexp.MustCompile(`[^A-Za-z0-9_.]`)

// Wrap is argv as launched: in a transient scope in app.slice with systemd,
// else unchanged (the caller starts it in a new session).
func Wrap(argv []string, name string, systemd bool) []string {
	if !systemd {
		return argv
	}
	id := unitUnsafe.ReplaceAllString(filepath.Base(name), "_")
	if len(id) > 60 {
		id = id[:60]
	}
	if id == "" {
		id = "app"
	}
	unit := fmt.Sprintf("app-anoshell-autostart-%s-%x.scope", id, rand.Uint32())
	return append([]string{"systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app.slice", "--unit=" + unit, "--"}, argv...)
}

func startDetached(argv []string, newSession bool) error {
	cmd := exec.Command(argv[0], argv[1:]...)
	if newSession {
		cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	}
	if err := cmd.Start(); err != nil {
		return err
	}
	go cmd.Wait() // reap
	return nil
}

// Launch starts one entry now.
func (l *Launcher) Launch(e Entry) error {
	argv, name, err := Resolve(e, l.dirs())
	if err == nil {
		start := l.Start
		if start == nil {
			start = startDetached
		}
		sd := l.Systemd()
		label := e.DesktopID
		if label == "" {
			label = argv[len(argv)-1]
			if f := strings.Fields(label); len(f) > 0 {
				label = f[0]
			}
		}
		err = start(Wrap(argv, label, sd), !sd)
	}
	st := Status{At: time.Now()}
	if err != nil {
		st.Error = err.Error()
		l.logf("autostart: %s: %v", name, err)
	} else {
		l.logf("autostart: started %s", name)
	}
	l.mu.Lock()
	if l.status == nil {
		l.status = map[string]Status{}
	}
	l.status[e.Key()] = st
	l.mu.Unlock()
	return err
}

// StatusOf: when an entry was last launched by this anod (zero At: never).
func (l *Launcher) StatusOf(e Entry) Status {
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.status[e.Key()]
}

// RunAll launches every enabled entry after its delay; the returned count is
// how many were scheduled.
func (l *Launcher) RunAll(entries []Entry) int {
	n := 0
	for _, e := range entries {
		if !e.Enabled {
			continue
		}
		n++
		if e.DelayMs <= 0 {
			l.Launch(e)
			continue
		}
		time.AfterFunc(time.Duration(e.DelayMs)*time.Millisecond, func() { l.Launch(e) })
	}
	return n
}
