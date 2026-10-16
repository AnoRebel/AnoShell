// anod is ano's companion daemon: the control socket, event hooks and
// (opt-in) supervision of the `qs -c ano` shell. See ano/docs/anod.md.
package main

import (
	"context"
	"encoding/json"
	"errors"
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
	"ano/anod/internal/wallpaper"
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
	session := sessionID()
	alive := func() bool { return session == "" || sessionID() == session }
	go exitWithSession(ctx, stop, alive)

	started := time.Now()
	runner := &hooks.Runner{Config: hookConfig, Logf: log.Printf}
	srv := ipc.NewServer(*socket)

	var sup *supervisor.Supervisor
	if *supervise {
		sup = &supervisor.Supervisor{
			Cmd:         []string{"qs", "-c", "ano"},
			Notify:      notify,
			CrashReport: supervisor.QuickshellCrashReport,
			Alive:       alive,
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
			"hooks": hookConfig().Enable, "session": session,
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
	// A newer session's anod asks a stale one (from a session that ended) to go.
	srv.Handle("shutdown", func(json.RawMessage) (any, error) {
		log.Print("shutdown requested over the socket")
		go func() { time.Sleep(100 * time.Millisecond); stop() }()
		return true, nil
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

	// Wallpaper pipeline (replaces switchwall.sh and the awww randomize loop).
	stateDir := filepath.Join(xdgState(), "anoshell")
	wp := &wallpaper.Pipeline{
		ColorsPath: filepath.Join(stateDir, "generated", "colors.json"),
		StatePath:  filepath.Join(stateDir, "wallpaper.json"),
		Logf:       log.Printf,
	}
	announce := func(res wallpaper.Result, s wallpaper.Settings) {
		data := map[string]string{"wallpaper": res.Image, "themeMode": s.Mode}
		runner.Fire("wallpaper_changed", data)
		srv.Broadcast("wallpaper_changed", map[string]any{"wallpaper": res.Image, "themeMode": s.Mode, "resize": res.Resize, "steps": res.Steps})
	}
	rot := &wallpaper.Rotator{
		Pipeline: wp,
		BagPath:  filepath.Join(stateDir, "rotation.json"),
		Settings: wallpaperSettings,
		OnApply:  func(r wallpaper.Result) { _, s := wallpaperSettings(); announce(r, s) },
	}
	srv.Handle("wallpaper.set", func(p json.RawMessage) (any, error) {
		var req struct {
			wallpaper.Request
			Mode string `json:"mode"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Image == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {image, outputs?, mode?}")
		}
		_, s := wallpaperSettings()
		if req.Mode == "dark" || req.Mode == "light" {
			s.Mode = req.Mode
		}
		res, err := wp.Apply(ctx, req.Request, s)
		if err != nil {
			return res, err
		}
		announce(res, s)
		return res, nil
	})
	srv.Handle("wallpaper.next", func(json.RawMessage) (any, error) { rot.Next(); return true, nil })
	srv.Handle("wallpaper.status", func(json.RawMessage) (any, error) {
		rs, _ := wallpaperSettings()
		return map[string]any{"state": wp.LoadState(), "rotation": map[string]any{
			"enable": rs.Enable, "dir": rs.Dir, "intervalSeconds": int(rs.Interval.Seconds())}}, nil
	})
	go rot.Run(ctx)

	if err := listenOrTakeOver(srv, *socket, session); err != nil {
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

func xdgState() string {
	if d := os.Getenv("XDG_STATE_HOME"); d != "" {
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state")
}

// wallpaperSettings reads background.* and the colour settings on every use.
func wallpaperSettings() (wallpaper.RotationSettings, wallpaper.Settings) {
	m, err := config.Effective()
	if err != nil {
		log.Printf("wallpaper: %v", err)
		m = map[string]any{}
	}
	trans := config.String(m, "background.transition.type", "fade")
	switch trans {
	case "crossfade", "":
		trans = "fade"
	}
	if !config.Bool(m, "background.transition.enable", true) {
		trans = "none"
	}
	mode := "dark"
	if !config.Bool(m, "appearance.colors.darkMode", true) {
		mode = "light"
	}
	s := wallpaper.Settings{
		Resize:     config.String(m, "background.resize", "fit"),
		Transition: trans,
		DurationMs: config.Int(m, "background.transition.duration", 800),
		Mode:       mode,
		SchemeType: config.String(m, "appearance.colors.schemeType", "tonal-spot"),
		Prefer:     config.String(m, "appearance.colors.prefer", "saturation"),
		FixedColor: config.String(m, "appearance.theme.colorMode", "dynamicAccent") == "fixed" ||
			config.String(m, "appearance.theme.source", "materialYou") == "static",
	}
	if raw, ok := config.Get(m, "background.hooks"); ok {
		b, _ := json.Marshal(raw)
		_ = json.Unmarshal(b, &s.Hooks)
	}
	rs := wallpaper.RotationSettings{
		Enable:   config.Bool(m, "background.randomize.enable", false),
		Dir:      config.String(m, "background.randomize.directory", "~/Pictures/Wallpapers"),
		Interval: time.Duration(config.Int(m, "background.randomize.interval", 300)) * time.Second,
	}
	return rs, s
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
	if f, err := os.OpenFile(p, flags, 0o600); err == nil {
		log.SetOutput(io.MultiWriter(os.Stderr, &cappedFile{f: f, max: 1 << 20}))
	}
}

// cappedFile starts the log over once it passes max bytes (checked per write,
// so a long-running anod's log stays bounded).
type cappedFile struct {
	f   *os.File
	max int64
}

func (c *cappedFile) Write(p []byte) (int, error) {
	if fi, err := c.f.Stat(); err == nil && fi.Size()+int64(len(p)) > c.max {
		c.f.Truncate(0) // O_APPEND: the next write lands at offset 0
	}
	return c.f.Write(p)
}

// sessionID identifies the graphical session anod started in: the Wayland
// socket's path, inode and change time (a new login recreates it, even under
// the same name), plus Hyprland's instance signature. "" outside Wayland.
func sessionID() string {
	wd := os.Getenv("WAYLAND_DISPLAY")
	if wd == "" {
		return ""
	}
	if !filepath.IsAbs(wd) {
		wd = filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), wd)
	}
	var st syscall.Stat_t
	if err := syscall.Stat(wd, &st); err != nil {
		return "gone"
	}
	return fmt.Sprintf("%s:%d:%d:%s", wd, st.Ino, st.Ctim.Nano(), os.Getenv("HYPRLAND_INSTANCE_SIGNATURE"))
}

// listenOrTakeOver binds the socket. If another anod holds it and belongs to a
// different (ended) session, it is asked to shut down and anod retries for 5 s;
// an anod of this same session is a real duplicate and wins.
func listenOrTakeOver(srv *ipc.Server, sock, session string) error {
	err := srv.Listen()
	if !errors.Is(err, ipc.ErrRunning) {
		return err
	}
	res, cerr := ipc.Call(sock, "status", nil)
	var st struct {
		Session string `json:"session"`
		PID     int    `json:"pid"`
	}
	if cerr == nil {
		json.Unmarshal(res, &st)
	}
	if cerr == nil && st.Session == session {
		return err
	}
	log.Printf("taking over from a stale anod (pid %d, other session)", st.PID)
	ipc.Call(sock, "shutdown", nil)
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); time.Sleep(200 * time.Millisecond) {
		if err = srv.Listen(); !errors.Is(err, ipc.ErrRunning) {
			return err
		}
	}
	return err
}

// exitWithSession stops anod when its graphical session is gone, so a stale
// daemon never supervises a shell into a dead (or someone else's) display.
func exitWithSession(ctx context.Context, stop func(), alive func() bool) {
	t := time.NewTicker(5 * time.Second)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if !alive() {
				log.Print("the Wayland session anod started in has ended; exiting")
				stop()
				return
			}
		}
	}
}
