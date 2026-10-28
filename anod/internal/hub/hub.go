// Package hub is the AnoShell Hub's content store: built-in, user and
// catalog-installed themes, looks, widgets, launcher plugins, lock screens,
// wallpapers and rices, verified
// installs with receipts, a static audit for code content, and rice
// apply/undo/export. The shell's Settings → Hub page drives it over anod.
//
// Where items live (cfg = $XDG_CONFIG_HOME):
//
//	themes      <shell>/assets/themes/<id>.json      cfg/anoshell/themes/<id>.json
//	looks       <shell>/looks/<id>.json              cfg/anoshell/looks/<id>.json
//	widgets     <shell>/widgets/<id>/widget.json     cfg/anoshell/widgets/<id>[~<n>]/widget.json
//	plugins     <shell>/plugins/<id>/plugin.json     cfg/anoshell/plugins/<id>[~<n>]/plugin.json
//	lockscreens <shell>/lockscreens/<id>/lockscreen.json  cfg/anoshell/lockscreens/<id>[~<n>]/lockscreen.json
//	wallpapers  (none built in)                      <wallpaper folder>/*, installs in <wallpaper folder>/hub/<id>.<ext>
//	rices       (none built in)                      cfg/anoshell/rices/<id>/rice.json
//
// State: $XDG_STATE_HOME/anoshell/hub/{revision,receipts/<type>/<id>.json,rice-undo.json};
// catalog cache: $XDG_CACHE_HOME/anoshell/hub/catalogs/<sha256(url)[:16]>.json (+ .etag).
package hub

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"ano/anod/internal/backup"
	"ano/anod/internal/config"
	"ano/anod/internal/looks"
)

// Types the Hub handles; "plugins" are launcher plugins.
var Types = []string{"themes", "looks", "widgets", "plugins", "lockscreens", "wallpapers", "rices"}

// codeManifest: the code types (QML that runs with the shell's rights), each
// a folder with this manifest at its root, installed into a fresh <id>~<n>
// folder per version so the shell never loads stale cached QML.
var codeManifest = map[string]string{"widgets": "widget.json", "plugins": "plugin.json", "lockscreens": "lockscreen.json"}

var idRe = regexp.MustCompile(`^[a-z0-9-]+$`)

// ValidID: catalog ids are lowercase letters, digits and dashes.
func ValidID(id string) bool { return idRe.MatchString(id) && len(id) <= 64 }

func checkType(t string) error {
	for _, x := range Types {
		if x == t {
			return nil
		}
	}
	switch t {
	case "launcher-plugins":
		return errors.New(`launcher plugins are "plugins"`)
	case "lock-screens":
		return errors.New(`lock screens are "lockscreens"`)
	}
	return fmt.Errorf("unknown content type %q (want one of %s)", t, strings.Join(Types, ", "))
}

// isCode: content that runs QML with the shell's rights.
func isCode(t string) bool { return codeManifest[t] != "" }

// Hub holds the paths and hooks; New fills them from the environment.
type Hub struct {
	ShellDir     string        // the shell checkout (built-in items)
	ConfigDir    string        // cfg/anoshell
	StateDir     string        // state/anoshell/hub
	CacheDir     string        // cache/anoshell/hub
	Home         string        // rice snapshots hold home-relative paths
	WallpaperDir func() string // the user's wallpaper folder
	Catalogs     func() []string
	Client       *http.Client
	Compositor   string // "hyprland", "niri" or ""

	// Optional hooks (anod wires them; nil in tests).
	SetWallpaper     func(path string) error
	CurrentWallpaper func() string
	KeybindsChanged  func() error // regenerate + reload compositor binds

	// Wallhaven: the API base and the image hosts (tests point them at a fake).
	WallhavenAPI   string
	WallhavenHosts []string

	mu       sync.Mutex
	whCache  map[string]whCached
	whCalls  []time.Time
	pending  map[string]*pending
	fetchErr map[string]string // catalog url -> last refresh error
	hashes   map[string]hashMemo
}

type hashMemo struct {
	size int64
	mod  time.Time
	sum  string
}

// DefaultCatalogs is used when hub.catalogs is unset.
// TODO(user): the AnoShell community catalog URL (task 11.37) is decided by
// the user; until that repo exists the default list is empty.
var DefaultCatalogs = []string{}

