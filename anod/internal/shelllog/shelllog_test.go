package shelllog

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const sample = `2026-11-10 02:04:02.962  WARN: GlobalShortcut will not work.
2026-11-10 02:04:03.017  WARN quickshell.io.socket: Socket error
2026-11-10 02:04:06.021  WARN scene: @modules/bar/Bar.qml[12:5]: TypeError: Cannot read property 'x' of null
2026-11-10 02:04:07.000  INFO qml: [Pieces] loaded
2026-11-10 02:04:08.000 ERROR qml: [NiriKeybinds] Failed to read config
  at line 3
2026-11-10 02:04:09.000  WARN scene: @modules/bar/Bar.qml[12:5]: TypeError: Cannot read property 'x' of null
2026-11-10 02:04:10.000  WARN qt.qml.typeresolution: Cannot resolve Foo
`

func TestParse(t *testing.T) {
	r := Parse(strings.NewReader(sample))
	if r.Total != 4 || r.Errors != 1 || len(r.Entries) != 3 {
		t.Fatalf("%+v", r)
	}
	if e := r.Entries[1]; e.Category != "scene" || e.Count != 2 || e.First != "2026-11-10 02:04:06.021" || e.Last != "2026-11-10 02:04:09.000" {
		t.Fatalf("dedup: %+v", e)
	}
	if e := r.Entries[0]; e.Level != "ERROR" || e.Message != "[NiriKeybinds] Failed to read config\n  at line 3" {
		t.Fatalf("continuation: %+v", e)
	}
	var b strings.Builder
	for i := range MaxEntries + 5 {
		fmt.Fprintf(&b, "2026-11-10 02:04:06.021  WARN qml: message %d\n", i)
	}
	r = Parse(strings.NewReader(b.String()))
	if len(r.Entries) != MaxEntries || r.Dropped != 5 || r.Entries[MaxEntries-1].Message != fmt.Sprintf("message %d", MaxEntries+4) {
		t.Fatalf("cap: %d %d", len(r.Entries), r.Dropped)
	}
}

func TestIsShellAndFind(t *testing.T) {
	t.Setenv("ANO_SHELL_DIR", "/home/u/.config/quickshell/ano")
	for argv, want := range map[string]bool{
		"qs -c ano":                                            true,
		"/usr/bin/qs --config=ano -d":                          true,
		"qs -p /home/u/.config/quickshell/ano":                 true,
		"qs -n -p /home/u/.config/quickshell/ano/settings.qml": false,
		"qs -c other":                                          false,
		"vim -c ano":                                           false,
	} {
		if IsShell(strings.Fields(argv)) != want {
			t.Errorf("%s: want %v", argv, want)
		}
	}
	rt := t.TempDir()
	t.Setenv("XDG_RUNTIME_DIR", rt)
	cmd := map[int]string{10: "qs -n -p /home/u/.config/quickshell/ano/settings.qml", 11: "qs -c ano", 12: "qs -c other"}
	Cmdline = func(pid int) []string { return strings.Fields(cmd[pid]) }
	for pid := range cmd {
		d := filepath.Join(rt, "quickshell/by-pid", fmt.Sprint(pid))
		os.MkdirAll(d, 0o755)
		os.WriteFile(filepath.Join(d, "log.log"), []byte(sample), 0o644)
	}
	// Settings' own process isn't the shell: the running shell's log is found.
	if _, p, err := Find(10); err != nil || p != 11 {
		t.Fatalf("find from settings: %d %v", p, err)
	}
	r, err := Errors(11)
	if err != nil || r.PID != 11 || len(r.Entries) != 3 {
		t.Fatalf("errors: %+v %v", r, err)
	}
	delete(cmd, 11)
	if _, _, err := Find(10); err == nil {
		t.Fatal("found a log without a running shell")
	}
}
