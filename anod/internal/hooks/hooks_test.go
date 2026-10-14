package hooks

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

type logbuf struct {
	mu    sync.Mutex
	lines []string
}

func (l *logbuf) Logf(f string, a ...any) {
	l.mu.Lock()
	l.lines = append(l.lines, fmt.Sprintf(f, a...))
	l.mu.Unlock()
}

func runner(cmds map[string]string, timeout time.Duration, l *logbuf) *Runner {
	return &Runner{
		Config: func() Config { return Config{Enable: true, Timeout: timeout, Commands: cmds} },
		Logf:   l.Logf,
	}
}

func TestThemeModeHookGetsEnv(t *testing.T) {
	out := filepath.Join(t.TempDir(), "out")
	l := &logbuf{}
	r := runner(map[string]string{"theme_mode_changed": `printf '%s %s' "$ANO_EVENT" "$ANO_THEME_MODE" > "` + out + `"`}, time.Second, l)
	started, done := r.Fire("theme_mode_changed", map[string]string{"themeMode": "light"})
	if !started {
		t.Fatal("hook not started")
	}
	<-done
	b, _ := os.ReadFile(out)
	if string(b) != "theme_mode_changed light" {
		t.Errorf("hook saw %q (log %v)", b, l.lines)
	}
}

func TestSlowHookKilledAndLaterEventsFire(t *testing.T) {
	out := filepath.Join(t.TempDir(), "out")
	l := &logbuf{}
	r := runner(map[string]string{
		"session_locked":   "sleep 30",
		"session_unlocked": "touch " + out,
	}, 100*time.Millisecond, l)
	start := time.Now()
	_, done := r.Fire("session_locked", nil)
	_, done2 := r.Fire("session_unlocked", nil)
	<-done
	<-done2
	if el := time.Since(start); el > 3*time.Second {
		t.Errorf("slow hook not killed in time (%s)", el)
	}
	if len(l.lines) != 1 || !strings.Contains(l.lines[0], "killed after 100ms") {
		t.Errorf("log = %v", l.lines)
	}
	if _, err := os.Stat(out); err != nil {
		t.Error("later event's hook did not run")
	}
}

func TestDataCannotInjectCommands(t *testing.T) {
	dir := t.TempDir()
	l := &logbuf{}
	r := runner(map[string]string{"wifi_changed": `echo "$ANO_WIFI" > ` + filepath.Join(dir, "out")}, time.Second, l)
	_, done := r.Fire("wifi_changed", map[string]string{"wifi": "$(touch " + filepath.Join(dir, "pwned") + ")"})
	<-done
	if _, err := os.Stat(filepath.Join(dir, "pwned")); err == nil {
		t.Fatal("event data was executed")
	}
}

func TestDisabledOrEmptyDoesNothing(t *testing.T) {
	r := &Runner{Config: func() Config { return Config{Enable: false, Commands: map[string]string{"started": "false"}} }}
	if s, _ := r.Fire("started", nil); s {
		t.Error("disabled hooks ran")
	}
	r = &Runner{Config: func() Config { return Config{Enable: true} }}
	if s, _ := r.Fire("started", nil); s {
		t.Error("empty hook ran")
	}
}

func TestEnvName(t *testing.T) {
	for in, want := range map[string]string{"themeMode": "THEME_MODE", "battery_percent": "BATTERY_PERCENT", "wifi": "WIFI", "a-b": "A_B"} {
		if got := EnvName(in); got != want {
			t.Errorf("EnvName(%q) = %q, want %q", in, got, want)
		}
	}
}
