package downloads

import (
	"context"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

// Growing counts, with a rate; a partial that stops growing drops out after stale.
func TestStep(t *testing.T) {
	tr := &tracker{seen: map[string]seen{}, stale: 10 * time.Second}
	t0 := time.Now()
	p := "/d/a.iso.part"
	got := tr.step(map[string][2]int64{p: {100, t0.Unix()}}, t0)
	if len(got) != 1 || got[0].Name != "a.iso" || got[0].Rate != 0 {
		t.Fatalf("start: %+v", got)
	}
	got = tr.step(map[string][2]int64{p: {1100, t0.Unix()}}, t0.Add(time.Second))
	if len(got) != 1 || got[0].Rate != 500 { // (0 + 1000)/2
		t.Fatalf("growing: %+v", got)
	}
	got = tr.step(map[string][2]int64{p: {1100, t0.Unix()}}, t0.Add(12*time.Second))
	if len(got) != 0 {
		t.Fatalf("stalled past stale: %+v", got)
	}
	// abandoned before the watcher started: old mtime, never shown
	got = tr.step(map[string][2]int64{"/d/old.crdownload": {5, t0.Add(-time.Hour).Unix()}}, t0)
	if len(got) != 0 {
		t.Fatalf("abandoned: %+v", got)
	}
}

// A partial renamed to its real name becomes a finished entry.
func TestFinish(t *testing.T) {
	dir := t.TempDir()
	events := make(chan map[string]any, 16)
	w := &Watcher{Dir: dir, Notify: func(_ string, d any) { events <- d.(map[string]any) }}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go w.Run(ctx)
	time.Sleep(100 * time.Millisecond)

	part := filepath.Join(dir, "x.zip.crdownload")
	os.WriteFile(part, make([]byte, 2048), 0o644)
	wait := func(ok func(map[string]any) bool) map[string]any {
		for {
			select {
			case e := <-events:
				if ok(e) {
					return e
				}
			case <-time.After(3 * time.Second):
				t.Fatal("timed out")
			}
		}
	}
	wait(func(e map[string]any) bool { return len(e["active"].([]Active)) == 1 })
	os.Rename(part, filepath.Join(dir, "x.zip"))
	e := wait(func(e map[string]any) bool { return len(e["finished"].([]Finished)) == 1 })
	f := e["finished"].([]Finished)[0]
	if f.Name != "x.zip" || f.Size != 2048 || len(e["active"].([]Active)) != 0 {
		t.Fatalf("finished: %+v", e)
	}
}

func TestDir(t *testing.T) {
	cfg := t.TempDir()
	if got := Dir(cfg, "/home/u"); got != "/home/u/Downloads" {
		t.Fatal(got)
	}
	os.WriteFile(filepath.Join(cfg, "user-dirs.dirs"), []byte("XDG_DOWNLOAD_DIR=\"$HOME/Stuff\"\n"), 0o644)
	if got := Dir(cfg, "/home/u"); got != "/home/u/Stuff" {
		t.Fatal(got)
	}
}

// Cancelling returns promptly (closing the raw fd didn't wake a blocked read).
func TestCancel(t *testing.T) {
	w := &Watcher{Dir: t.TempDir()}
	ctx, cancel := context.WithCancel(context.Background())
	ret := make(chan error, 1)
	go func() { ret <- w.Run(ctx) }()
	time.Sleep(100 * time.Millisecond)
	cancel()
	select {
	case err := <-ret:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not return after cancel")
	}
}

// A folder that appears later is picked up, and renames in its parent (the
// fallback watch) don't count as finished downloads.
func TestLateDir(t *testing.T) {
	parent := t.TempDir()
	dir := filepath.Join(parent, "Downloads")
	var mu sync.Mutex
	var last map[string]any
	w := &Watcher{Dir: dir, Notify: func(_ string, d any) { mu.Lock(); last = d.(map[string]any); mu.Unlock() }}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go w.Run(ctx)
	time.Sleep(100 * time.Millisecond)
	os.Mkdir(dir, 0o755)
	time.Sleep(100 * time.Millisecond)
	stray := filepath.Join(parent, "y.part")
	os.WriteFile(stray, []byte("x"), 0o644)
	os.Rename(stray, filepath.Join(parent, "y"))
	part := filepath.Join(dir, "z.part")
	os.WriteFile(part, []byte("abc"), 0o644)
	os.Rename(part, filepath.Join(dir, "z"))
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		mu.Lock()
		l := last
		mu.Unlock()
		if l != nil {
			if fs := l["finished"].([]Finished); len(fs) > 0 {
				if len(fs) != 1 || fs[0].Name != "z" {
					t.Fatalf("finished: %+v", fs)
				}
				return
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatal("timed out")
}
