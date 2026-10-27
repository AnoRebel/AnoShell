package hub

// Rices. A rice is a folder:
//
//	rice.json        {name, author, version, description, preview, keys, config, theme?, look?, wallpaper?}
//	themes/*.json    copied to cfg/anoshell/themes/
//	looks/*.json     copied to cfg/anoshell/looks/
//	widgets/<id>/    copied to cfg/anoshell/widgets/<id>~1/ (skipped when you have that widget)
//	wallpapers/*     copied to <wallpaper folder>/hub/ (never over an existing file)
//	keybinds.json    behaviour layer "keybinds": replaces ano's keybind overrides
//
// `config` is a sparse config delta; only LookKeys are merged from it.

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/user"
	"path/filepath"
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

func lookKey(p string) bool {
	under := func(list []string) bool {
		return slices.ContainsFunc(list, func(k string) bool { return p == k || strings.HasPrefix(p, k+".") })
	}
	return under(LookKeys) && !under(lookDeny)
}

// lookLeaves flattens m into its allowlisted leaf paths (arrays are leaves).
func lookLeaves(m map[string]any, prefix string, out map[string]any) {
	for k, v := range m {
		if k == "" || strings.Contains(k, ".") {
			continue
		}
		p := k
		if prefix != "" {
			p = prefix + "." + k
		}
		if sub, ok := v.(map[string]any); ok {
			lookLeaves(sub, p, out)
		} else if lookKey(p) {
			out[p] = v
		}
	}
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

// undoRecord is what riceUndo needs: the snapshot of the files the apply
// replaced and the files it created.
type undoRecord struct {
	Rice      string    `json:"rice"`
	At        time.Time `json:"at"`
	Snapshot  string    `json:"snapshot"`
	Paths     []string  `json:"paths"`   // home-relative, in the snapshot
	Created   []string  `json:"created"` // absolute, removed on undo
	Wallpaper string    `json:"wallpaper,omitempty"`
	Keybinds  bool      `json:"keybinds,omitempty"`
}

func (h *Hub) undoPath() string { return filepath.Join(h.StateDir, "rice-undo.json") }

// RiceResult is hub.riceApply's reply.
type RiceResult struct {
	Snapshot  string        `json:"snapshot"`
	Applied   []string      `json:"applied"`
	Created   []string      `json:"created"`
	Skipped   []SkippedPart `json:"skipped"`
	Wallpaper string        `json:"wallpaper"`
}

type SkippedPart struct {
	Part   string `json:"part"`
	Reason string `json:"reason"`
}

type copyOp struct{ src, dst string }

// RiceApply applies an installed or user rice. layers picks the behaviour
// layers ("keybinds", "compositor") ticked in the apply dialog.
func (h *Hub) RiceApply(id string, layers []string) (*RiceResult, error) {
	if !ValidID(id) {
		return nil, fmt.Errorf("invalid rice id %q", id)
	}
	dir := filepath.Join(h.userDir("rices"), id)
	var r Rice
	if b, err := os.ReadFile(filepath.Join(dir, "rice.json")); err != nil {
		return nil, fmt.Errorf("no rice %q", id)
	} else if err := json.Unmarshal(b, &r); err != nil {
		return nil, fmt.Errorf("rice.json: %v", err)
	}
	res := &RiceResult{Applied: []string{}, Created: []string{}, Skipped: []SkippedPart{}}
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

	// Plan every write first.
	var ops []copyOp
	parts := map[string]bool{}
	for _, t := range []string{"themes", "looks"} {
		files, _ := filepath.Glob(filepath.Join(dir, t, "*.json"))
		for _, f := range files {
			ops = append(ops, copyOp{f, filepath.Join(h.userDir(t), filepath.Base(f))})
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
			ops = append(ops, copyOp{filepath.Join(dir, "wallpapers", e.Name()), dst})
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
			widgetDirs = append(widgetDirs, copyOp{filepath.Join(dir, "widgets", e.Name()), filepath.Join(h.userDir("widgets"), e.Name()+"~1")})
			parts["widgets"] = true
		}
	}
	kbPath := keybinds.DefaultPaths().Overrides
	if wantKeybinds {
		if _, err := os.Stat(filepath.Join(dir, "keybinds.json")); err == nil {
			ops = append(ops, copyOp{filepath.Join(dir, "keybinds.json"), kbPath})
			parts["keybinds"] = true
		} else {
			wantKeybinds = false
			res.Skipped = append(res.Skipped, SkippedPart{"keybinds", "this rice has no keybinds"})
		}
	}
	leaves := map[string]any{}
	lookLeaves(r.Config, "", leaves)
	cfgPath := config.UserPath()
	if real, err := filepath.EvalSymlinks(cfgPath); err == nil {
		cfgPath = real
	}

	// Snapshot what will be replaced; remember what will be created.
	targets := []string{}
	if len(leaves) > 0 {
		targets = append(targets, cfgPath)
	}
	for _, op := range ops {
		targets = append(targets, op.dst)
	}
	rec := undoRecord{Rice: id, At: time.Now().UTC(), Keybinds: wantKeybinds}
	for _, t := range targets {
		fi, err := os.Lstat(t)
		if errors.Is(err, os.ErrNotExist) {
			rec.Created = append(rec.Created, t)
			continue
		}
		if err != nil || !fi.Mode().IsRegular() {
			return nil, fmt.Errorf("refusing to replace %s (not a regular file)", t)
		}
		rel, err := filepath.Rel(h.Home, t)
		if err != nil || !backup.SafeRel(rel) {
			return nil, fmt.Errorf("%s is outside your home folder; can't snapshot it", t)
		}
		rec.Paths = append(rec.Paths, filepath.ToSlash(rel))
	}
	for _, w := range widgetDirs {
		rec.Created = append(rec.Created, w.dst)
	}
	snapDir := filepath.Join(h.StateDir, "snapshots")
	rec.Snapshot = filepath.Join(snapDir, fmt.Sprintf("rice-%s-%d.tar.gz", id, time.Now().UnixNano()))
	if _, err := backup.Create(h.Home, rec.Snapshot, []backup.Category{{Name: "rice-snapshot", Paths: rec.Paths}}, time.Now()); err != nil {
		return nil, fmt.Errorf("snapshot: %w", err)
	}
	// Written before anything changes, so a failure halfway can still be undone.
	if err := h.writeUndo(rec); err != nil {
		return nil, err
	}

	for _, op := range ops {
		if err := copyFile(op.src, op.dst); err != nil {
			return res, err
		}
	}
	for _, w := range widgetDirs {
		if err := copyTree(w.src, w.dst); err != nil {
			return res, err
		}
	}
	if len(leaves) > 0 {
		user, err := config.Load(cfgPath)
		if err != nil {
			return res, fmt.Errorf("your config: %v", err)
		}
		keys := make([]string, 0, len(leaves))
		for k := range leaves {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			config.Set(user, k, leaves[k])
		}
		if err := writeConfig(cfgPath, user); err != nil {
			return res, err
		}
		parts["config"] = true
	}
	if wallpaper != "" && h.SetWallpaper != nil {
		if h.CurrentWallpaper != nil {
			rec.Wallpaper = h.CurrentWallpaper()
			h.writeUndo(rec)
		}
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
	res.Snapshot, res.Wallpaper = rec.Snapshot, wallpaper
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

// RiceUndo restores the setup from before the last rice apply.
func (h *Hub) RiceUndo() error {
	b, err := os.ReadFile(h.undoPath())
	if err != nil {
		return errors.New("no rice apply to undo")
	}
	var rec undoRecord
	if err := json.Unmarshal(b, &rec); err != nil {
		return err
	}
	if len(rec.Paths) > 0 {
		if _, err := backup.Restore(h.Home, rec.Snapshot, []backup.Category{{Name: "rice-snapshot", Paths: rec.Paths}}, "", false, time.Now()); err != nil {
			return fmt.Errorf("restore: %w", err)
		}
	}
	for _, c := range rec.Created {
		// only what the Hub manages; a tampered record can't delete elsewhere
		if h.managed(c) {
			os.RemoveAll(c)
		}
	}
	if rec.Wallpaper != "" && h.SetWallpaper != nil {
		h.SetWallpaper(rec.Wallpaper)
	}
	if rec.Keybinds && h.KeybindsChanged != nil {
		h.KeybindsChanged()
	}
	os.Remove(h.undoPath())
	h.bump()
	return nil
}

func (h *Hub) managed(p string) bool {
	roots := []string{config.UserPath(), keybinds.DefaultPaths().Overrides}
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
	lookLeaves(userCfg, "", leaves)
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
