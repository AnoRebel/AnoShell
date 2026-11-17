// Package notifhistory keeps the shell's notification history: every notification the shell receives, kept after it
// is dismissed (notifications.history.* in config.json).
//
// Files are JSON Lines in Settings.Dir: history.jsonl is written to; past RotateBytes it becomes history.1.jsonl (the
// older ones shift up, past RotateKeep they are deleted). Entries are appended in time order, so the files read oldest
// (history.<keep>.jsonl) to newest (history.jsonl).
//
// Age and count limits are applied on every read, so what the shell sees is always within them; the files themselves
// are trimmed when they hold 10% more than the cap, and daily (Run).
package notifhistory

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/sys/unix"

	"ano/anod/internal/config"
)

// Entry is one recorded notification.
type Entry struct {
	ID      string   `json:"id"`   // time-ordered: sorts like Time
	Time    int64    `json:"time"` // ms since the epoch
	App     string   `json:"app"`
	Desktop string   `json:"desktop,omitempty"` // desktop entry, when the sender gave one
	Icon    string   `json:"icon,omitempty"`
	Summary string   `json:"summary"`
	Body    string   `json:"body,omitempty"`
	Urgency string   `json:"urgency"` // low | normal | critical
	Actions []string `json:"actions,omitempty"`
}

// Settings are read before every operation, so config changes apply at once.
type Settings struct {
	Enable      bool
	Dir         string // already expanded
	KeepDays    int    // 0: forever
	MaxEntries  int    // 0: unlimited
	RotateBytes int64  // 0: never rotate
	RotateKeep  int    // rotated files kept
	Exclude     []string
}

// Query selects entries; zero values match everything.
type Query struct {
	Text    string   `json:"text"`    // in summary, body or app, any case
	App     string   `json:"app"`     // app name, any case
	Urgency []string `json:"urgency"` // any of these
	Since   int64    `json:"since"`   // ms, inclusive
	Until   int64    `json:"until"`   // ms, exclusive (0: now)
	Cursor  string   `json:"cursor"`  // the previous page's Next: entries older than it
	Limit   int      `json:"limit"`   // page size (default 50, at most 500)
	IDs     []string `json:"ids"`     // only these (for delete)
}

// Page is one page of a query, newest first.
type Page struct {
	Entries []Entry `json:"entries"`
	Next    string  `json:"next"`  // "" on the last page
	Total   int     `json:"total"` // matching entries in all pages
}

// Stats describes the store for Settings and the history view.
type Stats struct {
	Enable bool   `json:"enable"`
	Dir    string `json:"dir"`
	Count  int    `json:"count"`
	Bytes  int64  `json:"bytes"`
	Files  int    `json:"files"`
	Oldest int64  `json:"oldest"`
	Error  string `json:"error"` // the last write problem, "" when fine
}

// AppCount is one app in the history and how many entries it has.
type AppCount struct {
	App   string `json:"app"`
	Icon  string `json:"icon,omitempty"`
	Count int    `json:"count"`
}

// ErrDisabled is returned by Add while the history is off.
var ErrDisabled = errors.New("notification history is off")

// Store is safe for concurrent use.
type Store struct {
	Settings func() Settings
	Now      func() time.Time            // time.Now when nil
	Changed  func(name string, data any) // "notifhistory_changed" after any change (optional)
	Logf     func(string, ...any)

	mu       sync.Mutex
	seq      uint32
	lastErr  string
	count    int // entries in the files of countDir (-1 or another dir: unknown)
	countDir string
}

const current = "history.jsonl"

func (s *Store) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

func (s *Store) logf(f string, a ...any) {
	if s.Logf != nil {
		s.Logf(f, a...)
	}
}

func (s *Store) changed() {
	if s.Changed != nil {
		s.Changed("notifhistory_changed", nil)
	}
}

// files lists the history files that exist, oldest first.
func files(st Settings) []string {
	var out []string
	for i := st.RotateKeep; i >= 1; i-- {
		p := filepath.Join(st.Dir, fmt.Sprintf("history.%d.jsonl", i))
		if _, err := os.Stat(p); err == nil {
			out = append(out, p)
		}
	}
	if _, err := os.Stat(filepath.Join(st.Dir, current)); err == nil {
		out = append(out, filepath.Join(st.Dir, current))
	}
	return out
}

