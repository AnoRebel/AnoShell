package ipc

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func startServer(t *testing.T) (*Server, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "ano", "anod.sock")
	s := NewServer(path)
	s.Handle("ping", func(json.RawMessage) (any, error) { return "pong", nil })
	s.Handle("boom", func(json.RawMessage) (any, error) { return nil, errors.New("kaput") })
	if err := s.Listen(); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { s.Serve(ctx); close(done) }()
	t.Cleanup(func() { cancel(); <-done })
	return s, path
}

func TestPermissions(t *testing.T) {
	_, path := startServer(t)
	fi, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := fi.Mode().Perm(); got != 0o600 {
		t.Errorf("socket mode = %o, want 600", got)
	}
	di, _ := os.Stat(filepath.Dir(path))
	if got := di.Mode().Perm(); got != 0o700 {
		t.Errorf("dir mode = %o, want 700", got)
	}
}

func TestLoosePreexistingDirIsTightened(t *testing.T) {
	dir := filepath.Join(t.TempDir(), "ano")
	os.MkdirAll(dir, 0o755)
	os.Chmod(dir, 0o755)
	s := NewServer(filepath.Join(dir, "anod.sock"))
	if err := s.Listen(); err != nil {
		t.Fatal(err)
	}
	defer s.ln.Close()
	di, _ := os.Stat(dir)
	if got := di.Mode().Perm(); got != 0o700 {
		t.Errorf("dir mode = %o, want 700", got)
	}
}

func TestCallAndErrors(t *testing.T) {
	_, path := startServer(t)
	res, err := Call(path, "ping", nil)
	if err != nil || string(res) != `"pong"` {
		t.Fatalf("ping = %s, %v", res, err)
	}
	_, err = Call(path, "nope", nil)
	var e *Error
	if !errors.As(err, &e) || e.Code != CodeMethod {
		t.Errorf("unknown method error = %v", err)
	}
	_, err = Call(path, "boom", nil)
	if !errors.As(err, &e) || e.Code != CodeFailed || e.Message != "kaput" {
		t.Errorf("handler error = %v", err)
	}
}

func rawLine(t *testing.T, path, line string) map[string]any {
	t.Helper()
	c, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(3 * time.Second))
	c.Write([]byte(line + "\n"))
	r := bufio.NewScanner(c)
	if !r.Scan() {
		t.Fatal("no reply")
	}
	var m map[string]any
	json.Unmarshal(r.Bytes(), &m)
	return m
}

func TestVersionMismatch(t *testing.T) {
	_, path := startServer(t)
	for _, line := range []string{
		`{"v":99,"id":1,"method":"ping"}`,
		`{"id":2,"method":"ping"}`, // no version at all
	} {
		m := rawLine(t, path, line)
		e, _ := m["error"].(map[string]any)
		if e["code"] != CodeVersion || !strings.Contains(e["message"].(string), "API v1") {
			t.Errorf("%s -> %v", line, m)
		}
	}
	// The server keeps serving after a mismatch.
	if _, err := Call(path, "ping", nil); err != nil {
		t.Fatal(err)
	}
}

func TestBadJSON(t *testing.T) {
	_, path := startServer(t)
	m := rawLine(t, path, `{nope`)
	if e, _ := m["error"].(map[string]any); e["code"] != CodeBadInput {
		t.Errorf("got %v", m)
	}
}

func TestSubscribeBroadcast(t *testing.T) {
	s, path := startServer(t)
	c, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(3 * time.Second))
	c.Write([]byte(`{"v":1,"id":1,"method":"subscribe","params":{"events":["a"]}}` + "\n"))
	r := bufio.NewScanner(c)
	r.Scan()              // subscribe ack
	s.Broadcast("b", nil) // not subscribed: must not arrive
	s.Broadcast("a", map[string]string{"k": "v"})
	if !r.Scan() {
		t.Fatal("no event")
	}
	if got := r.Text(); got != `{"event":"a","data":{"k":"v"}}` {
		t.Errorf("event = %s", got)
	}
}

func TestRefusesSecondInstanceAndClearsStale(t *testing.T) {
	_, path := startServer(t)
	if err := NewServer(path).Listen(); err == nil || !strings.Contains(err.Error(), "already running") {
		t.Errorf("second Listen = %v", err)
	}
	// A leftover socket file with nobody listening is replaced.
	stale := filepath.Join(t.TempDir(), "ano", "anod.sock")
	os.MkdirAll(filepath.Dir(stale), 0o700)
	l, _ := net.Listen("unix", stale)
	l.(*net.UnixListener).SetUnlinkOnClose(false)
	l.Close()
	s := NewServer(stale)
	if err := s.Listen(); err != nil {
		t.Fatalf("stale socket not replaced: %v", err)
	}
	s.ln.Close()
}

// A slow method doesn't hold up later requests on the same connection.
func TestSlowMethodDoesNotBlockConnection(t *testing.T) {
	path := filepath.Join(t.TempDir(), "ano", "anod.sock")
	s := NewServer(path)
	release := make(chan struct{})
	s.HandleSlow("scan", func(json.RawMessage) (any, error) { <-release; return "scanned", nil })
	s.Handle("ping", func(json.RawMessage) (any, error) { return "pong", nil })
	if err := s.Listen(); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { s.Serve(ctx); close(done) }()
	defer func() { cancel(); <-done }()

	c, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(3 * time.Second))
	c.Write([]byte(`{"v":1,"id":1,"method":"scan"}` + "\n" + `{"v":1,"id":2,"method":"ping"}` + "\n"))
	r := bufio.NewScanner(c)
	var got []string
	for i := 0; i < 2 && r.Scan(); i++ {
		got = append(got, r.Text())
		if i == 0 {
			close(release)
		}
	}
	if len(got) != 2 || !strings.Contains(got[0], `"id":2`) || !strings.Contains(got[1], `"scanned"`) {
		t.Fatalf("replies = %q, want ping (id 2) first, then the scan", got)
	}
}

func TestCallNotRunning(t *testing.T) {
	_, err := Call(filepath.Join(t.TempDir(), "none.sock"), "status", nil)
	if !errors.Is(err, ErrNotRunning) {
		t.Fatalf("Call on a missing socket = %v, want ErrNotRunning", err)
	}
}
