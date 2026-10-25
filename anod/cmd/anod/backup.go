package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sort"
	"time"

	"ano/anod/internal/backup"
	"ano/anod/internal/ipc"
)

// registerBackup serves `ano backup` over the socket for Settings → Backup
// (the same internal/backup implementation as the CLI).
//
//	backup.categories                       → [{name, desc, default}]
//	backup.list                             → [{path, created, files, categories}], newest first
//	backup.create  {only?, add?}            → {path, files, categories}
//	backup.restore {path, only?, dryRun?}   → {files, snapshot}
//
// Restore only takes archives from the backup folder (what backup.list
// returns); the CLI can restore any file. Create and restore can take long
// (wallpapers), so they don't hold up other requests on the connection.
func registerBackup(srv *ipc.Server) {
	home, _ := os.UserHomeDir()
	dir := backup.DefaultDir(home)

	srv.Handle("backup.categories", func(json.RawMessage) (any, error) {
		out := []map[string]any{}
		for _, c := range backup.Categories {
			out = append(out, map[string]any{"name": c.Name, "desc": c.Desc, "default": c.Default})
		}
		return out, nil
	})

	srv.Handle("backup.list", func(json.RawMessage) (any, error) {
		files, _ := filepath.Glob(filepath.Join(dir, "*.tar.gz"))
		sort.Sort(sort.Reverse(sort.StringSlice(files)))
		out := []map[string]any{}
		for _, f := range files {
			m, err := backup.ReadManifest(f)
			if err != nil {
				continue
			}
			out = append(out, map[string]any{"path": f, "created": m.Created.Unix(), "files": m.Files, "categories": m.Categories})
		}
		return out, nil
	})

	srv.HandleSlow("backup.create", func(raw json.RawMessage) (any, error) {
		var p struct {
			Only []string `json:"only"`
			Add  []string `json:"add"`
		}
		if len(raw) > 0 {
			if err := json.Unmarshal(raw, &p); err != nil {
				return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
			}
		}
		names := p.Only
		if len(names) == 0 && len(p.Add) > 0 {
			for _, c := range backup.Categories {
				if c.Default {
					names = append(names, c.Name)
				}
			}
			names = append(names, p.Add...)
		}
		cats, err := backup.Lookup(names)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
		}
		now := time.Now()
		dest := filepath.Join(dir, "anoshell-"+now.Format("20060102-150405")+".tar.gz")
		m, err := backup.Create(home, dest, cats, now)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeFailed, "%v", err)
		}
		return map[string]any{"path": dest, "files": m.Files, "categories": m.Categories}, nil
	})

	srv.HandleSlow("backup.restore", func(raw json.RawMessage) (any, error) {
		var p struct {
			Path   string   `json:"path"`
			Only   []string `json:"only"`
			DryRun bool     `json:"dryRun"`
		}
		if err := json.Unmarshal(raw, &p); err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
		}
		abs, err := filepath.Abs(p.Path)
		if err != nil || filepath.Dir(abs) != filepath.Clean(dir) || filepath.Ext(abs) != ".gz" {
			return nil, ipc.Errorf(ipc.CodeBadInput, "not a backup in %s", dir)
		}
		m, err := backup.ReadManifest(abs)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
		}
		names := p.Only
		if len(names) == 0 {
			names = m.Categories
		}
		for _, n := range names {
			found := false
			for _, c := range m.Categories {
				found = found || c == n
			}
			if !found {
				return nil, ipc.Errorf(ipc.CodeBadInput, "%q is not in this backup", n)
			}
		}
		cats, err := backup.Lookup(names)
		if err != nil {
			return nil, ipc.Errorf(ipc.CodeBadInput, "%v", err)
		}
		now := time.Now()
		snap := ""
		if !p.DryRun {
			snap = filepath.Join(dir, "pre-restore-"+now.Format("20060102-150405")+".tar.gz")
		}
		files, err := backup.Restore(home, abs, cats, snap, p.DryRun, now)
		if files == nil {
			files = []string{}
		}
		if err != nil {
			return map[string]any{"files": files, "snapshot": snap, "error": err.Error()}, nil
		}
		if len(files) == 0 {
			snap = ""
		}
		return map[string]any{"files": files, "snapshot": snap}, nil
	})
}
