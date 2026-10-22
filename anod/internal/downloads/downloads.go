// Package downloads reports the downloads browsers are writing into the
// download folder (spec system-integration, after Bioma's scripts/downloads):
// partial files, Firefox's `.part` and Chromium's `.crdownload`, with the
// bytes so far and the bytes a second. Browsers keep the total to
// themselves, so there's no fraction. A partial counts while it grows; one
// that hasn't grown for Stale (an abandoned download) drops out.
//
// A download finishes when its partial is renamed to the real name (both
// browsers do that); the renamed file becomes a finished entry. The folder is
// watched with inotify; only while something grows is it looked at every
// second, so a stalled download slows to nothing instead of freezing.
package downloads

import (
	"bufio"
	"context"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var suffixes = []string{".part", ".crdownload"}

func partialName(name string) (string, bool) {
	for _, s := range suffixes {
		if strings.HasSuffix(name, s) && len(name) > len(s) {
			return strings.TrimSuffix(name, s), true
		}
	}
	return "", false
}

// Active is a download in progress.
type Active struct {
	Path string  `json:"path"`
	Name string  `json:"name"`
	Size int64   `json:"size"`
	Rate float64 `json:"rate"` // bytes a second, smoothed
}

// Finished is a download that completed while anod watched.
type Finished struct {
	Path string `json:"path"`
	Name string `json:"name"`
	Size int64  `json:"size"`
	At   int64  `json:"at"` // unix seconds
}

type seen struct {
	size  int64
	when  time.Time // monotonic, when last looked at
	rate  float64
	grown time.Time // wall clock, when it last grew
}

// tracker is the state, apart from the filesystem, so it can be tested.
type tracker struct {
	seen  map[string]seen
	stale time.Duration
}

// step takes the partials now on disk (path → size, mtime) and returns the
// growing ones.
func (t *tracker) step(files map[string][2]int64, now time.Time) []Active {
	cur := map[string]seen{}
	var out []Active
	for path, f := range files {
		size, mtime := f[0], time.Unix(f[1], 0)
		s, ok := t.seen[path]
		if !ok {
			s = seen{size: size, when: now, grown: mtime}
		} else {
			el := now.Sub(s.when).Seconds()
			inst := s.rate
			if el > 0 {
				inst = float64(max(0, size-s.size)) / el
			}
			// smoothed, so a burst and a pause read as the speed between them
			s.rate = s.rate*0.5 + inst*0.5
			if size > s.size {
				s.grown = now
			}
			s.size, s.when = size, now
		}
		cur[path] = s
		if now.Sub(s.grown) < t.stale {
			name, _ := partialName(filepath.Base(path))
			out = append(out, Active{Path: path, Name: name, Size: size, Rate: float64(int64(s.rate))})
		}
	}
	t.seen = cur
	sort.Slice(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out
}

// Watcher keeps the state and calls Notify("downloads", State()) on changes.
type Watcher struct {
	Dir    string
	Stale  time.Duration // default 60 s
	Keep   int           // finished entries kept, default 5
	Notify func(name string, data any)

	mu       sync.Mutex
	active   []Active
	finished []Finished
}

// State is what the event and downloads.list carry.
func (w *Watcher) State() map[string]any {
	w.mu.Lock()
	defer w.mu.Unlock()
	return map[string]any{"dir": w.Dir, "active": append([]Active{}, w.active...), "finished": append([]Finished{}, w.finished...)}
}

// Clear forgets the finished entries (path "" = all).
func (w *Watcher) Clear(path string) {
	w.mu.Lock()
	var keep []Finished
	for _, f := range w.finished {
		if path != "" && f.Path != path {
			keep = append(keep, f)
		}
	}
	w.finished = keep
	w.mu.Unlock()
	w.notify()
}

func (w *Watcher) notify() {
	if w.Notify != nil {
		w.Notify("downloads", w.State())
	}
}

func (w *Watcher) finish(path string) {
	fi, err := os.Stat(path)
	if err != nil || fi.IsDir() {
		return
	}
	w.mu.Lock()
	keep := max(1, w.Keep)
	f := Finished{Path: path, Name: filepath.Base(path), Size: fi.Size(), At: time.Now().Unix()}
	w.finished = append([]Finished{f}, w.finished...)
	if len(w.finished) > keep {
		w.finished = w.finished[:keep]
	}
	w.mu.Unlock()
}

func scan(dir string) map[string][2]int64 {
	out := map[string][2]int64{}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return out
	}
	for _, e := range entries {
		if _, ok := partialName(e.Name()); !ok {
			continue
		}
		fi, err := e.Info()
		if err != nil || fi.IsDir() {
			continue
		}
		out[filepath.Join(dir, e.Name())] = [2]int64{fi.Size(), fi.ModTime().Unix()}
	}
	return out
}

const dirEvents = syscall.IN_MODIFY | syscall.IN_CREATE | syscall.IN_DELETE | syscall.IN_MOVED_FROM | syscall.IN_MOVED_TO

// Run watches until ctx is done.
func (w *Watcher) Run(ctx context.Context) error {
	if w.Stale == 0 {
		w.Stale = time.Minute
	}
	fd, err := syscall.InotifyInit1(syscall.IN_CLOEXEC)
	if err != nil {
		return err
	}
	go func() { <-ctx.Done(); syscall.Close(fd) }()

	// A folder that isn't there yet: watch the one it would appear in.
	watched := false
	watch := func() {
		if _, err := syscall.InotifyAddWatch(fd, w.Dir, dirEvents); err == nil {
			watched = true
		} else {
			syscall.InotifyAddWatch(fd, filepath.Dir(w.Dir), syscall.IN_CREATE|syscall.IN_MOVED_TO)
		}
	}
	watch()

	kick := make(chan struct{}, 1)
	done := make(chan string, 8) // finished paths
	go w.loop(ctx, kick, done)
	kick <- struct{}{}

	from := map[uint32]bool{} // rename cookie → a partial left
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
		for off := 0; off+syscall.SizeofInotifyEvent <= n; {
			ev := (*syscall.InotifyEvent)(unsafe.Pointer(&buf[off]))
			name := strings.TrimRight(string(buf[off+syscall.SizeofInotifyEvent:off+syscall.SizeofInotifyEvent+int(ev.Len)]), "\x00")
			off += syscall.SizeofInotifyEvent + int(ev.Len)
			if !watched {
				if name == filepath.Base(w.Dir) {
					watch()
				}
				continue
			}
			_, partial := partialName(name)
			switch {
			case ev.Mask&syscall.IN_MOVED_FROM != 0 && partial:
				from[ev.Cookie] = true
			case ev.Mask&syscall.IN_MOVED_TO != 0 && !partial && from[ev.Cookie]:
				delete(from, ev.Cookie)
				done <- filepath.Join(w.Dir, name)
			}
		}
		if len(from) > 64 { // pairs that never completed
			from = map[uint32]bool{}
		}
		select {
		case kick <- struct{}{}:
		default:
		}
	}
}

