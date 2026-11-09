package main

import (
	"encoding/json"
	"log"
	"os"
	"path/filepath"

	"ano/anod/internal/autostart"
	"ano/anod/internal/config"
	"ano/anod/internal/ipc"
)

// autostartEntries reads autostart.entries from the effective config.
func autostartEntries() []autostart.Entry {
	m, err := config.Effective()
	if err != nil {
		log.Printf("autostart: %v", err)
		return nil
	}
	v, _ := config.Get(m, "autostart.entries")
	return autostart.Parse(v)
}

// registerAutostart adds the autostart.* methods. The list itself lives in
// the config (the shell's Settings edits it with Config.setNestedValue, as
// it owns the user config file); anod launches, reports and runs entries.
func registerAutostart(srv *ipc.Server, l *autostart.Launcher) {
	// autostart.list → {entries: [{index, desktopId, command, enabled, delayMs,
	// name, icon, error, launchedAt}], launchMode, autostartDir, desktopFiles}
	srv.Handle("autostart.list", func(json.RawMessage) (any, error) {
		dirs := autostart.SearchDirs()
		type row struct {
			Index int `json:"index"`
			autostart.Entry
			Name       string `json:"name"`
			Icon       string `json:"icon,omitempty"`
			Error      string `json:"error,omitempty"`
			LaunchedAt int64  `json:"launchedAt,omitempty"` // ms since epoch; 0: not by this anod
		}
		rows := []row{}
		for i, e := range autostartEntries() {
			r := row{Index: i, Entry: e, Name: e.Command}
			if e.DesktopID != "" {
				if d, err := autostart.FindDesktop(e.DesktopID, dirs); err == nil {
					r.Name, r.Icon = d.Name, d.Icon
				} else {
					r.Name, r.Error = e.DesktopID, err.Error()
				}
			}
			if st := l.StatusOf(e); !st.At.IsZero() {
				r.LaunchedAt = st.At.UnixMilli()
				if st.Error != "" {
					r.Error = st.Error
				}
			}
			rows = append(rows, r)
		}
		mode := "setsid"
		if l.Systemd() {
			mode = "systemd"
		}
		userDir := autostart.AutostartDirs()[0]
		files := autostart.ListDir(userDir)
		if files == nil {
			files = []autostart.DesktopFile{}
		}
		return map[string]any{"entries": rows, "launchMode": mode, "autostartDir": userDir, "desktopFiles": files}, nil
	})
	// autostart.run {index} — start that entry now, enabled or not.
	srv.Handle("autostart.run", func(p json.RawMessage) (any, error) {
		var req struct {
			Index *int `json:"index"`
		}
		entries := autostartEntries()
		if err := json.Unmarshal(p, &req); err != nil || req.Index == nil || *req.Index < 0 || *req.Index >= len(entries) {
			return nil, ipc.Errorf(ipc.CodeBadInput, "want {index} of autostart.entries")
		}
		if err := l.Launch(entries[*req.Index]); err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return true, nil
	})
}

// autostartOnce launches the enabled entries the first time anod runs in
// this graphical session.
func autostartOnce(l *autostart.Launcher, session string) {
	if os.Getenv("XDG_RUNTIME_DIR") == "" || session == "gone" {
		return
	}
	m := autostart.Marker{Path: filepath.Join(os.Getenv("XDG_RUNTIME_DIR"), "ano", "autostart.session")}
	first, err := m.Claim(session)
	if err != nil {
		log.Printf("autostart: %v", err)
		return
	}
	if !first {
		return
	}
	if n := l.RunAll(autostartEntries()); n > 0 {
		log.Printf("autostart: %d startup application(s) for this session", n)
	}
}
