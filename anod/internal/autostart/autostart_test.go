package autostart

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestParse(t *testing.T) {
	var v any
	d := json.NewDecoder(strings.NewReader(`[
		{"desktopId": "firefox.desktop", "delayMs": 1500},
		{"command": "  waybar -c x ", "enabled": false},
		{"desktopId": "kitty", "command": "ignored"},
		{"enabled": true},
		"junk",
		{"command": "a", "delayMs": -5},
		{"command": "b", "delayMs": 99999999}
	]`))
	d.UseNumber()
	if err := d.Decode(&v); err != nil {
		t.Fatal(err)
	}
	got := Parse(v)
	want := []Entry{
		{DesktopID: "firefox", Enabled: true, DelayMs: 1500},
		{Command: "waybar -c x", Enabled: false},
		{DesktopID: "kitty", Enabled: true},
		{Command: "a", Enabled: true},
		{Command: "b", Enabled: true, DelayMs: MaxDelay},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %+v\nwant %+v", got, want)
	}
	if Parse(nil) != nil || Parse("x") != nil {
		t.Fatal("non-lists parse to nothing")
	}
}

func TestExecArgv(t *testing.T) {
	cases := map[string][]string{
		`firefox %u`:                       {"firefox"},
		`env FOO=1 app --x=%f "a b" 100%%`: {"env", "FOO=1", "app", "--x=", "a b", "100%"},
		`"/opt/My App/run" "say \"hi\""`:   {"/opt/My App/run", `say "hi"`},
		`  spaced   out  `:                 {"spaced", "out"},
		`code --open-url %U --icon %i`:     {"code", "--open-url", "--icon"},
	}
	for in, want := range cases {
		got, err := ExecArgv(in)
		if err != nil || !reflect.DeepEqual(got, want) {
			t.Errorf("ExecArgv(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	for _, bad := range []string{``, `%U`, `"open`} {
		if _, err := ExecArgv(bad); err == nil {
			t.Errorf("ExecArgv(%q): want an error", bad)
		}
	}
}

func TestResolve(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "app.desktop"), []byte("[Desktop Entry]\nName=App\nExec=app --start %F\n[Desktop Action x]\nExec=other\n"), 0o644)
	os.WriteFile(filepath.Join(dir, "tui.desktop"), []byte("[Desktop Entry]\nName=Tui\nExec=htop\nTerminal=true\n"), 0o644)

	argv, name, err := Resolve(Entry{DesktopID: "app"}, []string{"/nonexistent", dir})
	if err != nil || name != "App" || !reflect.DeepEqual(argv, []string{"app", "--start"}) {
		t.Fatalf("app: %q %q %v", argv, name, err)
	}
	argv, _, _ = Resolve(Entry{DesktopID: "tui"}, []string{dir})
	if !reflect.DeepEqual(argv, []string{"ano", "run", "terminal", "-e", "htop"}) {
		t.Fatalf("terminal entry: %q", argv)
	}
	argv, _, _ = Resolve(Entry{Command: "a | b"}, nil)
	if !reflect.DeepEqual(argv, []string{"sh", "-c", "a | b"}) {
		t.Fatalf("command: %q", argv)
	}
	for _, id := range []string{"../etc/passwd", "a/b", "missing"} {
		if _, _, err := Resolve(Entry{DesktopID: id}, []string{dir}); err == nil {
			t.Errorf("Resolve(%q): want an error", id)
		}
	}
}

func TestMarkerOncePerSession(t *testing.T) {
	m := Marker{Path: filepath.Join(t.TempDir(), "ano", "autostart.session")}
	if ok, err := m.Claim("s1"); !ok || err != nil {
		t.Fatalf("first claim: %v %v", ok, err)
	}
	if ok, _ := m.Claim("s1"); ok {
		t.Fatal("an anod restart in the same session must not launch again")
	}
	if ok, _ := m.Claim("s2"); !ok {
		t.Fatal("a new session launches again")
	}
	if ok, _ := m.Claim(""); ok {
		t.Fatal("no session, no launch")
	}
}

func TestRunAll(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "app.desktop"), []byte("[Desktop Entry]\nExec=app\n"), 0o644)
	var mu sync.Mutex
	var started [][]string
	l := &Launcher{Dirs: []string{dir}, Start: func(argv []string, newSession bool) error {
		mu.Lock()
		started = append(started, argv)
		mu.Unlock()
		return nil
	}}
	l.once.Do(func() {}) // no systemd probe in tests: plain argv
	n := l.RunAll([]Entry{
		{DesktopID: "app", Enabled: true},
		{Command: "off", Enabled: false},
		{Command: "later", Enabled: true, DelayMs: 20},
		{DesktopID: "missing", Enabled: true},
	})
	if n != 3 {
		t.Fatalf("scheduled %d, want 3", n)
	}
	time.Sleep(100 * time.Millisecond)
	mu.Lock()
	defer mu.Unlock()
	want := [][]string{{"app"}, {"sh", "-c", "later"}}
	if !reflect.DeepEqual(started, want) {
		t.Fatalf("started %q, want %q", started, want)
	}
	if st := l.StatusOf(Entry{DesktopID: "missing"}); st.At.IsZero() || st.Error == "" {
		t.Fatalf("missing entry status: %+v", st)
	}
	if st := l.StatusOf(Entry{Command: "off"}); !st.At.IsZero() {
		t.Fatal("a disabled entry is not launched")
	}
}

func TestWrap(t *testing.T) {
	if got := Wrap([]string{"x"}, "x", false); !reflect.DeepEqual(got, []string{"x"}) {
		t.Fatal(got)
	}
	got := Wrap([]string{"x", "y"}, "my app/../z", true)
	if got[0] != "systemd-run" || got[len(got)-3] != "--" || !strings.HasPrefix(got[6], "--unit=app-anoshell-autostart-z-") {
		t.Fatalf("%q", got)
	}
}