func (w *Watcher) loop(ctx context.Context, kick <-chan struct{}, done <-chan string) {
	t := &tracker{seen: map[string]seen{}, stale: w.Stale}
	tick := time.NewTicker(time.Second)
	defer tick.Stop()
	var last []Active
	for {
		finished := false
		select {
		case <-ctx.Done():
			return
		case p := <-done:
			w.finish(p)
			finished = true
		case <-kick:
		case <-tick.C:
			if len(last) == 0 { // only while something grows
				continue
			}
		}
		cur := t.step(scan(w.Dir), time.Now())
		if finished || !same(last, cur) {
			w.mu.Lock()
			w.active = cur
			w.mu.Unlock()
			w.notify()
		}
		last = cur
	}
}

func same(a, b []Active) bool {
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

// Dir is the user's download folder: XDG_DOWNLOAD_DIR in
// $XDG_CONFIG_HOME/user-dirs.dirs, else ~/Downloads.
func Dir(configHome, home string) string {
	if f, err := os.Open(filepath.Join(configHome, "user-dirs.dirs")); err == nil {
		defer f.Close()
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			k, v, ok := strings.Cut(strings.TrimSpace(sc.Text()), "=")
			if !ok || k != "XDG_DOWNLOAD_DIR" {
				continue
			}
			v = strings.ReplaceAll(strings.Trim(v, `"`), "$HOME", home)
			if v != "" && v != home && filepath.IsAbs(v) {
				return v
			}
		}
	}
	return filepath.Join(home, "Downloads")
}
