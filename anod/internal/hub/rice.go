package hub

// Rices. A rice is a folder:
//
//	rice.json        {name, author, version, description, preview, keys, config, theme?, look?, wallpaper?}
//	themes/*.json    copied to cfg/anoshell/themes/
//	looks/*.json     copied to cfg/anoshell/looks/
//	widgets/<id>/    copied to cfg/anoshell/widgets/<id>~1/ (skipped when you have that widget)
//	wallpapers/*     copied to <wallpaper folder>/hub/ (never over an existing file)
//	keybinds.json    behaviour layer "keybinds": catalogue binds only (see ricekeys.go),
//	                 replacing ano's keybind overrides
//
// `config` is a sparse config delta; only LookKeys that are schema leaves of
// the right type are merged from it.

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/user"
	"path/filepath"
	"reflect"
	"regexp"
	"slices"
	"sort"
	"strings"
	"time"

	"ano/anod/internal/backup"
	"ano/anod/internal/config"
	"ano/anod/internal/keybinds"
)

// LookKeys are the config key paths (and everything under them) a rice may
// set. Conservative: how things look, never what they run (no hooks, apps,
// commands, actions, paths or credentials).
var LookKeys = []string{
	"appearance",
	"panelFamily", "familyTransitionAnimation",
	"bar.style", "bar.cornerStyle", "bar.morphingPanels", "bar.showBackground",
	"dock.style",
	"background.resize", "background.transition",
	"anoSpot.position", "anoSpot.widthPx", "anoSpot.heightPx",
	"widgets.screens", "widgets.cell", "widgets.gap",
}

// lookDeny: per-machine keys under an allowed prefix.
var lookDeny = []string{"appearance.colors.monitor"}

// UndoTTL: how long the last rice apply can be undone.
// ponytail: one fixed window; make it a setting if anyone asks.
const UndoTTL = 14 * 24 * time.Hour

func lookKey(p string) bool {
	under := func(list []string) bool {
		return slices.ContainsFunc(list, func(k string) bool { return p == k || strings.HasPrefix(p, k+".") })
	}
	return under(LookKeys) && !under(lookDeny)
}

// lookAncestor: p is an object on the way to an allowlisted key ("bar").
func lookAncestor(p string) bool {
	return slices.ContainsFunc(LookKeys, func(k string) bool { return strings.HasPrefix(k, p+".") })
}

// lookLeaves collects the allowlisted schema leaves of m whose values fit
// their schema type. A value at an object key, unknown keys and wrong types
// are dropped.
func lookLeaves(m map[string]any, out map[string]any) {
	s, err := config.LoadSchema()
	if err != nil {
		return
	}
	var walk func(m map[string]any, prefix string)
	walk = func(m map[string]any, prefix string) {
		for k, v := range m {
			if k == "" || strings.Contains(k, ".") {
				continue
			}
			p := k
			if prefix != "" {
				p = prefix + "." + k
			}
			if !lookKey(p) && !lookAncestor(p) {
				continue
			}
			if _, leaf := s.Leaves[p]; leaf {
				if lookKey(p) && s.Leaf(p, v) {
					out[p] = v
				}
			} else if sub, ok := v.(map[string]any); ok && s.Object(p) {
				walk(sub, p)
			}
		}
	}
	walk(m, "")
}

// Rice is rice.json.
type Rice struct {
	ID          string         `json:"id,omitempty"`
	Name        string         `json:"name"`
	Author      string         `json:"author"`
	Version     string         `json:"version"`
	Description string         `json:"description"`
	Preview     string         `json:"preview,omitempty"`
	Keys        []string       `json:"keys"`
	Config      map[string]any `json:"config"`
	Theme       string         `json:"theme,omitempty"`
	Look        string         `json:"look,omitempty"`
	Wallpaper   string         `json:"wallpaper,omitempty"` // a file in wallpapers/
}

// decodeNumbers decodes JSON keeping numbers as json.Number (what the
// config schema checks and writes back unchanged).
func decodeNumbers(b []byte, v any) error {
	d := json.NewDecoder(bytes.NewReader(b))
	d.UseNumber()
	return d.Decode(v)
}