func xdg(env, fallback string) string {
	if d := os.Getenv(env); d != "" {
		return d
	}
	h, _ := os.UserHomeDir()
	return filepath.Join(h, fallback)
}

// New reads the paths from the environment and config.
func New() *Hub {
	home, _ := os.UserHomeDir()
	return &Hub{
		ShellDir:  config.ShellDir(),
		ConfigDir: filepath.Dir(config.UserPath()),
		StateDir:  filepath.Join(xdg("XDG_STATE_HOME", ".local/state"), "anoshell", "hub"),
		CacheDir:  filepath.Join(xdg("XDG_CACHE_HOME", ".cache"), "anoshell", "hub"),
		Home:      home,
		WallpaperDir: func() string {
			m, _ := config.Effective()
			return config.WallpaperDir(m)
		},
		Catalogs: func() []string {
			m, err := config.Effective()
			if err != nil {
				return DefaultCatalogs
			}
			v, ok := config.Get(m, "hub.catalogs")
			list, isList := v.([]any)
			if !ok || !isList {
				return DefaultCatalogs
			}
			var out []string
			for _, x := range list {
				if s, ok := x.(string); ok && strings.TrimSpace(s) != "" {
					out = append(out, strings.TrimSpace(s))
				}
			}
			return out
		},
		Client:     &http.Client{Timeout: 15 * time.Second},
		Compositor: RunningCompositor(),
	}
}

// RunningCompositor is "hyprland", "niri" or "".
func RunningCompositor() string {
	switch {
	case os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "":
		return "hyprland"
	case os.Getenv("NIRI_SOCKET") != "":
		return "niri"
	}
	return ""
}

// Init creates the state folder (the shell watches the revision file) and
// clears staging left by an earlier run.
func (h *Hub) Init() error {
	if err := os.MkdirAll(h.StateDir, 0o755); err != nil {
		return err
	}
	if _, err := os.Stat(h.revisionPath()); errors.Is(err, fs.ErrNotExist) {
		config.WriteAtomic(h.revisionPath(), []byte("0\n"), 0o644)
	}
	for _, t := range Types {
		h.cleanStaging(h.stageParent(t))
	}
	return nil
}

func (h *Hub) cleanStaging(dir string) {
	ents, _ := os.ReadDir(dir)
	for _, e := range ents {
		if strings.HasPrefix(e.Name(), ".hub-stage-") || strings.HasPrefix(e.Name(), ".hub-old-") {
			os.RemoveAll(filepath.Join(dir, e.Name()))
		}
	}
}

// ── Revision ────────────────────────────────────────────────────────────

func (h *Hub) revisionPath() string { return filepath.Join(h.StateDir, "revision") }

func (h *Hub) Revision() int {
	b, _ := os.ReadFile(h.revisionPath())
	n, _ := strconv.Atoi(strings.TrimSpace(string(b)))
	return n
}

func (h *Hub) bump() {
	os.MkdirAll(h.StateDir, 0o755)
	config.WriteAtomic(h.revisionPath(), []byte(strconv.Itoa(h.Revision()+1)+"\n"), 0o644)
}

// ── Receipts ────────────────────────────────────────────────────────────

type Receipt struct {
	Catalog     string            `json:"catalog"`
	Version     string            `json:"version"`
	InstalledAt time.Time         `json:"installedAt"`
	Path        string            `json:"path"`
	Files       map[string]string `json:"files"` // relpath -> sha256
	Hosts       []string          `json:"hosts"`
	Commands    []string          `json:"commands"`
	Seq         int               `json:"seq,omitempty"` // widgets: the ~<n> of the folder
}

func (h *Hub) receiptPath(typ, id string) string {
	return filepath.Join(h.StateDir, "receipts", typ, id+".json")
}

func (h *Hub) receipt(typ, id string) *Receipt {
	b, err := os.ReadFile(h.receiptPath(typ, id))
	if err != nil {
		return nil
	}
	var r Receipt
	if json.Unmarshal(b, &r) != nil {
		return nil
	}
	return &r
}

func (h *Hub) writeReceipt(typ, id string, r Receipt) error {
	p := h.receiptPath(typ, id)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	b, _ := json.MarshalIndent(r, "", "  ")
	return config.WriteAtomic(p, append(b, '\n'), 0o644)
}