func excluded(st Settings, e Entry) bool {
	for _, x := range st.Exclude {
		x = strings.TrimSpace(x)
		if x != "" && (strings.EqualFold(x, e.App) || strings.EqualFold(x, e.Desktop)) {
			return true
		}
	}
	return false
}

// Add records one notification. Excluded apps are skipped silently (ok false).
func (s *Store) Add(e Entry) (ok bool, err error) {
	st := s.Settings()
	if !st.Enable {
		return false, ErrDisabled
	}
	if excluded(st, e) {
		return false, nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if e.Time <= 0 {
		e.Time = s.now().UnixMilli()
	}
	s.seq++
	e.ID = fmt.Sprintf("%013x%08x", e.Time, s.seq)
	switch e.Urgency {
	case "low", "normal", "critical":
	default:
		e.Urgency = "normal"
	}
	line, _ := json.Marshal(e)
	line = append(line, '\n')
	if err := s.append(st, line); err != nil {
		s.lastErr = err.Error()
		return false, err
	}
	s.lastErr = ""
	if s.countDir == st.Dir && s.count >= 0 {
		s.count++
	}
	if st.MaxEntries > 0 {
		if n := s.countLocked(st); n > st.MaxEntries+st.MaxEntries/10 {
			if _, err := s.pruneLocked(st); err != nil {
				s.logf("notifhistory: prune: %v", err)
			}
		}
	}
	s.changed()
	return true, nil
}

func (s *Store) append(st Settings, line []byte) error { // s.mu held
	if err := os.MkdirAll(st.Dir, 0o700); err != nil {
		return err
	}
	cur := filepath.Join(st.Dir, current)
	if st.RotateBytes > 0 {
		if fi, err := os.Stat(cur); err == nil && fi.Size() > 0 && fi.Size()+int64(len(line)) > st.RotateBytes {
			if err := rotate(st); err != nil {
				return err
			}
			s.forget()
		}
	}
	f, err := os.OpenFile(cur, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
	if err != nil {
		return err
	}
	if _, err := f.Write(line); err != nil {
		f.Close()
		return err
	}
	return f.Close()
}

// rotate shifts history.N.jsonl up by one (dropping those past RotateKeep) and makes the current file history.1.jsonl.
func rotate(st Settings) error {
	cur := filepath.Join(st.Dir, current)
	if st.RotateKeep <= 0 {
		return os.Remove(cur)
	}
	// Anything at or beyond the last slot goes (also files left from a larger RotateKeep).
	matches, _ := filepath.Glob(filepath.Join(st.Dir, "history.*.jsonl"))
	for _, m := range matches {
		if n := rotatedIndex(m); n >= st.RotateKeep {
			os.Remove(m)
		}
	}
	for i := st.RotateKeep - 1; i >= 1; i-- {
		from := filepath.Join(st.Dir, fmt.Sprintf("history.%d.jsonl", i))
		if _, err := os.Stat(from); err == nil {
			if err := os.Rename(from, filepath.Join(st.Dir, fmt.Sprintf("history.%d.jsonl", i+1))); err != nil {
				return err
			}
		}
	}
	return os.Rename(cur, filepath.Join(st.Dir, "history.1.jsonl"))
}

// forget drops the kept count (files were rotated away, or changed outside rewrite).
func (s *Store) forget() { s.count = -1 }

func rotatedIndex(path string) int {
	b := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(path), "history."), ".jsonl")
	n, err := strconv.Atoi(b)
	if err != nil {
		return 0
	}
	return n
}

// readAll returns every entry in the files, oldest first. Broken lines are skipped.
// ponytail: whole-history scan per read; a few MB parse in milliseconds. Add an index if histories reach ~10⁶ entries.
func readAll(st Settings) []Entry {
	var out []Entry
	for _, p := range files(st) {
		f, err := os.Open(p)
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(f)
		sc.Buffer(make([]byte, 64*1024), 4*1024*1024)
		for sc.Scan() {
			var e Entry
			if json.Unmarshal(sc.Bytes(), &e) == nil && e.ID != "" {
				out = append(out, e)
			}
		}
		f.Close() // a read error (or a line past 4 MB) ends this file early; the rest of it is skipped
	}
	return out
}

// visible applies the age and count limits to the oldest-first list.
func (s *Store) visible(st Settings, all []Entry) []Entry {
	if st.KeepDays > 0 {
		cut := s.now().Add(-time.Duration(st.KeepDays) * 24 * time.Hour).UnixMilli()
		i := 0
		for i < len(all) && all[i].Time < cut {
			i++
		}
		all = all[i:]
	}
	if st.MaxEntries > 0 && len(all) > st.MaxEntries {
		all = all[len(all)-st.MaxEntries:]
	}
	return all
}

