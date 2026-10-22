package downloads

import (
	"context"
	"os"
	"path/filepath"
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