// hashTree hashes a file (key: its base name) or every regular file under a folder.
func hashTree(root string) (map[string]string, error) {
	out := map[string]string{}
	fi, err := os.Lstat(root)
	if err != nil {
		return nil, err
	}
	if fi.Mode().IsRegular() {
		s, err := hashFile(root)
		out[filepath.Base(root)] = s
		return out, err
	}
	err = filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.Type().IsRegular() {
			rel, _ := filepath.Rel(root, p)
			s, err := hashFile(p)
			if err != nil {
				return err
			}
			out[filepath.ToSlash(rel)] = s
		}
		return nil
	})
	return out, err
}

func hashFile(p string) (string, error) {
	f, err := os.Open(p)
	if err != nil {
		return "", err
	}
	defer f.Close()
	s := sha256.New()
	if _, err := io.Copy(s, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(s.Sum(nil)), nil
}

// modifiedFiles lists the receipt's files that changed or went missing, and
// files added since.
func (h *Hub) modifiedFiles(r *Receipt) []string {
	cur := map[string]string{}
	if fi, err := os.Lstat(r.Path); err == nil && fi.Mode().IsRegular() {
		cur[filepath.Base(r.Path)] = h.memoHash(r.Path, fi)
	} else {
		filepath.WalkDir(r.Path, func(p string, d fs.DirEntry, err error) error {
			if err == nil && d.Type().IsRegular() {
				if fi, err := d.Info(); err == nil {
					rel, _ := filepath.Rel(r.Path, p)
					cur[filepath.ToSlash(rel)] = h.memoHash(p, fi)
				}
			}
			return nil
		})
	}
	out := []string{}
	for f, sum := range r.Files {
		if cur[f] != sum {
			out = append(out, f)
		}
	}
	for f := range cur {
		if _, ok := r.Files[f]; !ok {
			out = append(out, f)
		}
	}
	sort.Strings(out)
	return out
}

// memoHash hashes p, reusing the last result while size and mtime match
// (hub.list runs often; wallpapers are large).
func (h *Hub) memoHash(p string, fi fs.FileInfo) string {
	h.mu.Lock()
	if h.hashes == nil {
		h.hashes = map[string]hashMemo{}
	}
	m, ok := h.hashes[p]
	h.mu.Unlock()
	if ok && m.size == fi.Size() && m.mod.Equal(fi.ModTime()) {
		return m.sum
	}
	s, _ := hashFile(p)
	h.mu.Lock()
	h.hashes[p] = hashMemo{fi.Size(), fi.ModTime(), s}
	h.mu.Unlock()
	return s
}

// ── Listing ─────────────────────────────────────────────────────────────

// Item is one local item, normalised across types.
type Item struct {
	Type        string `json:"type"`
	ID          string `json:"id"`
	Name        string `json:"name"`
	Author      string `json:"author"`
	Version     string `json:"version"`
	Description string `json:"description"`
	Preview     string `json:"preview"`
	Source      string `json:"source"` // builtin | user | installed
	Catalog     string `json:"catalog,omitempty"`
	Path        string `json:"path"`
	Update      string `json:"update,omitempty"`
	Modified    bool   `json:"modified,omitempty"`
	Revoked     bool   `json:"revoked,omitempty"`
	Code        bool   `json:"code"`
	// rices: what the keybinds layer would set, and what it leaves out
	Keybinds        []KeybindSummary `json:"keybinds,omitempty"`
	KeybindsDropped []string         `json:"keybindsDropped,omitempty"`
}

// ListResult is hub.list's reply.
type ListResult struct {
	Revision int             `json:"revision"`
	Items    []Item          `json:"items"`
	Catalog  []CatalogItem   `json:"catalog"`
	Catalogs []CatalogStatus `json:"catalogs"`
	LastRice *LastRice       `json:"lastRice"` // null: nothing to undo
}

// List merges the local items with the cached catalogs (no network).
func (h *Hub) List(typ string) (ListResult, error) {
	types := Types
	if typ != "" {
		if err := checkType(typ); err != nil {
			return ListResult{}, err
		}
		types = []string{typ}
	}
	cats, status := h.cachedCatalogs()
	res := ListResult{Revision: h.Revision(), Items: []Item{}, Catalog: []CatalogItem{}, Catalogs: status, LastRice: h.LastRice()}
	for _, t := range types {
		items := h.localItems(t)
		for i := range items {
			it := &items[i]
			r := h.receipt(t, it.ID)
			if r == nil || it.Source == "builtin" || r.Path != it.Path {
				continue
			}
			it.Source, it.Catalog, it.Version = "installed", r.Catalog, r.Version
			it.Modified = len(h.modifiedFiles(r)) > 0
			if e, ok := findEntry(cats, r.Catalog, t, it.ID); ok {
				it.Revoked = e.Revoked
				if !e.Revoked && newer(e.Version, r.Version) {
					it.Update = e.Version
				}
			}
		}
		res.Items = append(res.Items, items...)
	}
	for _, c := range cats {
		for _, e := range c.Items {
			if typ != "" && e.Type != typ {
				continue
			}
			ci := CatalogItem{Entry: e, Catalog: c.URL, CatalogName: c.Name}
			if r := h.receipt(e.Type, e.ID); r != nil && r.Catalog == c.URL {
				ci.Installed = true
			}
			ci.Unavailable = h.unavailable(e)
			res.Catalog = append(res.Catalog, ci)
		}
	}
	return res, nil
}

func (h *Hub) unavailable(e Entry) string {
	if err := checkType(e.Type); err != nil {
		return "not supported yet"
	}
	if e.Compositor != "" && e.Compositor != h.Compositor {
		return e.Compositor + " only"
	}
	return ""
}

// newer: a's dotted numeric version is above b's (non-numeric: any difference).
func newer(a, b string) bool {
	if a == b || a == "" {
		return false
	}
	pa, pb := strings.Split(strings.TrimPrefix(a, "v"), "."), strings.Split(strings.TrimPrefix(b, "v"), ".")
	for i := 0; i < max(len(pa), len(pb)); i++ {
		var x, y int
		var e1, e2 error
		if i < len(pa) {
			x, e1 = strconv.Atoi(pa[i])
		}
		if i < len(pb) {
			y, e2 = strconv.Atoi(pb[i])
		}
		if e1 != nil || e2 != nil {
			return true
		}
		if x != y {
			return x > y
		}
	}
	return false
}

// meta is the descriptive part every manifest shares.
type meta struct {
	Name        string `json:"name"`
	Author      string `json:"author"`
	Version     string `json:"version"`
	Description string `json:"description"`
	Preview     string `json:"preview"`
	Licence     string `json:"licence"`
}

func readMeta(path string, nested string) meta {
	var m meta
	b, err := os.ReadFile(path)
	if err != nil {
		return m
	}
	if nested != "" {
		var w map[string]json.RawMessage
		if json.Unmarshal(b, &w) == nil {
			json.Unmarshal(w[nested], &m)
		}
		return m
	}
	json.Unmarshal(b, &m)
	return m
}

// localPreview resolves a manifest's preview: https URLs pass, a relative
// file inside dir becomes its path, anything else is dropped.
func localPreview(dir, p string) string {
	if strings.HasPrefix(p, "https://") {
		return p
	}
	if p == "" || !backup.SafeRel(p) {
		return ""
	}
	full := filepath.Join(dir, p)
	if _, err := os.Stat(full); err != nil {
		return ""
	}
	return full
}

func (h *Hub) userDir(t string) string {
	if t == "wallpapers" {
		return filepath.Join(h.WallpaperDir(), "hub")
	}
	return filepath.Join(h.ConfigDir, t)
}

// StripSeq turns a widget folder name "<id>~<n>" into its id.
func StripSeq(dir string) (string, int) {
	if i := strings.LastIndexByte(dir, '~'); i > 0 {
		if n, err := strconv.Atoi(dir[i+1:]); err == nil {
			return dir[:i], n
		}
	}
	return dir, 0
}

func (h *Hub) localItems(t string) []Item {
	var out []Item
	add := func(it Item) {
		it.Type, it.Code = t, isCode(t)
		if it.Name == "" {
			it.Name = it.ID
		}
		out = append(out, it)
	}
	jsonFiles := func(dir, src, nested string) {
		files, _ := filepath.Glob(filepath.Join(dir, "*.json"))
		for _, f := range files {
			m := readMeta(f, nested)
			add(Item{ID: strings.TrimSuffix(filepath.Base(f), ".json"), Name: m.Name, Author: m.Author,
				Version: m.Version, Description: m.Description, Source: src, Path: f})
		}
	}
	switch t {
	case "themes":
		jsonFiles(filepath.Join(h.ShellDir, "assets", "themes"), "builtin", "_meta")
		jsonFiles(h.userDir(t), "user", "_meta")
	case "looks":
		for _, e := range looks.List() {
			m := readMeta(e.Path, "")
			src := "user"
			if e.Source == "bundled" {
				src = "builtin"
			}
			add(Item{ID: e.ID, Name: e.Name, Author: m.Author, Version: m.Version, Description: m.Description, Source: src, Path: e.Path})
		}
	case "widgets", "plugins", "lockscreens":
		for _, d := range []struct{ dir, src string }{{filepath.Join(h.ShellDir, t), "builtin"}, {h.userDir(t), "user"}} {
			ents, _ := os.ReadDir(d.dir)
			for _, e := range ents {
				if !e.IsDir() || strings.HasPrefix(e.Name(), "_") || strings.HasPrefix(e.Name(), ".") {
					continue
				}
				dir := filepath.Join(d.dir, e.Name())
				mf := filepath.Join(dir, codeManifest[t])
				if _, err := os.Stat(mf); err != nil {
					continue
				}
				m := readMeta(mf, "")
				id, _ := StripSeq(e.Name())
				add(Item{ID: id, Name: m.Name, Author: m.Author, Version: m.Version, Description: m.Description,
					Preview: localPreview(dir, m.Preview), Source: d.src, Path: dir})
			}
		}
		if t == "lockscreens" { // the shell's own, drawn by modules/lock
			add(Item{ID: "default", Name: "AnoShell", Description: "The built-in lock screen", Source: "builtin",
				Path: filepath.Join(h.ShellDir, "modules", "lock")})
		}
	case "wallpapers":
		// ponytail: top level of the wallpaper folder plus hub/, capped at
		// 500; the wallpaper picker is the place for a deep browse.
		wd := h.WallpaperDir()
		for _, dir := range []string{h.userDir(t), wd} {
			ents, _ := os.ReadDir(dir)
			for _, e := range ents {
				if len(out) >= 500 {
					break
				}
				if !e.Type().IsRegular() || !isImage(e.Name()) || strings.HasPrefix(e.Name(), ".") {
					continue
				}
				p := filepath.Join(dir, e.Name())
				id := strings.TrimSuffix(e.Name(), filepath.Ext(e.Name()))
				add(Item{ID: id, Name: id, Source: "user", Path: p, Preview: p})
			}
		}
	case "rices":
		ents, _ := os.ReadDir(h.userDir(t))
		for _, e := range ents {
			dir := filepath.Join(h.userDir(t), e.Name())
			if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
				continue
			}
			mf := filepath.Join(dir, "rice.json")
			if _, err := os.Stat(mf); err != nil {
				continue
			}
			m := readMeta(mf, "")
			it := Item{ID: e.Name(), Name: m.Name, Author: m.Author, Version: m.Version, Description: m.Description,
				Preview: localPreview(dir, m.Preview), Source: "user", Path: dir}
			if kb := filepath.Join(dir, "keybinds.json"); fileExists(kb) {
				if _, sum, dropped, err := riceKeybinds(kb); err != nil {
					it.KeybindsDropped = []string{err.Error()}
				} else {
					it.Keybinds, it.KeybindsDropped = sum, dropped
				}
			}
			add(it)
			out[len(out)-1].Code = it.Keybinds != nil || len(it.KeybindsDropped) > 0 || dirExists(filepath.Join(dir, "widgets"))
		}
	}
	if out == nil {
		out = []Item{}
	}
	return out
}

func dirExists(p string) bool {
	fi, err := os.Stat(p)
	return err == nil && fi.IsDir()
}

var imageExts = map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".webp": true, ".avif": true, ".bmp": true, ".gif": true}

func isImage(name string) bool { return imageExts[strings.ToLower(filepath.Ext(name))] }
