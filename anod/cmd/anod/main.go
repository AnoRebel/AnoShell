// anod is ano's companion daemon: the control socket, event hooks and
// (opt-in) supervision of the `qs -c ano` shell. See ano/docs/anod.md.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"ano/anod/internal/config"
	"ano/anod/internal/hooks"
	"ano/anod/internal/ipc"
	"ano/anod/internal/supervisor"
	"ano/anod/internal/version"
)

func main() {
	supervise := flag.Bool("supervise", false, "start `qs -c ano` and restart it after crashes")
	socket := flag.String("socket", ipc.DefaultSocketPath(), "control socket path")
	showVersion := flag.Bool("version", false, "print the version and exit")
	flag.Parse()
	if *showVersion {
		fmt.Printf("anod %s (API v%d)\n", version.Version, version.API)
		return
	}
	setupLog()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	go exitWithCompositor(ctx, stop)

	started := time.Now()
	runner := &hooks.Runner{Config: hookConfig, Logf: log.Printf}
	srv := ipc.NewServer(*socket)

	var sup *supervisor.Supervisor
	if *supervise {
		sup = &supervisor.Supervisor{
			Cmd:         []string{"qs", "-c", "ano"},
			Notify:      notify,
			CrashReport: supervisor.QuickshellCrashReport,
		}
	}

	srv.Handle("ping", func(json.RawMessage) (any, error) { return "pong", nil })
	srv.Handle("version", func(json.RawMessage) (any, error) {
		return map[string]any{"version": version.Version, "api": version.API}, nil
	})
	srv.Handle("status", func(json.RawMessage) (any, error) {
		st := map[string]any{
			"version": version.Version, "api": version.API, "pid": os.Getpid(),
			"uptimeSeconds": int(time.Since(started).Seconds()), "clients": srv.Clients(),
			"hooks": hookConfig().Enable,
		}
		if sup != nil {
			st["supervisor"] = sup.Status()
		}
		return st, nil
	})
	// The shell reports events it owns (lock, theme mode, wifi, battery, …);
	// anod runs the user's hook and re-broadcasts to subscribers.
	srv.Handle("event.emit", func(p json.RawMessage) (any, error) {
		var req struct {
			Event string         `json:"event"`
			Data  map[string]any `json:"data"`
		}
		if err := json.Unmarshal(p, &req); err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
		}
		if _, ok := hooks.Events[req.Event]; !ok {
			return nil, ipc.Errorf(ipc.CodeBadInput, "unknown event %q", req.Event)
		}
		data := map[string]string{}
		for k, v := range req.Data {
			data[k] = fmt.Sprint(v)
		}
		ran, _ := runner.Fire(req.Event, data)
		srv.Broadcast(req.Event, req.Data)
		return map[string]any{"hook": ran}, nil
	})
	srv.Handle("config.validate", func(json.RawMessage) (any, error) {
		s, err := config.LoadSchema()
		if err != nil {
			return nil, err
		}
		m, err := config.Load(config.UserPath())
		if err != nil {
			return nil, err
		}
		return s.Validate(m), nil
	})

	if err := srv.Listen(); err != nil {
		log.Fatalf("anod: %v", err)
	}
	log.Printf("anod %s listening on %s (supervise=%v)", version.Version, *socket, *supervise)
	if sup != nil {
		go func() {
			st := sup.Run(ctx)
			log.Printf("supervisor: %s (%s)", st, sup.Status().LastExit)
		}()
	}
	if err := srv.Serve(ctx); err != nil {
		log.Fatalf("anod: %v", err)
	}
	log.Print("anod stopped")
}

// hookConfig reads hooks.* from the effective config on every event, so edits apply live.
func hookConfig() hooks.Config {
	m, err := config.Effective()
	if err != nil {
		log.Printf("hooks: %v", err)
		return hooks.Config{}
	}
	c := hooks.Config{
		Enable:   config.Bool(m, "hooks.enable", true),
		Timeout:  time.Duration(config.Int(m, "hooks.timeoutSeconds", 10)) * time.Second,
		Commands: map[string]string{},
	}
	for ev, key := range hooks.Events {
		c.Commands[ev] = config.String(m, "hooks."+key, "")
	}
	return c
}

func notify(title, body string) {
	if err := exec.Command("notify-send", "-a", "anod", "-u", "critical", title, body).Run(); err != nil {
		log.Printf("notify: %v", err)
	}
}

// setupLog writes to stderr and $XDG_STATE_HOME/ano/anod.log (reset past 1 MB).
func setupLog() {
	log.SetFlags(log.LstdFlags)
	dir := os.Getenv("XDG_STATE_HOME")
	if dir == "" {
		h, _ := os.UserHomeDir()
		dir = filepath.Join(h, ".local", "state")
	}
	dir = filepath.Join(dir, "ano")
	if os.MkdirAll(dir, 0o700) != nil {
		return
	}
	p := filepath.Join(dir, "anod.log")
	flags := os.O_CREATE | os.O_WRONLY | os.O_APPEND
	if fi, err := os.Stat(p); err == nil && fi.Size() > 1<<20 {
		flags |= os.O_TRUNC
	}
	if f, err := os.OpenFile(p, flags, 0o600); err == nil {
		log.SetOutput(io.MultiWriter(os.Stderr, f))
	}
}

// exitWithCompositor stops anod when the Wayland session it started in is gone,
// so a stale daemon never supervises a shell into a dead display.
func exitWithCompositor(ctx context.Context, stop func()) {
	wd := os.Getenv("WAYLAND_DISPLAY")
	if wd == "" {
		return
	}
	if !filepath.IsAbs(wd) {
		wd = filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), wd)
	}
	t := time.NewTicker(30 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if _, err := os.Stat(wd); err != nil {
				log.Printf("wayland display %s is gone; exiting", wd)
				stop()
				return
			}
		}
	}
}
