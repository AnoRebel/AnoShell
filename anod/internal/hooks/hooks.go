// Package hooks runs user commands on shell events (idea from Noctalia v5).
// Each hook gets ANO_EVENT plus ANO_<KEY> variables for the event data, runs
// in its own process group, and is killed when it exceeds its timeout.
package hooks

import (
	"context"
	"log"
	"os"
	"os/exec"
	"strings"
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
}

// Fire starts the hook for event (if any) and returns at once. The returned
// channel closes when the hook has finished (tests wait on it).
func (r *Runner) Fire(event string, data map[string]string) (started bool, done <-chan struct{}) {
	cfg := r.Config()
	cmdline := strings.TrimSpace(cfg.Commands[event])
	ch := make(chan struct{})
	if !cfg.Enable || cmdline == "" {
		close(ch)
		return false, ch
	}
	timeout := cfg.Timeout
	if timeout <= 0 {
		timeout = 10 * time.Second
	}
	go func() {
		defer close(ch)
		r.run(event, cmdline, data, timeout)
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
	cmd := exec.Command("sh", "-c", cmdline)
	cmd.Env = append(os.Environ(), "ANO_EVENT="+event)
	for k, v := range data {
		cmd.Env = append(cmd.Env, "ANO_"+EnvName(k)+"="+v)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var out strings.Builder
	cmd.Stdout, cmd.Stderr = &out, &out
	if err := cmd.Start(); err != nil {
		r.logf("hook %s: start: %v", event, err)
		return
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		if err != nil {
			r.logf("hook %s: %v: %s", event, err, tail(out.String()))
		}
	case <-ctx.Done():
		syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		<-done
		r.logf("hook %s: killed after %s timeout", event, timeout)
	}
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
