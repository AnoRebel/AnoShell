package palette

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func fake(t *testing.T, dir, name, body string) {
	t.Helper()
	os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755)
}

func TestScanCachesAndWarmScanRunsNothing(t *testing.T) {
	bin, pics := t.TempDir(), t.TempDir()
	t.Setenv("PATH", bin)
	// nice just execs the rest; matugen prints a source colour; ffmpeg prints a flat grey map.
	fake(t, bin, "nice", `shift 2; exec "$@"`)
	fake(t, bin, "matugen", `printf '{"colors":{"source_color":{"default":{"color":"#ff0000"}}}}'`)
	fake(t, bin, "ffmpeg", `case "$*" in *rawvideo*) /usr/bin/head -c 160 /dev/zero | /usr/bin/tr '\0' '\200';; *) : > "$(eval echo \${$#})";; esac`)
	for _, n := range []string{"a.png", "b.jpg", "clip.mp4", "notes.txt"} {
		os.WriteFile(filepath.Join(pics, n), []byte("x"), 0o644)
	}
	c := &Cache{Path: filepath.Join(t.TempDir(), "palette.json"), StillDir: t.TempDir()}
	got, err := c.Scan(context.Background(), pics)
	if err != nil || len(got) != 3 {
		t.Fatalf("scan: %v %d", err, len(got))
	}
	for _, e := range got {
		if e.Source != "#ff0000" || e.Hue != 0 || e.Luminance < 0.49 || e.Luminance > 0.51 {
			t.Fatalf("entry %+v", e)
		}
		if strings.HasSuffix(e.Path, ".mp4") && (e.Still == "" || !e.Video) {
			t.Fatalf("video entry %+v", e)
		}
	}
	// A fresh cache object (new anod) reading the file: a warm scan spawns nothing.
	c2 := &Cache{Path: c.Path, StillDir: c.StillDir}
	if _, err := c2.Scan(context.Background(), pics); err != nil || c2.Spawned != 0 {
		t.Fatalf("warm scan spawned %d (%v)", c2.Spawned, err)
	}
	// Get on a cached file runs nothing.
	before := c2.Spawned
	if e, err := c2.Get(context.Background(), filepath.Join(pics, "a.png")); err != nil || e.Source != "#ff0000" || c2.Spawned != before {
		t.Fatalf("get: %+v %v spawned %d", e, err, c2.Spawned-before)
	}
	// A changed file is recomputed, a removed one dropped.
	os.WriteFile(filepath.Join(pics, "a.png"), []byte("changed"), 0o644)
	os.Remove(filepath.Join(pics, "b.jpg"))
	got, _ = c2.Scan(context.Background(), pics)
	if len(got) != 2 || c2.Spawned == 0 {
		t.Fatalf("rescan: %d entries, spawned %d", len(got), c2.Spawned)
	}
}

func TestHue(t *testing.T) {
	for hex, want := range map[string]float64{"#ff0000": 0, "#00ff00": 120, "#0000ff": 240, "bad": -1} {
		if h := Hue(hex); h != want {
			t.Errorf("Hue(%s) = %v", hex, h)
		}
	}
}