// countLocked is the number of entries in the files, read once per folder and then kept up to date.
func (s *Store) countLocked(st Settings) int {
	if s.countDir != st.Dir || s.count < 0 {
		s.count, s.countDir = len(readAll(st)), st.Dir
	}
	return s.count
}

func (q Query) match(e Entry) bool {
	if len(q.IDs) > 0 && !slices.Contains(q.IDs, e.ID) {
		return false
	}
	if q.App != "" && !strings.EqualFold(q.App, e.App) {
		return false
	}
	if len(q.Urgency) > 0 && !slices.Contains(q.Urgency, e.Urgency) {
		return false
	}
	if q.Since > 0 && e.Time < q.Since {
		return false
	}
	if q.Until > 0 && e.Time >= q.Until {
		return false
	}
	if t := strings.TrimSpace(q.Text); t != "" {
		t = strings.ToLower(t)
		if !strings.Contains(strings.ToLower(e.Summary), t) && !strings.Contains(strings.ToLower(e.Body), t) &&
			!strings.Contains(strings.ToLower(e.App), t) {
			return false
		}
	}
	return true
}

// Query returns one page of matching entries, newest first.
func (s *Store) Query(q Query) Page {
	st := s.Settings()
	s.mu.Lock()
	all := s.visible(st, readAll(st))
	s.mu.Unlock()
	limit := q.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > 500 {
		limit = 500
	}
	p := Page{Entries: []Entry{}}
	for i := len(all) - 1; i >= 0; i-- {
		e := all[i]
		if !q.match(e) {
			continue
		}
		p.Total++
		if q.Cursor != "" && e.ID >= q.Cursor {
			continue
		}
		if len(p.Entries) < limit {
			p.Entries = append(p.Entries, e)
		} else if p.Next == "" {
			p.Next = p.Entries[len(p.Entries)-1].ID
		}
	}
	return p
}

// Delete removes the entries matching q (all of them when q is empty and all is true). It returns how many went.
// An empty query without all deletes nothing, so a missing filter can't wipe the history.
func (s *Store) Delete(q Query, all bool) (int, error) {
	if !all && len(q.IDs) == 0 && q.App == "" && q.Text == "" && len(q.Urgency) == 0 && q.Since == 0 && q.Until == 0 {
		return 0, nil
	}
	st := s.Settings()
	s.mu.Lock()
	defer s.mu.Unlock()
	n, err := s.rewrite(st, func(e Entry) bool { return all || q.match(e) })
	if n > 0 {
		s.changed()
	}
	return n, err
}

// rewrite drops the entries drop() picks from every file. Files are replaced atomically; emptied rotated files go.
func (s *Store) rewrite(st Settings, drop func(Entry) bool) (int, error) {
	removed := 0
	for _, p := range files(st) {
		data, err := os.ReadFile(p)
		if err != nil {
			return removed, err
		}
		var keep bytes.Buffer
		n := 0
		for _, line := range bytes.Split(data, []byte{'\n'}) {
			if len(bytes.TrimSpace(line)) == 0 {
				continue
			}
			var e Entry
			if json.Unmarshal(line, &e) == nil && e.ID != "" && drop(e) {
				n++
				continue
			}
			keep.Write(line)
			keep.WriteByte('\n')
		}
		if n == 0 {
			continue
		}
		removed += n
		if s.countDir == st.Dir && s.count >= 0 {
			s.count -= n
		}
		if keep.Len() == 0 && filepath.Base(p) != current {
			if err := os.Remove(p); err != nil {
				return removed, err
			}
			continue
		}
		if err := writeAtomic(p, keep.Bytes()); err != nil {
			return removed, err
		}
	}
	return removed, nil
}

func writeAtomic(path string, data []byte) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".history-*")
	if err != nil {
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return err
	}
	if err := tmp.Close(); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	if err := os.Chmod(tmp.Name(), 0o600); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return os.Rename(tmp.Name(), path)
}

// Prune removes what the age and count limits hide from the files.
func (s *Store) Prune() (int, error) {
	st := s.Settings()
	s.mu.Lock()
	defer s.mu.Unlock()
	n, err := s.pruneLocked(st)
	if n > 0 {
		s.changed()
	}
	return n, err
}

