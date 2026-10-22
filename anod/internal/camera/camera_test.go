package camera

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

// A fake /proc, /dev and sysfs: pid 10 (zoom) holds video0, pid 11
// (pipewire) holds video0, pid 12 holds an unrelated file.
func TestScan(t *testing.T) {
	root := t.TempDir()
	proc, dev, sys := filepath.Join(root, "proc"), filepath.Join(root, "dev"), filepath.Join(root, "sys")
	os.MkdirAll(dev, 0o755)
	os.WriteFile(filepath.Join(dev, "video0"), nil, 0o644)
	os.MkdirAll(filepath.Join(sys, "video0"), 0o755)
	os.WriteFile(filepath.Join(sys, "video0", "name"), []byte("Integrated Camera\n"), 0o644)
	proc0 := func(pid, comm string, fds map[string]string) {
		d := filepath.Join(proc, pid)
		os.MkdirAll(filepath.Join(d, "fd"), 0o755)
		os.WriteFile(filepath.Join(d, "comm"), []byte(comm+"\n"), 0o644)
		for fd, target := range fds {
			os.Symlink(target, filepath.Join(d, "fd", fd))
		}
	}
	cam := filepath.Join(dev, "video0")
	proc0("10", "zoom", map[string]string{"3": cam, "4": cam})
	proc0("11", "pipewire", map[string]string{"3": cam})
	proc0("12", "vim", map[string]string{"3": "/etc/passwd"})
	proc0("13", "self", map[string]string{"3": cam})

	got := Scan(proc, dev, sys, 13)
	if len(got) != 1 || got[0].PID != 10 || got[0].Name != "zoom" || got[0].Device != cam || got[0].Label != "Integrated Camera" {
		t.Fatalf("Scan = %+v", got)
	}
}

func TestSettle(t *testing.T) {
	h := Holder{PID: 1, Name: "app", Device: "/dev/video0"}
	t0 := time.Unix(1000, 0)
	d := 1500 * time.Millisecond

	conf, pend, due := settle(nil, map[string]time.Time{}, []Holder{h}, t0, d)
	if len(conf) != 0 || len(pend) != 1 || due != d {
		t.Fatalf("new holder must wait: %v %v %v", conf, pend, due)
	}
	// A quick probe: gone before it was due, never confirmed.
	conf, pend, _ = settle(conf, pend, nil, t0.Add(300*time.Millisecond), d)
	if len(conf) != 0 || len(pend) != 0 {
		t.Fatalf("probe must vanish: %v %v", conf, pend)
	}
	// Held long enough: confirmed, then dropped as soon as it closes.
	_, pend, _ = settle(nil, map[string]time.Time{}, []Holder{h}, t0, d)
	conf, pend, due = settle(nil, pend, []Holder{h}, t0.Add(d), d)
	if len(conf) != 1 || len(pend) != 0 || due != 0 {
		t.Fatalf("held holder must be confirmed: %v %v %v", conf, pend, due)
	}
	if conf, _, _ = settle(conf, pend, nil, t0.Add(2*d), d); len(conf) != 0 {
		t.Fatalf("closed holder must go: %v", conf)
	}
}
