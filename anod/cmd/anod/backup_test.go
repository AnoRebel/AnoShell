package main

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"ano/anod/internal/ipc"
)

// Settings → Backup over the socket: create, list, a dry-run preview, a
// restore of one category that leaves the others alone, and no archive from
// outside the backup folder.
func TestBackupMethods(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(home, ".local/share"))
	write := func(rel, s string) {
		p := filepath.Join(home, rel)
		os.MkdirAll(filepath.Dir(p), 0o755)
		if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	read := func(rel string) string { b, _ := os.ReadFile(filepath.Join(home, rel)); return string(b) }
	write(".config/anoshell/config.json", `{"a":1}`)
	write(".config/anoshell/themes/t.json", `theme-1`)

	sock := filepath.Join(t.TempDir(), "s")
	srv := ipc.NewServer(sock)
	registerBackup(srv)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	if err := srv.Listen(); err != nil {
		t.Fatal(err)
	}
	go srv.Serve(ctx)
	call := func(method string, params any, out any) {
		raw, err := ipc.Call(sock, method, params)
		if err != nil {
			t.Fatalf("%s: %v", method, err)
		}
		if out != nil {
			json.Unmarshal(raw, out)
		}
	}

	var made struct {
		Path       string
		Files      int
		Categories []string
	}
	call("backup.create", map[string]any{"only": []string{"config", "themes"}}, &made)
	if made.Files != 2 || len(made.Categories) != 2 {
		t.Fatalf("create: %+v", made)
	}
	var list []struct{ Path string }
	call("backup.list", nil, &list)
	if len(list) != 1 || list[0].Path != made.Path {
		t.Fatalf("list: %+v", list)
	}

	write(".config/anoshell/config.json", `{"a":2}`)
	write(".config/anoshell/themes/t.json", `theme-2`)
	var res struct {
		Files    []string
		Snapshot string
		Error    string
	}
	call("backup.restore", map[string]any{"path": made.Path, "only": []string{"themes"}, "dryRun": true}, &res)
	if len(res.Files) != 1 || res.Files[0] != ".config/anoshell/themes/t.json" || read(".config/anoshell/themes/t.json") != "theme-2" {
		t.Fatalf("dry run: %+v", res)
	}
	call("backup.restore", map[string]any{"path": made.Path, "only": []string{"themes"}}, &res)
	if read(".config/anoshell/themes/t.json") != "theme-1" || read(".config/anoshell/config.json") != `{"a":2}` || res.Snapshot == "" {
		t.Fatalf("restore themes only: %+v, config %q", res, read(".config/anoshell/config.json"))
	}
	if _, err := ipc.Call(sock, "backup.restore", map[string]any{"path": filepath.Join(home, "x.tar.gz")}); err == nil {
		t.Fatal("an archive outside the backup folder was accepted")
	}
}
