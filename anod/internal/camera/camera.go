// Package camera reports which processes hold a camera (a video4linux device)
// open, for the privacy indicator (spec system-integration). Most apps open
// /dev/video* directly rather than through PipeWire, so there is nothing to
// subscribe to but the device nodes: inotify reports their opens and closes,
// and only then are the holders looked up in /proc. Nothing polls.
//
// An app that only asks a device what it can do opens and closes it within a
// moment, so a new holder counts once it has held the device for Settle.
// PipeWire's own daemons are left out: an app using the camera through
// PipeWire shows up there, as a capture link (services/Privacy.qml).
package camera

import (
	"context"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

// Holder is one process with one camera open.
type Holder struct {
	PID    int    `json:"pid"`
	Name   string `json:"name"`
	Device string `json:"device"`
	Label  string `json:"label"` // the device's own name (sysfs), or its node name
}

func (h Holder) key() string { return strconv.Itoa(h.PID) + ":" + h.Device }

var ignored = map[string]bool{"pipewire": true, "wireplumber": true, "pipewire-pulse": true}

// Scan lists the processes under procDir holding a devDir/video* node open,
// skipping self and PipeWire's daemons. Processes it can't read are skipped.
func Scan(procDir, devDir, sysDir string, self int) []Holder {
	entries, err := os.ReadDir(procDir)
	if err != nil {
		return nil
	}
	prefix := filepath.Join(devDir, "video")
	var out []Holder
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil || pid == self {
			continue
		}
		fdDir := filepath.Join(procDir, e.Name(), "fd")
		fds, err := os.ReadDir(fdDir)
		if err != nil {
			continue
		}
		seen := map[string]bool{}
		for _, fd := range fds {
			target, err := os.Readlink(filepath.Join(fdDir, fd.Name()))
			if err != nil || !strings.HasPrefix(target, prefix) || seen[target] {
				continue
			}
			seen[target] = true
		}
		if len(seen) == 0 {
			continue
		}
		comm, _ := os.ReadFile(filepath.Join(procDir, e.Name(), "comm"))
		name := strings.TrimSpace(string(comm))
		if ignored[name] {
			continue
		}
		for dev := range seen {
			out = append(out, Holder{PID: pid, Name: name, Device: dev, Label: label(sysDir, dev)})
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].key() < out[j].key() })
	return out
}

func label(sysDir, dev string) string {
	b, err := os.ReadFile(filepath.Join(sysDir, filepath.Base(dev), "name"))
	if err != nil {
		return filepath.Base(dev)
	}
	return strings.Trim(strings.TrimSpace(string(b)), "'")
}

// settle keeps the holders that have held their device for at least d:
// confirmed ones stay while present, new ones wait in pending (first seen).
// It returns the confirmed holders, the updated pending set, and how long
// until the next pending one is due (0: none pending).
func settle(confirmed []Holder, pending map[string]time.Time, now []Holder, at time.Time, d time.Duration) ([]Holder, map[string]time.Time, time.Duration) {
	was := map[string]bool{}
	for _, h := range confirmed {
		was[h.key()] = true
	}
	next := map[string]time.Time{}
	var out []Holder
	var due time.Duration
	for _, h := range now {
		k := h.key()
		if was[k] {
			out = append(out, h)
			continue
		}
		first, ok := pending[k]
		if !ok {
			first = at
		}
		if at.Sub(first) >= d {
			out = append(out, h)
			continue
		}
		next[k] = first
		if left := d - at.Sub(first); due == 0 || left < due {
			due = left
		}
	}
	return out, next, due
}

// Watcher keeps the current holders and calls Notify("camera_users",
// {"holders": [...]}) when they change.
type Watcher struct {
	Proc, Dev, Sys string        // /proc, /dev, /sys/class/video4linux
	Settle         time.Duration // how long a new holder must hold on
	Notify         func(name string, data any)

	mu        sync.Mutex
	confirmed []Holder
}

// Current returns the confirmed holders.
func (w *Watcher) Current() []Holder {
	w.mu.Lock()
	defer w.mu.Unlock()
	return append([]Holder{}, w.confirmed...)
}

const deviceEvents = syscall.IN_OPEN | syscall.IN_CLOSE_WRITE | syscall.IN_CLOSE_NOWRITE

// Run watches until ctx is done.
func (w *Watcher) Run(ctx context.Context) error {
	fd, err := syscall.InotifyInit1(syscall.IN_CLOEXEC)
	if err != nil {
		return err
	}
	// Closing the descriptor ends the blocking read below.
	go func() { <-ctx.Done(); syscall.Close(fd) }()

	// Device nodes come and go (USB cameras): /dev itself is watched for
	// video* nodes appearing or leaving, and each node for opens/closes.
	syscall.InotifyAddWatch(fd, w.Dev, syscall.IN_CREATE|syscall.IN_DELETE)
	watchDevices := func() {
		nodes, _ := filepath.Glob(filepath.Join(w.Dev, "video*"))
		for _, n := range nodes {
			syscall.InotifyAddWatch(fd, n, deviceEvents) // re-adding updates in place
		}
	}
	watchDevices()

	kick := make(chan struct{}, 1)
	go w.loop(ctx, kick)
	kick <- struct{}{} // the state at start

	buf := make([]byte, 64*(syscall.SizeofInotifyEvent+syscall.NAME_MAX+1))
	for {
		n, err := syscall.Read(fd, buf)
		if err != nil || n <= 0 {
			if ctx.Err() != nil {
				return nil
			}
			if err == syscall.EINTR {
				continue
			}
			return err
		}
		rewatch := false
		for off := 0; off+syscall.SizeofInotifyEvent <= n; {
			ev := (*syscall.InotifyEvent)(unsafe.Pointer(&buf[off]))
			name := strings.TrimRight(string(buf[off+syscall.SizeofInotifyEvent:off+syscall.SizeofInotifyEvent+int(ev.Len)]), "\x00")
			if ev.Mask&syscall.IN_CREATE != 0 && strings.HasPrefix(name, "video") {
				rewatch = true
			}
			off += syscall.SizeofInotifyEvent + int(ev.Len)
		}
		if rewatch {
			watchDevices()
		}
		select {
		case kick <- struct{}{}:
		default:
		}
	}
}

// loop rescans shortly after device activity (coalesced) and again when a
// pending holder is due.
func (w *Watcher) loop(ctx context.Context, kick <-chan struct{}) {
	pending := map[string]time.Time{}
	timer := time.NewTimer(time.Hour)
	timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-kick:
			timer.Reset(250 * time.Millisecond)
			continue
		case <-timer.C:
		}
		now := Scan(w.Proc, w.Dev, w.Sys, os.Getpid())
		w.mu.Lock()
		prev := w.confirmed
		var due time.Duration
		w.confirmed, pending, due = settle(prev, pending, now, time.Now(), w.Settle)
		changed := !same(prev, w.confirmed)
		cur := append([]Holder{}, w.confirmed...)
		w.mu.Unlock()
		if due > 0 {
			timer.Reset(due)
		}
		if changed && w.Notify != nil {
			w.Notify("camera_users", map[string]any{"holders": cur})
		}
	}
}

func same(a, b []Holder) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
