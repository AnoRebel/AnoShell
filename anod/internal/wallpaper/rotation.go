package wallpaper

import (
	"context"
	"encoding/json"
	"math/rand/v2"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// RotationSettings come from background.randomize.
type RotationSettings struct {
	Enable   bool
	Dir      string
	Interval time.Duration
}

// Bag deals every image in a folder once, in random order, before any repeats;
// what's left is persisted, so a restart doesn't start over.
type Bag struct {
	Path      string   // state file
	Dir       string   `json:"dir"`
	Remaining []string `json:"remaining"`
}

// LoadBag reads the bag for dir (a fresh one when the dir changed).
func LoadBag(path, dir string) *Bag {
	b := &Bag{Path: path}
	if data, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(data, b)
	}
	if b.Dir != dir {
		b.Dir, b.Remaining = dir, nil
	}
	return b
}

// Next returns the next image, refilling (reshuffled) when empty. Images that
// disappeared are skipped; avoid is not dealt first after a refill (no instant
// repeat across the boundary). "" when the folder has no images.
func (b *Bag) Next(avoid string) string {
	for range 2 {
		for len(b.Remaining) > 0 {
			img := b.Remaining[0]
			b.Remaining = b.Remaining[1:]
			if fi, err := os.Stat(img); err == nil && !fi.IsDir() {
				b.save()
				return img
			}
		}
		all := ListImages(b.Dir)
		if len(all) == 0 {
			b.save()
			return ""
		}
		rand.Shuffle(len(all), func(i, j int) { all[i], all[j] = all[j], all[i] })
		if len(all) > 1 && all[0] == avoid {
			all[0], all[len(all)-1] = all[len(all)-1], all[0]
		}
		b.Remaining = all
	}
	return ""
}

func (b *Bag) save() {
	data, _ := json.Marshal(b)
	_ = writeAtomic(b.Path, data)
}

// ListImages returns the images under dir (recursive), sorted.
func ListImages(dir string) []string {
	var out []string
	_ = filepath.WalkDir(expandHome(dir), func(p string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() && IsImage(p) {
			out = append(out, p)
		}
		return nil
	})
	sort.Strings(out)
	return out
}

// Outputs lists awww's outputs ("" entries never); nil when awww can't say.
func Outputs(ctx context.Context) []string {
	out, err := exec.CommandContext(ctx, "awww", "query").Output()
	if err != nil {
		return nil
	}
	var names []string
	for line := range strings.SplitSeq(string(out), "\n") {
		// ": eDP-1: 1920x1200, scale: 1.5, currently displaying: image: …"
		f := strings.Fields(strings.TrimPrefix(strings.TrimSpace(line), ":"))
		if len(f) > 0 {
			if n := strings.TrimSuffix(f[0], ":"); n != "" {
				names = append(names, n)
			}
		}
	}
	return names
}

// Rotator changes the wallpaper on a timer: a different image per output,
// colours once per cycle (from the first output's image).
type Rotator struct {
	Pipeline *Pipeline
	BagPath  string
	Settings func() (RotationSettings, Settings)
	OnApply  func(Result)

	mu   sync.Mutex
	kick chan struct{}
	last string
}

// Next advances now (also restarts the interval).
func (r *Rotator) Next() {
	r.mu.Lock()
	if r.kick == nil {
		r.kick = make(chan struct{}, 1)
	}
	k := r.kick
	r.mu.Unlock()
	select {
	case k <- struct{}{}:
	default:
	}
}

// Run loops until ctx ends. Settings are re-read every tick, so enabling,
// disabling or changing the folder/interval applies live.
func (r *Rotator) Run(ctx context.Context) {
	r.mu.Lock()
	if r.kick == nil {
		r.kick = make(chan struct{}, 1)
	}
	kick := r.kick
	r.mu.Unlock()
	for {
		rs, _ := r.Settings()
		wait := max(rs.Interval, 10*time.Second)
		if !rs.Enable {
			wait = 30 * time.Second // poll the setting
		}
		select {
		case <-ctx.Done():
			return
		case <-kick:
			r.step(ctx, true)
		case <-time.After(wait):
			if rs.Enable {
				r.step(ctx, false)
			}
		}
	}
}

func (r *Rotator) step(ctx context.Context, forced bool) {
	rs, s := r.Settings()
	if !rs.Enable && !forced {
		return
	}
	bag := LoadBag(r.BagPath, rs.Dir)
	outs := Outputs(ctx)
	if len(outs) == 0 {
		outs = []string{""}
	}
	var first *Result
	for i, o := range outs {
		img := bag.Next(r.last)
		if img == "" {
			return
		}
		r.last = img
		req := Request{Image: img}
		if o != "" {
			req.Outputs = []string{o}
		}
		ss := s
		if i > 0 {
			ss.Hooks, ss.SkipColors = nil, true // colours and hooks once per cycle
		}
		res, err := r.Pipeline.Apply(ctx, req, ss)
		if err == nil && first == nil {
			first = &res
		}
	}
	if first != nil && r.OnApply != nil {
		r.OnApply(*first)
	}
}
