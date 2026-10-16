// Package palette caches what the shell needs to know about each wallpaper
// without re-reading it: its source colour (matugen), hue, average luminance
// and a tiny luminance map (for glass contrast), plus a still frame for
// videos. Entries are keyed by path + size + mtime, so a second scan of an
// unchanged folder runs nothing. Work runs in a small, niced worker pool.
package palette

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"
)

// Entry is what is known about one file.
type Entry struct {
	Path      string    `json:"path"`
	Size      int64     `json:"size"`
	ModTime   time.Time `json:"mtime"`
	Video     bool      `json:"video,omitempty"`
	Still     string    `json:"still,omitempty"`   // a frame of a video (png)
	Source    string    `json:"source,omitempty"`  // matugen source colour, #rrggbb
	Hue       float64   `json:"hue"`               // 0..360 of Source; -1 if unknown
	Luminance float64   `json:"luminance"`         // 0..1 average
	LumaMap   []byte    `json:"lumaMap,omitempty"` // 16×10 grayscale, row-major
	Error     string    `json:"error,omitempty"`
}

const mapW, mapH = 16, 10

var (
	imageExt = regexp.MustCompile(`(?i)\.(jpe?g|png|webp|gif|bmp|avif|tiff?)$`)
	videoExt = regexp.MustCompile(`(?i)\.(mp4|mkv|webm|mov|avi|m4v|ogv)$`)
)

// Cache is the on-disk palette cache.
type Cache struct {
	Path     string // cache file (json)
	StillDir string // where video stills go
	Workers  int    // 0: half the CPUs (at least 1, at most 4)
	Logf     func(string, ...any)

	mu      sync.Mutex
	entries map[string]Entry
	loaded  bool
	// Spawned counts external processes run (tests check a warm scan runs 0).
	Spawned int
}

func (c *Cache) load() {
	if c.loaded {
		return
	}
	c.loaded = true
	c.entries = map[string]Entry{}
	if b, err := os.ReadFile(c.Path); err == nil {
		var list []Entry
		if json.Unmarshal(b, &list) == nil {
			for _, e := range list {
				c.entries[e.Path] = e
			}
		}
	}
}

func (c *Cache) save() error {
	list := make([]Entry, 0, len(c.entries))
	for _, e := range c.entries {
		list = append(list, e)
	}
	sort.Slice(list, func(i, j int) bool { return list[i].Path < list[j].Path })
	b, err := json.Marshal(list)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(c.Path), 0o755); err != nil {
		return err
	}
	tmp := c.Path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, c.Path)
}

// Scan returns entries for every image/video under dir (not recursive),
// computing only the new or changed ones. Entries for files that are gone
// are dropped from the cache.
func (c *Cache) Scan(ctx context.Context, dir string) ([]Entry, error) {
	ents, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	c.mu.Lock()
	c.load()
	var todo []Entry
	var out []Entry
	seen := map[string]bool{}
	for _, de := range ents {
		if de.IsDir() {
			continue
		}
		p := filepath.Join(dir, de.Name())
		isVid := videoExt.MatchString(p)
		if !isVid && !imageExt.MatchString(p) {
			continue
		}
		fi, err := de.Info()
		if err != nil {
			continue
		}
		seen[p] = true
		if e, ok := c.entries[p]; ok && e.Size == fi.Size() && e.ModTime.Equal(fi.ModTime()) {
			out = append(out, e)
			continue
		}
		todo = append(todo, Entry{Path: p, Size: fi.Size(), ModTime: fi.ModTime(), Video: isVid, Hue: -1})
	}
	for p := range c.entries {
		if filepath.Dir(p) == filepath.Clean(dir) && !seen[p] {
			delete(c.entries, p)
		}
	}
	c.mu.Unlock()

	done := c.compute(ctx, todo)
	c.mu.Lock()
	for _, e := range done {
		c.entries[e.Path] = e
		out = append(out, e)
	}
	err = c.save()
	c.mu.Unlock()
	sort.Slice(out, func(i, j int) bool { return out[i].Path < out[j].Path })
	return out, err
}

