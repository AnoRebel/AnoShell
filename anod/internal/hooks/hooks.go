// Package hooks runs user commands on shell events (idea from Noctalia v5).
// Each hook gets ANO_EVENT plus ANO_<KEY> variables for the event data, runs
// in its own process group, and is killed when it exceeds its timeout.
package hooks

import (
	"context"
	"errors"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode"
)

// Events lists the supported event names and their config keys (hooks.<key>).
var Events = map[string]string{
	"started":               "started",
	"wallpaper_changed":     "wallpaperChanged",
	"theme_mode_changed":    "themeModeChanged",
	"session_locked":        "sessionLocked",
	"session_unlocked":      "sessionUnlocked",
	"logging_out":           "loggingOut",
	"rebooting":             "rebooting",
	"shutting_down":         "shuttingDown",
	"wifi_changed":          "wifiChanged",
	"bluetooth_changed":     "bluetoothChanged",
	"battery_changed":       "batteryChanged",
	"power_profile_changed": "powerProfileChanged",
}

type Config struct {
	Enable   bool
	Timeout  time.Duration
	Commands map[string]string // event name -> shell command
}

type Runner struct {
	// Config is read on every Fire, so edits to config.json apply without a restart.
	Config func() Config
	Logf   func(format string, a ...any)

	mu      sync.Mutex
	running map[string]*pending // events whose hook is running now
}

// pending holds the newest event that arrived while its hook was running.
type pending struct {
	data map[string]string
	set  bool
}

// Fire starts the hook for event (if any) and returns at once. While an
// event's hook is still running, newer occurrences collapse into one rerun
// with the latest data, so a flapping event can't pile up processes. The
// returned channel closes when this event's hook work (including a collapsed
// rerun) is done; tests wait on it.
func (r *Runner) Fire(event string, data map[string]string) (started bool, done <-chan struct{}) {
	ch := make(chan struct{})
	cfg := r.Config()
	if !cfg.Enable || strings.TrimSpace(cfg.Commands[event]) == "" {
		close(ch)
		return false, ch
	}
	r.mu.Lock()
	if r.running == nil {
		r.running = map[string]*pending{}
	}
	if p, busy := r.running[event]; busy {
		p.data, p.set = data, true
		r.mu.Unlock()
		close(ch)
		return true, ch
	}
	r.running[event] = &pending{}
	r.mu.Unlock()

	go func() {
		defer close(ch)
		for {
			c := r.Config() // re-read: the command may have changed meanwhile
			if cmdline := strings.TrimSpace(c.Commands[event]); c.Enable && cmdline != "" {
				timeout := c.Timeout
				if timeout <= 0 {
					timeout = 10 * time.Second
				}
				r.run(event, cmdline, data, timeout)
			}
			r.mu.Lock()
			p := r.running[event]
			if !p.set {
				delete(r.running, event)
				r.mu.Unlock()
				return
			}
			data, p.data, p.set = p.data, nil, false
			r.mu.Unlock()
		}
	}()
	return true, ch
}

func (r *Runner) logf(format string, a ...any) {
	if r.Logf != nil {
		r.Logf(format, a...)
	} else {
		log.Printf(format, a...)
	}
}

func (r *Runner) run(event, cmdline string, data map[string]string, timeout time.Duration) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	// The command is the user's own config text, run as the user; event data
	// only ever travels through the environment, never through the command line.
	cmd := exec.CommandContext(ctx, "sh", "-c", cmdline)
	cmd.Env = os.Environ()
	for k, v := range data {
		if name := EnvName(k); name != "EVENT" { // ANO_EVENT is reserved
			cmd.Env = append(cmd.Env, "ANO_"+name+"="+v)
		}
	}
	cmd.Env = append(cmd.Env, "ANO_EVENT="+event)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	// On timeout the whole group goes (sh and what it started in the foreground).
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	// Programs a hook starts in the background inherit the output pipe; don't
	// wait for them once sh has exited (they keep running, by design).
	cmd.WaitDelay = time.Second
	out := &tailBuffer{max: 4096} // bounded: a chatty hook can't grow anod's memory
	cmd.Stdout, cmd.Stderr = out, out
	err := cmd.Run()
	switch {
	case ctx.Err() == context.DeadlineExceeded && cmd.ProcessState != nil && !cmd.ProcessState.Exited():
		r.logf("hook %s: killed after %s timeout", event, timeout)
	case err != nil && !errors.Is(err, exec.ErrWaitDelay):
		r.logf("hook %s: %v: %s", event, err, tail(out.String()))
	}
}

// tailBuffer keeps only the last max bytes written to it.
type tailBuffer struct {
	mu  sync.Mutex
	max int
	b   []byte
}

func (t *tailBuffer) Write(p []byte) (int, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.b = append(t.b, p...)
	if len(t.b) > t.max {
		t.b = append(t.b[:0], t.b[len(t.b)-t.max:]...)
	}
	return len(p), nil
}

func (t *tailBuffer) String() string {
	t.mu.Lock()
	defer t.mu.Unlock()
	return string(t.b)
}

// EnvName turns "batteryPercent" / "battery_percent" into "BATTERY_PERCENT".
func EnvName(k string) string {
	var b strings.Builder
	for i, c := range k {
		switch {
		case unicode.IsUpper(c) && i > 0 && k[i-1] != '_':
			b.WriteByte('_')
			b.WriteRune(c)
		case unicode.IsLetter(c) || unicode.IsDigit(c):
			b.WriteRune(unicode.ToUpper(c))
		default:
			b.WriteByte('_')
		}
	}
	return b.String()
}

func tail(s string) string {
	s = strings.TrimSpace(s)
	if len(s) > 300 {
		s = "…" + s[len(s)-300:]
	}
	return s
}