func (s *Store) pruneLocked(st Settings) (int, error) {
	all := readAll(st)
	vis := s.visible(st, all)
	if len(vis) == len(all) {
		return 0, nil
	}
	if len(vis) == 0 {
		return s.rewrite(st, func(Entry) bool { return true })
	}
	first := vis[0].ID // entries are in ID order: everything before the first visible one goes
	return s.rewrite(st, func(e Entry) bool { return e.ID < first })
}

// Apps lists the apps in the visible history, most entries first.
func (s *Store) Apps() []AppCount {
	st := s.Settings()
	s.mu.Lock()
	all := s.visible(st, readAll(st))
	s.mu.Unlock()
	idx := map[string]int{}
	out := []AppCount{}
	for i := len(all) - 1; i >= 0; i-- {
		e := all[i]
		k := strings.ToLower(e.App)
		if j, ok := idx[k]; ok {
			out[j].Count++
			continue
		}
		idx[k] = len(out)
		out = append(out, AppCount{App: e.App, Icon: e.Icon, Count: 1})
	}
	for i := 1; i < len(out); i++ { // stable insertion sort by count, few apps
		for j := i; j > 0 && out[j].Count > out[j-1].Count; j-- {
			out[j], out[j-1] = out[j-1], out[j]
		}
	}
	return out
}

// Stats describes the store.
func (s *Store) Stats() Stats {
	st := s.Settings()
	s.mu.Lock()
	defer s.mu.Unlock()
	out := Stats{Enable: st.Enable, Dir: st.Dir, Error: s.lastErr}
	for _, p := range files(st) {
		if fi, err := os.Stat(p); err == nil {
			out.Bytes += fi.Size()
			out.Files++
		}
	}
	vis := s.visible(st, readAll(st))
	out.Count = len(vis)
	if len(vis) > 0 {
		out.Oldest = vis[0].Time
	}
	if out.Error == "" && st.Enable {
		out.Error = writable(st.Dir)
	}
	return out
}

// writable says why dir can't hold the history ("" when it can), without creating anything: the nearest
// existing folder on its path must be a writable directory.
func writable(dir string) string {
	for d := dir; ; d = filepath.Dir(d) {
		fi, err := os.Stat(d)
		if err == nil {
			if !fi.IsDir() {
				return d + " is not a folder"
			}
			if unix.Access(d, unix.W_OK) != nil {
				return "no permission to write in " + d
			}
			return ""
		}
		if !os.IsNotExist(err) {
			return err.Error()
		}
		if filepath.Dir(d) == d {
			return "no such folder"
		}
	}
}

// Run prunes at start and then daily until ctx ends.
func (s *Store) Run(ctx context.Context) {
	t := time.NewTicker(24 * time.Hour)
	defer t.Stop()
	for {
		if s.Settings().Enable {
			if _, err := s.Prune(); err != nil {
				s.logf("notifhistory: prune: %v", err)
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// ExpandDir resolves the configured folder: "" is the default, a leading ~ is the home folder.
func ExpandDir(path, dataHome, home string) string {
	path = strings.TrimSpace(path)
	switch {
	case path == "":
		return filepath.Join(dataHome, "anoshell", "notifications")
	case path == "~":
		return home
	case strings.HasPrefix(path, "~/"):
		return filepath.Join(home, path[2:])
	case !filepath.IsAbs(path):
		return filepath.Join(home, path)
	}
	return filepath.Clean(path)
}

// FromConfig reads notifications.history.* from an effective config.
func FromConfig(m map[string]any, dataHome, home string) Settings {
	st := Settings{
		Enable:      config.Bool(m, "notifications.history.enable", true),
		Dir:         ExpandDir(config.String(m, "notifications.history.path", ""), dataHome, home),
		KeepDays:    max(0, config.Int(m, "notifications.history.keepDays", 30)),
		MaxEntries:  max(0, config.Int(m, "notifications.history.maxEntries", 5000)),
		RotateBytes: int64(max(0, config.Int(m, "notifications.history.rotateSizeMB", 5))) << 20,
		RotateKeep:  max(0, config.Int(m, "notifications.history.rotateKeep", 5)),
	}
	if v, ok := config.Get(m, "notifications.history.excludeApps"); ok {
		if list, ok := v.([]any); ok {
			for _, x := range list {
				if s, ok := x.(string); ok {
					st.Exclude = append(st.Exclude, s)
				}
			}
		}
	}
	return st
}