func readRice(dir string) (Rice, error) {
	var r Rice
	b, err := os.ReadFile(filepath.Join(dir, "rice.json"))
	if err != nil {
		return r, fmt.Errorf("no rice at %s", dir)
	}
	if err := decodeNumbers(b, &r); err != nil {
		return r, fmt.Errorf("rice.json: %v", err)
	}
	return r, nil
}

// configPrev is a config key's value before a rice set it, and what it set.
type configPrev struct {
	Key     string `json:"key"`
	Had     bool   `json:"had"`
	Value   any    `json:"value,omitempty"`
	Applied any    `json:"applied"`
}

// undoRecord is what riceUndo needs.
type undoRecord struct {
	Rice      string            `json:"rice"`
	Name      string            `json:"name"`
	At        time.Time         `json:"at"`
	Snapshot  string            `json:"snapshot"`
	Paths     []string          `json:"paths"`   // replaced files, home-relative, in the snapshot
	Created   []string          `json:"created"` // absolute, removed on undo
	Hashes    map[string]string `json:"hashes"`  // replaced and created paths -> fingerprint after the apply
	Config    []configPrev      `json:"config"`  // the keys the rice set
	CfgPath   string            `json:"configPath"`
	Wallpaper string            `json:"wallpaper,omitempty"` // shown before the apply
	Keybinds  bool              `json:"keybinds,omitempty"`
}

func (h *Hub) undoPath() string { return filepath.Join(h.StateDir, "rice-undo.json") }

func (h *Hub) readUndo() (*undoRecord, error) {
	b, err := os.ReadFile(h.undoPath())
	if err != nil {
		return nil, errors.New("no rice apply to undo")
	}
	var rec undoRecord
	if err := decodeNumbers(b, &rec); err != nil {
		return nil, err
	}
	return &rec, nil
}

// LastRice is the rice apply that can still be undone.
type LastRice struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	AppliedAt int64  `json:"appliedAt"` // unix seconds
}

// LastRice is nil when there is nothing to undo.
func (h *Hub) LastRice() *LastRice {
	rec, err := h.readUndo()
	if err != nil || time.Since(rec.At) > UndoTTL {
		return nil
	}
	return &LastRice{rec.Rice, rec.Name, rec.At.Unix()}
}

// RiceResult is hub.riceApply's reply.
type RiceResult struct {
	Snapshot  string           `json:"snapshot"`
	Applied   []string         `json:"applied"`
	Created   []string         `json:"created"`
	Skipped   []SkippedPart    `json:"skipped"`
	Wallpaper string           `json:"wallpaper"`
	Keybinds  []KeybindSummary `json:"keybinds"` // what the keybinds layer set (empty when unticked)
	AppliedAt int64            `json:"appliedAt"`
}

type SkippedPart struct {
	Part   string `json:"part"`
	Reason string `json:"reason"`
}

// copyOp copies src to dst, or writes data when it is set.
type copyOp struct {
	src, dst string
	data     []byte
}

