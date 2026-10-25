package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"ano/anod/internal/backup"
	"ano/anod/internal/ipc"
)

// registerBackup serves `ano backup` over the socket for Settings → Backup
// (the same internal/backup implementation as the CLI).
//
//	backup.categories                       → [{name, desc, default}]
//	backup.list                             → [{path, created, files, categories, preRestore}], newest first
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
		out := []map[string]any{}
		for _, f := range files {
			m, err := backup.ReadManifest(f)
			if err != nil {
				continue
			}
			preRestore := strings.HasPrefix(filepath.Base(f), "pre-restore-") // what a restore replaced
			out = append(out, map[string]any{"path": f, "created": m.Created.Unix(), "files": m.Files, "categories": m.Categories, "preRestore": preRestore})
		}
		sort.SliceStable(out, func(i, j int) bool { return out[i]["created"].(int64) > out[j]["created"].(int64) })
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
		dest := freeName(dir, "anoshell-", now)
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
			snap = freeName(dir, "pre-restore-", now)
		}
		files, err := backup.Restore(home, abs, cats, snap, p.DryRun, now)
		if files == nil {
			files = []string{}
		}
		if _, statErr := os.Stat(snap); snap != "" && statErr != nil {
			snap = "" // refused before the snapshot was written
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

// freeName is dir/<prefix><time>.tar.gz, with -2, -3… when a backup was
// already made in that second (archives are created O_EXCL).
func freeName(dir, prefix string, now time.Time) string {
	base := filepath.Join(dir, prefix+now.Format("20060102-150405"))
	p := base + ".tar.gz"
	for i := 2; ; i++ {
		if _, err := os.Lstat(p); os.IsNotExist(err) {
			return p
		}
		p = fmt.Sprintf("%s-%d.tar.gz", base, i)
	}
}