func (c *Cache) workers() int {
	if c.Workers > 0 {
		return c.Workers
	}
	return max(1, min(4, runtime.NumCPU()/2))
}

func (c *Cache) compute(ctx context.Context, todo []Entry) []Entry {
	jobs := make(chan Entry)
	res := make(chan Entry)
	var wg sync.WaitGroup
	for range c.workers() {
		wg.Go(func() {
			for e := range jobs {
				res <- c.one(ctx, e)
			}
		})
	}
	go func() {
		for _, e := range todo {
			select {
			case jobs <- e:
			case <-ctx.Done():
			}
		}
		close(jobs)
		wg.Wait()
		close(res)
	}()
	var out []Entry
	for e := range res {
		out = append(out, e)
	}
	return out
}

// one fills in an entry: a still for videos, then matugen and the luma map.
func (c *Cache) one(ctx context.Context, e Entry) Entry {
	src := e.Path
	if e.Video {
		still := filepath.Join(c.StillDir, fmt.Sprintf("%x.png", hash(e.Path)))
		if _, err := c.run(ctx, "ffmpeg", "-y", "-loglevel", "error", "-ss", "1", "-i", e.Path, "-frames:v", "1", "-vf", "scale=480:-2", still); err != nil {
			e.Error = "still: " + err.Error()
			return e
		}
		e.Still, src = still, still
	}
	if out, err := c.run(ctx, "matugen", "image", src, "--prefer", "saturation", "--json", "hex", "--dry-run"); err == nil {
		var d struct {
			Colors map[string]struct {
				Default struct {
					Color string `json:"color"`
				} `json:"default"`
			} `json:"colors"`
		}
		if json.Unmarshal(out, &d) == nil {
			e.Source = d.Colors["source_color"].Default.Color
			e.Hue = Hue(e.Source)
		}
	} else {
		e.Error = "matugen: " + err.Error()
	}
	if raw, err := c.run(ctx, "ffmpeg", "-loglevel", "error", "-i", src, "-vf",
		fmt.Sprintf("scale=%d:%d,format=gray", mapW, mapH), "-frames:v", "1", "-f", "rawvideo", "-"); err == nil && len(raw) >= mapW*mapH {
		e.LumaMap = raw[:mapW*mapH]
		sum := 0
		for _, v := range e.LumaMap {
			sum += int(v)
		}
		e.Luminance = float64(sum) / float64(len(e.LumaMap)) / 255
	}
	return e
}

func (c *Cache) run(ctx context.Context, name string, args ...string) ([]byte, error) {
	c.mu.Lock()
	c.Spawned++
	c.mu.Unlock()
	cctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	// Niced: palette work is background work.
	argv := append([]string{"-n", "15", name}, args...)
	return exec.CommandContext(cctx, "nice", argv...).Output()
}

// Hue returns the hue (0..360) of a #rrggbb colour, -1 if it isn't one.
func Hue(hex string) float64 {
	hex = strings.TrimPrefix(hex, "#")
	var r, g, b int
	if len(hex) != 6 {
		return -1
	}
	if _, err := fmt.Sscanf(hex, "%02x%02x%02x", &r, &g, &b); err != nil {
		return -1
	}
	rf, gf, bf := float64(r)/255, float64(g)/255, float64(b)/255
	mx, mn := math.Max(rf, math.Max(gf, bf)), math.Min(rf, math.Min(gf, bf))
	d := mx - mn
	if d == 0 {
		return 0
	}
	var h float64
	switch mx {
	case rf:
		h = math.Mod((gf-bf)/d, 6)
	case gf:
		h = (bf-rf)/d + 2
	default:
		h = (rf-gf)/d + 4
	}
	h *= 60
	if h < 0 {
		h += 360
	}
	return h
}

func hash(s string) uint64 {
	var h uint64 = 14695981039346656037
	for i := 0; i < len(s); i++ {
		h ^= uint64(s[i])
		h *= 1099511628211
	}
	return h
}