// RiceApply applies an installed or user rice. layers picks the behaviour
// layers ("keybinds", "compositor") ticked in the apply dialog.
func (h *Hub) RiceApply(id string, layers []string) (*RiceResult, error) {
	if !ValidID(id) {
		return nil, fmt.Errorf("invalid rice id %q", id)
	}
	dir := filepath.Join(h.userDir("rices"), id)
	r, err := readRice(dir)
	if err != nil {
		return nil, err
	}
	res := &RiceResult{Applied: []string{}, Created: []string{}, Skipped: []SkippedPart{}, Keybinds: []KeybindSummary{}}
	wantKeybinds := false
	for _, l := range layers {
		switch l {
		case "keybinds":
			wantKeybinds = true
		case "compositor":
			res.Skipped = append(res.Skipped, SkippedPart{"compositor", "not supported yet"})
		default:
			return nil, fmt.Errorf("unknown layer %q (want keybinds or compositor)", l)
		}
	}

	// Plan and check everything before anything changes.
	var ops []copyOp
	parts := map[string]bool{}
	kbPath := keybinds.DefaultPaths().Overrides
	if wantKeybinds {
		if src := filepath.Join(dir, "keybinds.json"); fileExists(src) {
			o, summary, dropped, err := riceKeybinds(src)
			if err != nil {
				return nil, fmt.Errorf("the rice's keybinds can't be applied: %v", err)
			}
			for _, d := range dropped {
				res.Skipped = append(res.Skipped, SkippedPart{"keybinds", d})
			}
			if len(o.Binds) == 0 && len(o.Remove) == 0 {
				// nothing usable: keep the user's keybinds rather than emptying them
				res.Skipped = append(res.Skipped, SkippedPart{"keybinds", "nothing in this rice's keybinds can be applied; yours are unchanged"})
				wantKeybinds = false
			} else {
				b, _ := json.MarshalIndent(o, "", "  ")
				ops = append(ops, copyOp{dst: kbPath, data: append(b, '\n')})
				res.Keybinds = summary
				parts["keybinds"] = true
			}
		} else {
			wantKeybinds = false
			res.Skipped = append(res.Skipped, SkippedPart{"keybinds", "this rice has no keybinds"})
		}
	}
	for _, t := range []string{"themes", "looks"} {
		files, _ := filepath.Glob(filepath.Join(dir, t, "*.json"))
		for _, f := range files {
			ops = append(ops, copyOp{src: f, dst: filepath.Join(h.userDir(t), filepath.Base(f))})
			parts[t] = true
		}
	}
	var wallpaper string
	if ents, err := os.ReadDir(filepath.Join(dir, "wallpapers")); err == nil {
		for _, e := range ents {
			if !e.Type().IsRegular() || !isImage(e.Name()) {
				continue
			}
			dst := filepath.Join(h.userDir("wallpapers"), e.Name())
			if e.Name() == filepath.Base(r.Wallpaper) {
				wallpaper = dst
			}
			if _, err := os.Lstat(dst); err == nil {
				continue // already there (from an earlier apply, or yours)
			}
			ops = append(ops, copyOp{src: filepath.Join(dir, "wallpapers", e.Name()), dst: dst})
			parts["wallpapers"] = true
		}
	}
	var widgetDirs []copyOp
	if ents, err := os.ReadDir(filepath.Join(dir, "widgets")); err == nil {
		have := map[string]bool{}
		for _, it := range h.localItems("widgets") {
			have[it.ID] = true
		}
		for _, e := range ents {
			if !e.IsDir() || !ValidID(e.Name()) {
				continue
			}
			if have[e.Name()] {
				res.Skipped = append(res.Skipped, SkippedPart{"widgets/" + e.Name(), "you already have this widget"})
				continue
			}
			widgetDirs = append(widgetDirs, copyOp{src: filepath.Join(dir, "widgets", e.Name()), dst: filepath.Join(h.userDir("widgets"), e.Name()+"~1")})
			parts["widgets"] = true
		}
	}
	leaves := map[string]any{}
	lookLeaves(r.Config, leaves)
	cfgPath := config.UserPath()
	if real, err := filepath.EvalSymlinks(cfgPath); err == nil {
		cfgPath = real
	}
	var userCfg map[string]any
	rec := undoRecord{Rice: id, Name: r.Name, At: time.Now().UTC(), Keybinds: wantKeybinds, CfgPath: cfgPath, Hashes: map[string]string{}}
	if rec.Name == "" {
		rec.Name = id
	}
	keys := make([]string, 0, len(leaves))
	for k := range leaves {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	if len(keys) > 0 {
		if userCfg, err = config.Load(cfgPath); err != nil {
			return nil, fmt.Errorf("your config: %v", err)
		}
		for _, k := range keys {
			v, had := config.Get(userCfg, k)
			rec.Config = append(rec.Config, configPrev{k, had, v, leaves[k]})
		}
	}

	// Snapshot the files that will be replaced; remember what will be created.
	for _, op := range ops {
		fi, err := os.Lstat(op.dst)
		if errors.Is(err, os.ErrNotExist) {
			rec.Created = append(rec.Created, op.dst)
			continue
		}
		if err != nil || !fi.Mode().IsRegular() {
			return nil, fmt.Errorf("refusing to replace %s (not a regular file)", op.dst)
		}
		rel, err := filepath.Rel(h.Home, op.dst)
		if err != nil || !backup.SafeRel(rel) {
			return nil, fmt.Errorf("%s is outside your home folder; can't snapshot it", op.dst)
		}
		rec.Paths = append(rec.Paths, filepath.ToSlash(rel))
	}
	for _, w := range widgetDirs {
		rec.Created = append(rec.Created, w.dst)
	}
	if h.CurrentWallpaper != nil {
		rec.Wallpaper = h.CurrentWallpaper()
	}
	rec.Snapshot = filepath.Join(h.StateDir, "snapshots", fmt.Sprintf("rice-%s-%d.tar.gz", id, time.Now().UnixNano()))
	if _, err := backup.Create(h.Home, rec.Snapshot, []backup.Category{{Name: "rice-snapshot", Paths: rec.Paths}}, time.Now()); err != nil {
		return nil, fmt.Errorf("snapshot: %w", err)
	}
	// Written before anything changes, so a failure halfway can still be undone.
	if err := h.writeUndo(rec); err != nil {
		return nil, err
	}

	for _, op := range ops {
		var err error
		if op.data != nil {
			err = writeFileAtomic(op.dst, op.data)
		} else {
			err = copyFile(op.src, op.dst)
		}
		if err != nil {
			return res, err
		}
	}
	for _, w := range widgetDirs {
		if err := copyTree(w.src, w.dst); err != nil {
			return res, err
		}
	}
	if len(keys) > 0 {
		for _, k := range keys {
			config.Set(userCfg, k, leaves[k])
		}
		if err := writeConfig(cfgPath, userCfg); err != nil {
			return res, err
		}
		parts["config"] = true
	}
	for _, p := range rec.Created {
		rec.Hashes[p] = fingerprint(p)
	}
	for _, rel := range rec.Paths {
		p := filepath.Join(h.Home, rel)
		rec.Hashes[p] = fingerprint(p)
	}
	if err := h.writeUndo(rec); err != nil {
		return res, err
	}
	if wallpaper != "" && h.SetWallpaper != nil {
		if err := h.SetWallpaper(wallpaper); err != nil {
			res.Skipped = append(res.Skipped, SkippedPart{"wallpaper", err.Error()})
		}
	}
	if wantKeybinds && h.KeybindsChanged != nil {
		if err := h.KeybindsChanged(); err != nil {
			res.Skipped = append(res.Skipped, SkippedPart{"keybinds", "saved, but regenerating the binds failed: " + err.Error()})
		}
	}
	for _, p := range []string{"config", "themes", "looks", "widgets", "wallpapers", "keybinds"} {
		if parts[p] {
			res.Applied = append(res.Applied, p)
		}
	}
	res.Snapshot, res.Wallpaper, res.AppliedAt = rec.Snapshot, wallpaper, rec.At.Unix()
	res.Created = append(res.Created, rec.Created...)
	h.bump()
	return res, nil
}

func (h *Hub) writeUndo(rec undoRecord) error {
	if err := os.MkdirAll(h.StateDir, 0o755); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(rec, "", "  ")
	return config.WriteAtomic(h.undoPath(), b, 0o644)
}

// fingerprint is a file's SHA-256, a folder's hash over its files, or "" when missing.
func fingerprint(p string) string {
	fi, err := os.Lstat(p)
	if err != nil {
		return ""
	}
	if fi.Mode().IsRegular() {
		s, _ := hashFile(p)
		return s
	}
	files, _ := hashTree(p)
	names := make([]string, 0, len(files))
	for n := range files {
		names = append(names, n)
	}
	sort.Strings(names)
	s := sha256.New()
	for _, n := range names {
		fmt.Fprintf(s, "%s=%s\n", n, files[n])
	}
	return "dir:" + hex.EncodeToString(s.Sum(nil))
}

// RiceUndo puts back what the last rice apply changed: the config keys it
// set, the files it replaced, and removes the files it created. It refuses
// when any of those files changed since; a config key you changed since is
// kept as you set it and returned in kept. Undo never discards later edits.
func (h *Hub) RiceUndo() (kept []string, err error) {
	kept = []string{}
	rec, err := h.readUndo()
	if err != nil {
		return kept, err
	}
	if time.Since(rec.At) > UndoTTL {
		os.Remove(h.undoPath())
		return kept, fmt.Errorf("%s was applied more than %d days ago; undo is no longer offered", rec.Name, int(UndoTTL.Hours()/24))
	}
	created := map[string]bool{}
	for _, c := range rec.Created {
		created[c] = true
	}
	var changed []string
	for p, want := range rec.Hashes {
		got := fingerprint(p)
		if got != want && !(created[p] && got == "") {
			changed = append(changed, p)
		}
	}
	if len(changed) > 0 {
		sort.Strings(changed)
		return kept, fmt.Errorf("can't undo %s: changed since it was applied (undo would discard your edits): %s", rec.Name, strings.Join(changed, ", "))
	}
	if len(rec.Paths) > 0 {
		if _, err := backup.Restore(h.Home, rec.Snapshot, []backup.Category{{Name: "rice-snapshot", Paths: rec.Paths}}, "", false, time.Now()); err != nil {
			return kept, fmt.Errorf("restore: %w", err)
		}
	}
	if len(rec.Config) > 0 {
		cfg, err := config.Load(rec.CfgPath)
		if err != nil {
			return kept, fmt.Errorf("your config: %v", err)
		}
		for _, c := range rec.Config {
			if cur, ok := config.Get(cfg, c.Key); !ok || !reflect.DeepEqual(cur, c.Applied) {
				kept = append(kept, c.Key) // you changed it since: yours stays
				continue
			}
			if c.Had {
				config.Set(cfg, c.Key, c.Value)
			} else {
				config.Delete(cfg, c.Key)
			}
		}
		if err := writeConfig(rec.CfgPath, cfg); err != nil {
			return kept, err
		}
	}
	inUse := ""
	if rec.Wallpaper != "" && h.SetWallpaper != nil {
		h.SetWallpaper(rec.Wallpaper)
	}
	if h.CurrentWallpaper != nil {
		inUse = h.CurrentWallpaper()
	}
	for _, c := range rec.Created {
		// only what the Hub manages, never the config or the wallpaper on screen
		if h.managed(c) && c != inUse && c != rec.CfgPath && c != config.UserPath() {
			os.RemoveAll(c)
		}
	}
	if rec.Keybinds && h.KeybindsChanged != nil {
		h.KeybindsChanged()
	}
	os.Remove(h.undoPath())
	h.bump()
	return kept, nil
}

func (h *Hub) managed(p string) bool {
	roots := []string{keybinds.DefaultPaths().Overrides}
	for _, t := range Types {
		roots = append(roots, h.userDir(t)+string(filepath.Separator))
	}
	for _, r := range roots {
		if p == r || strings.HasSuffix(r, string(filepath.Separator)) && strings.HasPrefix(p, r) {
			return true
		}
	}
	return false
}

func writeFileAtomic(dst string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	return config.WriteAtomic(dst, data, 0o644)
}

func writeConfig(path string, m map[string]any) error {
	b, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	perm := os.FileMode(0o644)
	if fi, err := os.Stat(path); err == nil {
		perm = fi.Mode().Perm()
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return config.WriteAtomic(path, append(b, '\n'), perm)
}

func copyFile(src, dst string) error {
	if fi, err := os.Lstat(src); err != nil || !fi.Mode().IsRegular() {
		return fmt.Errorf("%s is not a regular file", src)
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(dst), ".hub-copy-*")
	if err != nil {
		return err
	}
	_, err = io.Copy(tmp, in)
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = os.Chmod(tmp.Name(), 0o644)
	}
	if err == nil {
		err = os.Rename(tmp.Name(), dst)
	}
	if err != nil {
		os.Remove(tmp.Name())
	}
	return err
}

// copyTree copies regular files only (symlinks and the rest are skipped).
func copyTree(src, dst string) error {
	return filepath.WalkDir(src, func(p string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(src, p)
		switch {
		case d.IsDir():
			return os.MkdirAll(filepath.Join(dst, rel), 0o755)
		case d.Type().IsRegular():
			return copyFile(p, filepath.Join(dst, rel))
		}
		return nil
	})
}

var slugRe = regexp.MustCompile(`[^a-z0-9]+`)

// Slug turns a display name into an id.
func Slug(name string) string {
	s := strings.Trim(slugRe.ReplaceAllString(strings.ToLower(name), "-"), "-")
	if len(s) > 64 {
		s = strings.TrimRight(s[:64], "-")
	}
	return s
}

// RiceExport saves the current look as cfg/anoshell/rices/<id>/.
func (h *Hub) RiceExport(name string) (string, string, error) {
	id := Slug(name)
	if !ValidID(id) {
		return "", "", errors.New("give the rice a name with letters or digits")
	}
	dir := filepath.Join(h.userDir("rices"), id)
	if _, err := os.Lstat(dir); err == nil {
		return "", "", fmt.Errorf("a rice named %q already exists (%s)", id, dir)
	}
	userCfg, err := config.Load(config.UserPath())
	if err != nil {
		return "", "", err
	}
	eff, err := config.Effective()
	if err != nil {
		eff = userCfg
	}
	leaves := map[string]any{}
	lookLeaves(userCfg, leaves)
	r := Rice{ID: id, Name: strings.TrimSpace(name), Version: "1.0.0", Keys: []string{}, Config: map[string]any{}}
	if u, err := user.Current(); err == nil {
		r.Author = u.Username
	}
	for k, v := range leaves {
		config.Set(r.Config, k, v)
		r.Keys = append(r.Keys, k)
	}
	sort.Strings(r.Keys)
	tmp, err := os.MkdirTemp(h.userDir("rices"), ".hub-stage-")
	if errors.Is(err, os.ErrNotExist) {
		os.MkdirAll(h.userDir("rices"), 0o755)
		tmp, err = os.MkdirTemp(h.userDir("rices"), ".hub-stage-")
	}
	if err != nil {
		return "", "", err
	}
	defer os.RemoveAll(tmp)
	// The theme and look, when they are your own files (built-in ones ship with the shell).
	if t := config.String(eff, "appearance.theme.name", ""); t != "" && ValidName(t) {
		if src := filepath.Join(h.userDir("themes"), t+".json"); fileExists(src) {
			if err := copyFile(src, filepath.Join(tmp, "themes", t+".json")); err != nil {
				return "", "", err
			}
			r.Theme = t
		}
	}
	if l := config.String(eff, "appearance.look", ""); l != "" && ValidName(l) {
		if src := filepath.Join(h.userDir("looks"), l+".json"); fileExists(src) {
			if err := copyFile(src, filepath.Join(tmp, "looks", l+".json")); err != nil {
				return "", "", err
			}
			r.Look = l
		}
	}
	wp := ""
	if h.CurrentWallpaper != nil {
		wp = h.CurrentWallpaper()
	}
	if wp == "" {
		wp = config.String(eff, "background.wallpaperPath", "")
	}
	if fi, err := os.Stat(wp); wp != "" && err == nil && fi.Mode().IsRegular() && isImage(wp) && fi.Size() <= MaxWallpaperDownload {
		if err := copyFile(wp, filepath.Join(tmp, "wallpapers", filepath.Base(wp))); err != nil {
			return "", "", err
		}
		r.Wallpaper = filepath.Base(wp)
	}
	b, _ := json.MarshalIndent(r, "", "  ")
	if err := os.WriteFile(filepath.Join(tmp, "rice.json"), append(b, '\n'), 0o644); err != nil {
		return "", "", err
	}
	if err := os.Rename(tmp, dir); err != nil {
		return "", "", err
	}
	h.bump()
	return id, dir, nil
}

// ValidName: a theme/look file stem that is a plain name.
func ValidName(s string) bool {
	return s != "" && !strings.ContainsAny(s, `/\`) && s != "." && s != ".."
}

func fileExists(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.Mode().IsRegular()
}
