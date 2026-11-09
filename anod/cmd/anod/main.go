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
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"ano/anod/internal/atelier"
	"ano/anod/internal/autostart"
	"ano/anod/internal/camera"
	"ano/anod/internal/config"
	"ano/anod/internal/display"
	"ano/anod/internal/downloads"
	"ano/anod/internal/hooks"
	"ano/anod/internal/ipc"
	"ano/anod/internal/keybinds"
	"ano/anod/internal/palette"
	"ano/anod/internal/reader"
	"ano/anod/internal/screentime"
	"ano/anod/internal/secrets"
	"ano/anod/internal/supervisor"
	"ano/anod/internal/version"
	"ano/anod/internal/wallpaper"
	"ano/anod/internal/xkb"
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
		if m, err := config.Effective(); err == nil {
			sup.NoHugePages = !config.Bool(m, "shell.hugePages", false)
		}
	}

	srv.Handle("ping", func(json.RawMessage) (any, error) { return "pong", nil })
	starter := &autostart.Launcher{Logf: log.Printf}
	registerAutostart(srv, starter)
	registerBackup(srv)
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
		Choices:    &wallpaper.Choices{Path: filepath.Join(stateDir, "wallpaper-colors.json")},
		ColorCache: filepath.Join(xdgCache(), "anoshell", "colors"),
		GtkDirs: []string{filepath.Join(filepath.Dir(filepath.Dir(config.UserPath())), "gtk-3.0"),
			filepath.Join(filepath.Dir(filepath.Dir(config.UserPath())), "gtk-4.0")},
		Logf: log.Printf,
	}
	// hook: run the user's wallpaper_changed hook (once per change/cycle).
	announce := func(res wallpaper.Result, s wallpaper.Settings, hook bool) {
		if hook {
			runner.Fire("wallpaper_changed", map[string]string{"wallpaper": res.Image, "themeMode": res.Scheme.Mode})
		}
		srv.Broadcast("wallpaper_changed", map[string]any{"wallpaper": res.Image, "outputs": res.Outputs,
			"themeMode": res.Scheme.Mode, "scheme": res.Scheme, "custom": res.Custom, "colorImage": res.ColorImage,
			"resize": res.Resize, "engine": s.Engine, "steps": res.Steps})
	}
	rot := &wallpaper.Rotator{
		Pipeline: wp,
		BagPath:  filepath.Join(stateDir, "rotation.json"),
		Settings: wallpaperSettings,
		OnApply:  func(r wallpaper.Result, first bool) { _, s := wallpaperSettings(); announce(r, s, first) },
	}
	srv.HandleSlow("wallpaper.set", func(p json.RawMessage) (any, error) {
		var req struct {
			wallpaper.Request
			Transition string `json:"transition"` // "none": the caller animates (the picker's card grows into it)
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Image == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {image, outputs?, mode?, schemeType?, prefer?, transition?, colorsOnly?}")
		}
		_, s := wallpaperSettings()
		if req.Transition == "none" {
			s.Transition = "none"
		}
		res, err := wp.Apply(ctx, req.Request, s)
		if err != nil || req.ColorsOnly { // colours only: nothing new on screen to announce
			return res, err
		}
		announce(res, s, true)
		return res, nil
	})
	// Colours redone without a new wallpaper: announced so the shell shows
	// what they were made with.
	recolor := func(r wallpaper.Request, s wallpaper.Settings) (wallpaper.Result, error) {
		res, err := wp.Apply(ctx, r, s)
		if err == nil && res.ColorImage != "" {
			srv.Broadcast("wallpaper_colors", map[string]any{"scheme": res.Scheme, "custom": res.Custom, "colorImage": res.ColorImage})
		}
		return res, err
	}
	// Colour picks for the wallpaper the colours follow (or image):
	// remembered (remember), forgotten (reset), then its colours redone. With
	// no pick, reset or recolor it only reports.
	srv.HandleSlow("wallpaper.colors", func(p json.RawMessage) (any, error) {
		var req struct {
			Image string `json:"image"`
			wallpaper.Choice
			Remember bool `json:"remember"`
			Reset    bool `json:"reset"`
			Recolor  bool `json:"recolor"`
		}
		if err := json.Unmarshal(p, &req); err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {image?, schemeType?, prefer?, mode?, remember?, reset?, recolor?}")
		}
		_, s := wallpaperSettings()
		img := wp.ColorImage(s)
		if req.Image != "" {
			img, _ = filepath.Abs(expandHome(req.Image))
		}
		if img == "" {
			return map[string]any{"scheme": nil, "custom": false, "image": ""}, nil
		}
		picked := req.Choice != (wallpaper.Choice{})
		if req.Reset || req.Remember && picked {
			if _, err := wp.Choices.Set(img, req.Choice, req.Reset); err != nil {
				return nil, err
			}
		}
		r := wallpaper.Request{Image: img, ColorsOnly: true, Choice: req.Choice}
		if !picked && !req.Reset && !req.Recolor {
			s.SkipColors, s.Hooks = true, nil // report only
			res, err := wp.Apply(ctx, r, s)
			return map[string]any{"scheme": res.Scheme, "custom": res.Custom, "image": img}, err
		}
		res, err := recolor(r, s)
		return map[string]any{"scheme": res.Scheme, "custom": res.Custom, "image": img}, err
	})
	// The focused output (from the shell): with appearance.colors.from
	// "focused", the colours follow its wallpaper.
	srv.HandleSlow("wallpaper.focus", func(p json.RawMessage) (any, error) {
		var req struct {
			Output string `json:"output"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Output == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {output}")
		}
		focusedOutput.Store(req.Output)
		_, s := wallpaperSettings()
		img := wp.ColorImage(s)
		if s.ColorOutput != req.Output || img == "" || img == wp.LoadState().Colors {
			return false, nil
		}
		_, err := recolor(wallpaper.Request{Image: img, ColorsOnly: true}, s)
		return err == nil, err
	})
	// The GTK palette block now: written or removed per appearance.theme.gtk
	// (the Settings switch, so turning it off doesn't wait for a wallpaper).
	srv.Handle("theme.gtk", func(json.RawMessage) (any, error) {
		_, s := wallpaperSettings()
		st := wp.Gtk(s)
		if st.Error != "" {
			return nil, errors.New(st.Error)
		}
		return st, nil
	})
	registerThemes(ctx, srv, wp)
	srv.Handle("wallpaper.next", func(json.RawMessage) (any, error) { rot.Next(); return true, nil })
	srv.Handle("wallpaper.status", func(json.RawMessage) (any, error) {
		rs, _ := wallpaperSettings()
		return map[string]any{"state": wp.LoadState(), "rotation": map[string]any{
			"enable": rs.Enable, "dir": rs.Dir, "intervalSeconds": int(rs.Interval.Seconds())}}, nil
	})
	go rot.Run(ctx)

	// Who holds a camera open (privacy indicator): inotify on /dev/video*,
	// /proc looked at only on device activity.
	cams := &camera.Watcher{Proc: "/proc", Dev: "/dev", Sys: "/sys/class/video4linux",
		Settle: 1500 * time.Millisecond, Notify: srv.Broadcast}
	go func() {
		if err := cams.Run(ctx); err != nil {
			log.Printf("camera watcher: %v", err)
		}
	}()
	srv.Handle("camera.users", func(json.RawMessage) (any, error) {
		return map[string]any{"holders": cams.Current()}, nil
	})

	// Downloads in progress in the download folder (bar/pill module "downloads").
	{
		home, _ := os.UserHomeDir()
		cfgHome := os.Getenv("XDG_CONFIG_HOME")
		if cfgHome == "" {
			cfgHome = filepath.Join(home, ".config")
		}
		dls := &downloads.Watcher{Dir: downloads.Dir(cfgHome, home), Notify: srv.Broadcast}
		go func() {
			if err := dls.Run(ctx); err != nil {
				log.Printf("downloads watcher: %v", err)
			}
		}()
		srv.Handle("downloads.list", func(json.RawMessage) (any, error) { return dls.State(), nil })
		srv.Handle("downloads.clear", func(raw json.RawMessage) (any, error) {
			var p struct {
				Path string `json:"path"`
			}
			json.Unmarshal(raw, &p)
			dls.Clear(p.Path)
			return dls.State(), nil
		})
	}

	// Palette cache for the wallpaper picker (hue sort) and glass (luminance).
	cacheDir := filepath.Join(xdgCache(), "anoshell")
	pal := &palette.Cache{Path: filepath.Join(cacheDir, "palette.json"), StillDir: filepath.Join(cacheDir, "stills"), Logf: log.Printf}
	wp.Still = func(ctx context.Context, path string) (string, error) {
		e, err := pal.Get(ctx, path)
		return e.Still, err
	}
	// Slow: a cold scan runs matugen per file; the shell's other calls go on meanwhile.
	srv.HandleSlow("palette.scan", func(p json.RawMessage) (any, error) {
		var req struct {
			Dir string `json:"dir"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Dir == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {dir}")
		}
		return pal.Scan(ctx, expandHome(req.Dir))
	})
	srv.HandleSlow("palette.get", func(p json.RawMessage) (any, error) {
		var req struct {
			Path string `json:"path"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Path == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {path}")
		}
		return pal.Get(ctx, expandHome(req.Path))
	})

	// API keys live in $XDG_DATA_HOME/anoshell/secrets/<name> (0600), never
	// in config.json. The shell reads the file; it writes through here.
	srv.Handle("secret.set", func(p json.RawMessage) (any, error) {
		var req struct {
			Name  string `json:"name"`
			Value string `json:"value"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Name == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {name, value}")
		}
		if _, err := secrets.Path(req.Name); err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
		}
		if err := secrets.Set(req.Name, req.Value); err != nil {
			return nil, err
		}
		return true, nil
	})

	// Reader backend (novel/manga/anime panels): a lazy local HTTP server,
	// started by the first panel and stopped after reader.idleTimeout.
	home, _ := os.UserHomeDir()
	rd := &reader.Service{
		Settings:  readerSettings,
		DataDir:   filepath.Join(xdgData(), "anoshell", "reader"),
		CacheDir:  filepath.Join(cacheDir, "reader"),
		LegacyDir: filepath.Join(home, ".local", "share", "quickshell"),
		Logf:      log.Printf,
	}
	defer rd.Shutdown()
	readerKind := func(p json.RawMessage) (string, error) {
		var req struct {
			Kind string `json:"kind"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Kind == "" {
			return "", ipc.Errorf(ipc.CodeBadInput, "want {kind: anime|manga|novel}")
		}
		return req.Kind, nil
	}
	// Slow: a start can wait on a Python fallback booting.
	srv.HandleSlow("reader.open", func(p json.RawMessage) (any, error) {
		kind, err := readerKind(p)
		if err != nil {
			return nil, err
		}
		return rd.Open(kind)
	})
	srv.Handle("reader.close", func(p json.RawMessage) (any, error) {
		kind, err := readerKind(p)
		if err != nil {
			return nil, err
		}
		return rd.Close(kind), nil
	})
	srv.Handle("reader.status", func(json.RawMessage) (any, error) { return rd.Status(), nil })
	srv.Handle("reader.stop", func(json.RawMessage) (any, error) { rd.StopPlayback(); return true, nil })

	// Keybinds (Settings → Keybinds): one set, rendered for Hyprland and niri.
	kbApply := func(o keybinds.Overrides) (any, error) {
		d, err := keybinds.LoadDefaults()
		if err != nil {
			return nil, err
		}
		p := keybinds.DefaultPaths()
		if err := keybinds.SaveOverrides(p.Overrides, o); err != nil {
			return nil, err
		}
		h, _, err := keybinds.Generate(p, keybinds.Effective(d, o), keybinds.AllHelpers(d, o))
		if err == nil && h {
			err = keybinds.Reload()
		}
		return true, err
	}
	srv.Handle("keybinds.list", func(json.RawMessage) (any, error) {
		d, err := keybinds.LoadDefaults()
		if err != nil {
			return nil, err
		}
		o, err := keybinds.LoadOverrides(keybinds.DefaultPaths().Overrides)
		if err != nil {
			return nil, err
		}
		type row struct {
			keybinds.Bind
			Hyprland bool   `json:"onHyprland"`
			Niri     bool   `json:"onNiri"`
			Label    string `json:"label"`
		}
		var rows []row
		for _, b := range keybinds.Effective(d, o) {
			rows = append(rows, row{b, b.On("hyprland"), b.On("niri"), b.Describe()})
		}
		return map[string]any{"binds": rows, "overrides": o, "migrated": keybinds.Migrated(keybinds.DefaultPaths())}, nil
	})
	srv.Handle("keybinds.set", func(p json.RawMessage) (any, error) {
		var req struct {
			Chord   string         `json:"chord"`
			Submap  string         `json:"submap"`
			Bind    *keybinds.Bind `json:"bind"` // null removes the chord
			Replace bool           `json:"replace"`
		}
		if err := json.Unmarshal(p, &req); err != nil || req.Chord == "" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {chord, bind|null, replace?, submap?}")
		}
		d, err := keybinds.LoadDefaults()
		if err != nil {
			return nil, err
		}
		o, err := keybinds.LoadOverrides(keybinds.DefaultPaths().Overrides)
		if err != nil {
			return nil, err
		}
		o, err = keybinds.Set(d, o, req.Chord, req.Submap, req.Bind, req.Replace)
		var ce *keybinds.ConflictError
		if errors.As(err, &ce) {
			return nil, ipc.Errorf("conflict", "%v", ce)
		}
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
		}
		return kbApply(o)
	})
	// The cheatsheet: what the running compositor binds, plus ano actions left unbound.
	srv.HandleSlow("keybinds.active", func(p json.RawMessage) (any, error) {
		var req struct {
			Compositor string `json:"compositor"`
		}
		json.Unmarshal(p, &req)
		binds, unbound, err := keybinds.Active(keybinds.DefaultPaths(), req.Compositor)
		if err != nil {
			return nil, err
		}
		label := func(bs []keybinds.Bind) []map[string]any {
			out := []map[string]any{}
			for _, b := range bs {
				out = append(out, map[string]any{"chord": b.Chord, "action": b.Action, "args": b.Args, "label": b.Describe(), "submap": b.Submap})
			}
			return out
		}
		return map[string]any{"binds": label(binds), "unbound": label(unbound), "migrated": keybinds.Migrated(keybinds.DefaultPaths())}, nil
	})
	srv.Handle("keybinds.catalogue", func(json.RawMessage) (any, error) {
		out := map[string]any{}
		for id, a := range keybinds.Catalogue {
			out[id] = map[string]any{"label": a.Label, "arg": a.Arg, "hyprland": a.Hypr != nil, "niri": a.Niri != nil}
		}
		return out, nil
	})
	srv.Handle("keybinds.reset", func(p json.RawMessage) (any, error) {
		var req struct {
			Chord string `json:"chord"` // "" resets everything
		}
		json.Unmarshal(p, &req)
		o, err := keybinds.LoadOverrides(keybinds.DefaultPaths().Overrides)
		if err != nil {
			return nil, err
		}
		return kbApply(keybinds.Reset(o, req.Chord))
	})

	// Atelier (Settings → Atelier): content store, catalogs, rices.
	hb := atelier.New()
	hb.CurrentWallpaper = func() string { return wp.LoadState().Image }
	hb.SetWallpaper = func(img string) error {
		_, s := wallpaperSettings()
		res, err := wp.Apply(ctx, wallpaper.Request{Image: img}, s)
		if err == nil {
			announce(res, s, true)
		}
		return err
	}
	hb.KeybindsChanged = func() error {
		o, err := keybinds.LoadOverrides(keybinds.DefaultPaths().Overrides)
		if err != nil {
			return err
		}
		_, err = kbApply(o)
		return err
	}
	registerAtelier(srv, hb)

	// Displays (Settings → Displays): live apply, 15 s confirm-or-revert run
	// here (a shell crash can't strand a bad mode), managed include files, profiles.
	if dispBackend := displayBackend(); dispBackend != nil {
		if os.Getenv("ANOD_DISPLAY_DRYRUN") == "1" {
			dispBackend = &display.DryRun{Backend: dispBackend, Logf: log.Printf}
		}
		cfg := filepath.Dir(filepath.Dir(config.UserPath()))
		disp := &display.Service{
			Backend:     dispBackend,
			Deadline:    15 * time.Second,
			HyprFile:    filepath.Join(cfg, "hypr", "ano-managed.lua"),
			NiriFile:    filepath.Join(cfg, "niri", "ano-managed.kdl"),
			Profiles:    filepath.Join(cfg, "anoshell", "display-profiles.json"),
			Notify:      srv.Broadcast,
			Logf:        log.Printf,
			GtkSettings: []string{filepath.Join(cfg, "gtk-3.0", "settings.ini"), filepath.Join(cfg, "gtk-4.0", "settings.ini")},
			Cursor: func() *display.Cursor {
				m, err := config.Effective()
				if err != nil {
					return nil
				}
				c := display.Cursor{Theme: config.String(m, "cursor.theme", ""), Size: config.Int(m, "cursor.size", 24)}
				if c.Theme == "" {
					return nil
				}
				return &c
			},
			Keyboard: func() *display.Keyboard {
				m, err := config.Effective()
				if err != nil {
					return nil
				}
				k, err := keyboardFrom(m)
				if err != nil {
					return nil
				}
				return k
			},
		}
		if os.Getenv("ANOD_DISPLAY_DRYRUN") == "1" { // nothing outside anod's own files changes
			disp.GtkSettings = nil
			disp.Exec = func(name string, args ...string) error {
				log.Printf("display (dry run): would run %s %v", name, args)
				return nil
			}
		}
		// Cursor themes with a preview each (PNG in the cache, made once).
		srv.HandleSlow("cursor.themes", func(json.RawMessage) (any, error) {
			dir := filepath.Join(cacheDir, "cursor-previews")
			os.MkdirAll(dir, 0o755)
			var out []map[string]any
			for _, t := range display.CursorThemes(display.IconDirs()) {
				p := filepath.Join(dir, t.Name+".png")
				// redrawn when the theme is newer (a palette cursor is rebuilt in place)
				if pi, err := os.Stat(p); err != nil || themeNewer(t.Path, pi.ModTime()) {
					if b, err := display.Preview(t.Path, 48); err == nil {
						os.WriteFile(p, b, 0o644)
					} else {
						p = ""
					}
				}
				out = append(out, map[string]any{"name": t.Name, "title": t.Title, "preview": p})
			}
			return out, nil
		})
		srv.Handle("cursor.apply", func(p json.RawMessage) (any, error) {
			var c display.Cursor
			if err := json.Unmarshal(p, &c); err != nil {
				return nil, ipc.Errorf(ipc.CodeBadInput, "want {theme, size}")
			}
			if err := disp.SetCursor(c); err != nil {
				return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
			}
			return true, nil
		})
		// Keyboard layouts (Settings → Keyboard): applying keyboard.layouts
		// from the config live and into the managed files (the catalogue is
		// registered below, on every compositor).
		srv.Handle("keyboard.apply", func(json.RawMessage) (any, error) {
			m, err := config.Effective()
			if err != nil {
				return nil, err
			}
			k, err := keyboardFrom(m)
			if err != nil {
				return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
			}
			if k == nil { // empty list: the compositor config's own layouts
				return false, disp.ClearKeyboard()
			}
			if err := disp.SetKeyboard(*k); err != nil {
				return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
			}
			return true, nil
		})
		srv.Handle("display.get", func(json.RawMessage) (any, error) {
			outs, err := dispBackend.Current()
			if err != nil {
				return nil, err
			}
			ps, _ := disp.ListProfiles()
			return map[string]any{"outputs": outs, "pending": disp.PendingChange(), "profiles": ps, "compositor": dispBackend.Name(),
				"included": keybinds.Migrated(keybinds.DefaultPaths())}, nil
		})
		srv.Handle("display.apply", func(p json.RawMessage) (any, error) {
			var req struct {
				Outputs []display.Output `json:"outputs"`
			}
			if err := json.Unmarshal(p, &req); err != nil || len(req.Outputs) == 0 {
				return nil, ipc.Errorf(ipc.CodeBadInput, "want {outputs: [...]}")
			}
			pending, err := disp.Apply(req.Outputs)
			return map[string]any{"pending": pending}, err
		})
		srv.Handle("display.confirm", func(json.RawMessage) (any, error) { return true, disp.Confirm() })
		srv.Handle("display.revert", func(json.RawMessage) (any, error) { return true, disp.Revert() })
		srv.Handle("display.saveProfile", func(p json.RawMessage) (any, error) {
			var req struct {
				Name string `json:"name"`
			}
			if err := json.Unmarshal(p, &req); err != nil || strings.TrimSpace(req.Name) == "" {
				return nil, ipc.Errorf(ipc.CodeBadInput, "want {name}")
			}
			return true, disp.SaveProfile(strings.TrimSpace(req.Name))
		})
		// The shell reports a monitor plugged or unplugged; a matching profile applies.
		srv.Handle("display.outputsChanged", func(json.RawMessage) (any, error) {
			name, err := disp.OutputsChanged()
			return map[string]any{"profile": name}, err
		})
	} else {
		// No display backend here (an experimental or generic compositor):
		// layouts can still be listed, not applied.
		srv.Handle("keyboard.apply", func(json.RawMessage) (any, error) {
			return nil, ipc.Errorf(ipc.CodeFailed, "applying keyboard layouts isn't supported on this compositor yet; set them in its own config")
		})
	}
	srv.Handle("keyboard.catalogue", func(json.RawMessage) (any, error) { return xkb.Catalogue(xkb.Path) })

	// Screen time: the shell reports focused time; stored per day, pruned
	// after screenTime.keepDays (default 30), daily.
	st := &screentime.Store{Dir: filepath.Join(xdgState(), "anoshell", "screentime")}
	keepDays := func() int {
		m, err := config.Effective()
		if err != nil {
			return 30
		}
		return config.Int(m, "screenTime.keepDays", 30)
	}
	go func() {
		// Checked hourly against the wall clock: a 24 h sleep drifts across suspend.
		last := ""
		for {
			if today := time.Now().Format("2006-01-02"); today != last {
				last = today
				if n, err := st.Prune(time.Now(), keepDays()); err != nil {
					log.Printf("screentime prune: %v", err)
				} else if n > 0 {
					log.Printf("screentime: pruned %d old days", n)
				}
			}
			time.Sleep(time.Hour)
		}
	}()
	srv.Handle("screentime.add", func(p json.RawMessage) (any, error) {
		var req struct {
			App     string `json:"app"`
			Title   string `json:"title"`
			Seconds int    `json:"seconds"`
		}
		if err := json.Unmarshal(p, &req); err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {app, title, seconds}")
		}
		return true, st.Add(time.Now(), req.App, req.Title, req.Seconds)
	})
	srv.Handle("screentime.day", func(p json.RawMessage) (any, error) {
		var req struct {
			Date string `json:"date"`
		}
		json.Unmarshal(p, &req)
		if req.Date == "" {
			req.Date = time.Now().Format("2006-01-02")
		}
		if _, err := time.Parse("2006-01-02", req.Date); err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "date is YYYY-MM-DD")
		}
		return st.DaySummary(req.Date)
	})
	srv.Handle("screentime.week", func(json.RawMessage) (any, error) { return st.Week(time.Now()) })

	// A screen shader the shell set (eye-care filter, anti-flashbang) must not
	// outlive it: when its connection is gone, clear it (Hyprland).
	var shaderMu sync.Mutex
	shellShader := ""
	var shaderConn uint64 // the connection that set it
	srv.HandleConn("screen.shaderSet", func(conn uint64, p json.RawMessage) (any, error) {
		var req struct {
			Path string `json:"path"`
		}
		json.Unmarshal(p, &req)
		shaderMu.Lock()
		shellShader, shaderConn = req.Path, conn
		shaderMu.Unlock()
		return true, nil
	})
	srv.OnDisconnect = func(conn uint64) {
		shaderMu.Lock()
		defer shaderMu.Unlock()
		if conn != shaderConn || shellShader == "" || os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") == "" {
			return
		}
		log.Printf("the shell is gone: clearing its screen shader")
		if err := exec.Command("hyprctl", "eval", `hl.config({ decoration = { screen_shader = "" }, debug = { damage_tracking = 2 } })`).Run(); err != nil {
			log.Printf("clear screen shader: %v", err)
		}
		shellShader = ""
	}

	if err := listenOrTakeOver(srv, *socket, session); err != nil {
		log.Fatalf("anod: %v", err)
	}
	log.Printf("anod %s listening on %s (supervise=%v)", version.Version, *socket, *supervise)
	go autostartOnce(starter, session) // startup applications, once per session
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

// themeNewer: the theme directory changed after t (it is swapped in whole on a rebuild).
func themeNewer(dir string, t time.Time) bool {
	fi, err := os.Stat(dir)
	return err == nil && fi.ModTime().After(t)
}

func xdgCache() string {
	if d := os.Getenv("XDG_CACHE_HOME"); d != "" {
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".cache")
}

// keyboardFrom reads keyboard.layouts ([{layout, variant}]) and checks it
// against the XKB catalogue; nil for an empty list.
func keyboardFrom(m map[string]any) (*display.Keyboard, error) {
	v, _ := config.Get(m, "keyboard.layouts")
	list, _ := v.([]any)
	if len(list) == 0 {
		return nil, nil
	}
	var picks []xkb.Layout
	for _, e := range list {
		o, _ := e.(map[string]any)
		l, _ := o["layout"].(string)
		vr, _ := o["variant"].(string)
		picks = append(picks, xkb.Layout{Layout: l, Variant: vr})
	}
	cat, err := xkb.Catalogue(xkb.Path)
	if err != nil {
		return nil, err
	}
	ls, vs, err := xkb.Join(cat, picks)
	if err != nil {
		return nil, err
	}
	return &display.Keyboard{Layouts: ls, Variants: vs}, nil
}

func expandHome(p string) string {
	if p == "~" || strings.HasPrefix(p, "~/") {
		home, _ := os.UserHomeDir()
		return filepath.Join(home, strings.TrimPrefix(p, "~"))
	}
	return p
}

// displayBackend picks the running compositor's (nil when neither).
func displayBackend() display.Backend {
	switch {
	case os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "":
		return display.Hyprland{}
	case os.Getenv("NIRI_SOCKET") != "":
		return display.Niri{}
	}
	return nil
}

func xdgData() string {
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "share")
}

// readerProviders maps each reader to its source's config id.
var readerProviders = map[string]string{"anime": "allanime", "manga": "weebcentral", "novel": "freewebnovel"}

// readerSettings reads reader.* when the backend starts.
func readerSettings() reader.Settings {
	m, err := config.Effective()
	if err != nil {
		log.Printf("reader: %v", err)
		m = map[string]any{}
	}
	s := reader.Settings{
		IdleTimeout: time.Duration(config.Int(m, "reader.idleTimeout", 120)) * time.Second,
		CacheMB:     config.Int(m, "reader.cacheMB", 64),
		MetaEntries: config.Int(m, "reader.metaCacheEntries", 512),
		Python:      config.String(m, "reader.python", "python3"),
		ScriptsDir:  filepath.Join(config.ShellDir(), "scripts", "reader"),
		Backends:    map[string]string{},
	}
	for kind, id := range readerProviders {
		s.Backends[kind] = config.String(m, "reader.providers."+id+".backend", "go")
	}
	return s
}

func xdgState() string {
	if d := os.Getenv("XDG_STATE_HOME"); d != "" {
		return d
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "state")
}

// awwwTransition maps Settings' transition names to awww's --transition-type
// (anything unknown fades, so a bad value never fails the apply). A slide runs
// in `dir` (the arrow in Settings): "right" sweeps from the left edge.
func awwwTransition(typ, dir string) string {
	switch typ {
	case "none", "fade", "simple", "wipe", "wave", "grow", "center", "outer", "any", "random", "left", "right", "top", "bottom":
		return typ
	case "zoom":
		return "grow"
	case "slideRight", "slide":
		switch dir {
		case "left":
			return "right"
		case "down":
			return "top"
		case "up":
			return "bottom"
		}
		return "left"
	}
	return "fade"
}

// wallpaperSettings reads background.* and the colour settings on every use.
// focusedOutput is the shell's focused output (wallpaper.focus).
var focusedOutput atomic.Value

func wallpaperSettings() (wallpaper.RotationSettings, wallpaper.Settings) {
	m, err := config.Effective()
	if err != nil {
		log.Printf("wallpaper: %v", err)
		m = map[string]any{}
	}
	trans := awwwTransition(config.String(m, "background.transition.type", "fade"),
		config.String(m, "background.transition.direction", "right"))
	if !config.Bool(m, "background.transition.enable", true) {
		trans = "none"
	}
	mode := "dark"
	if !config.Bool(m, "appearance.colors.darkMode", true) {
		mode = "light"
	}
	s := wallpaper.Settings{
		Resize:       config.String(m, "background.resize", "fit"),
		Engine:       config.String(m, "background.engine", "awww"),
		Transition:   trans,
		DurationMs:   config.Int(m, "background.transition.duration", 800),
		Mode:         mode,
		SchemeType:   config.String(m, "appearance.colors.schemeType", "tonal-spot"),
		Prefer:       config.String(m, "appearance.colors.prefer", "saturation"),
		PerWallpaper: config.Bool(m, "appearance.colors.perWallpaper", true),
		Gtk:          config.Bool(m, "appearance.theme.gtk", true),
	}
	// A static theme's palette is applied by theme.apply; the brand palette
	// (colour mode fixed) leaves app colours alone.
	s.StaticTheme = config.String(m, "appearance.theme.source", "materialYou") == "static"
	s.FixedColor = !s.StaticTheme && config.String(m, "appearance.theme.colorMode", "dynamicAccent") == "fixed"
	// Which wallpaper sets the colours: the last one set ("last"), a chosen
	// monitor's ("monitor") or the focused monitor's ("focused").
	switch config.String(m, "appearance.colors.from", "last") {
	case "monitor":
		s.ColorOutput = config.String(m, "appearance.colors.monitor", "")
	case "focused":
		s.ColorOutput, _ = focusedOutput.Load().(string)
	}
	if raw, ok := config.Get(m, "background.hooks"); ok {
		b, _ := json.Marshal(raw)
		_ = json.Unmarshal(b, &s.Hooks)
	}
	rs := wallpaper.RotationSettings{
		Enable:   config.Bool(m, "background.randomize.enable", false),
		Dir:      config.RotationDir(m),
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
