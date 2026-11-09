package atelier

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"ano/anod/internal/backup"
)

// Install caps.
const (
	MaxDownload          = 16 << 20 // non-wallpapers
	MaxWallpaperDownload = 64 << 20
	MaxUnpacked          = 64 << 20
	MaxFiles             = 500
	TokenTTL             = 10 * time.Minute
)

// Prepared is atelier.prepare's reply: what the confirmation shows.
type Prepared struct {
	Token               string    `json:"token"`
	Type                string    `json:"type"`
	ID                  string    `json:"id"`
	Code                bool      `json:"code"`
	Name                string    `json:"name"`
	Author              string    `json:"author"`
	Catalog             string    `json:"catalog"`
	CatalogName         string    `json:"catalogName"`
	Version             string    `json:"version"`
	Findings            []Finding `json:"findings"`
	Hosts               []string  `json:"hosts"`
	Commands            []string  `json:"commands"`
	CapabilitiesChanged bool      `json:"capabilitiesChanged"`
	ModifiedFiles       []string  `json:"modifiedFiles"`
	// rices: what the keybinds layer would set (applied only when ticked)
	Keybinds []KeybindSummary `json:"keybinds,omitempty"`
	Update   bool             `json:"update"`            // replaces an installed copy
	Changes  []string         `json:"changes,omitempty"` // what's new in Version (plain text)
}

type pending struct {
	Prepared
	entry   Entry
	stage   string // staged file or folder
	ext     string // wallpapers: the image's extension
	expires time.Time
	// the receipt's version at prepare time ("" = not installed)
	installedVersion string
	timer            *time.Timer
}

// stageParent is where an install of t is staged: the folder it lands in,
// so the final rename stays on one filesystem.
func (h *Store) stageParent(t string) string { return h.userDir(t) }

// singleFile: types whose archive holds exactly one file.
func singleFile(t string) bool { return t == "themes" || t == "looks" || t == "wallpapers" }

// Prepare downloads, verifies, stages and audits a catalog item.
func (h *Store) Prepare(typ, id, catalog string) (*Prepared, error) {
	if err := checkType(typ); err != nil {
		return nil, err
	}
	if !ValidID(id) {
		return nil, fmt.Errorf("invalid id %q (want lowercase letters, digits and dashes)", id)
	}
	if typ == "lockscreens" && id == "default" {
		return nil, errors.New(`"default" is the built-in lock screen's id`)
	}
	cats, _ := h.cachedCatalogs()
	if catalog == "" { // the first catalog that has it
		for _, c := range cats {
			if _, ok := findEntry(cats, c.URL, typ, id); ok {
				catalog = c.URL
				break
			}
		}
	}
	e, ok := findEntry(cats, catalog, typ, id)
	if !ok {
		return nil, fmt.Errorf("%s/%s is not in the catalog %s (refresh the catalogs?)", typ, id, catalog)
	}
	if e.Revoked {
		return nil, fmt.Errorf("%s/%s was revoked by its catalog; it can't be installed", typ, id)
	}
	if u := h.unavailable(e); u != "" {
		return nil, fmt.Errorf("%s/%s is unavailable here: %s", typ, id, u)
	}
	old := h.receipt(typ, id)
	if old == nil {
		if p := h.userItemPath(typ, id); p != "" {
			return nil, fmt.Errorf("you already have your own %s %q at %s; rename or remove it first", strings.TrimSuffix(typ, "s"), id, p)
		}
	}
	catName := catalog
	for _, c := range cats {
		if c.URL == catalog && c.Name != "" {
			catName = c.Name
		}
	}

	data, err := h.download(e)
	if err != nil {
		return nil, err
	}
	tok, err := token()
	if err != nil {
		return nil, err
	}
	parent := h.stageParent(typ)
	if err := os.MkdirAll(parent, 0o755); err != nil {
		return nil, err
	}
	p := &pending{entry: e, stage: filepath.Join(parent, stagePrefix+tok)}
	p.ext, err = extract(data, typ, id, p.stage)
	if err != nil {
		os.RemoveAll(p.stage)
		return nil, err
	}
	p.Prepared = Prepared{
		Token: tok, Type: typ, ID: id, Code: isCode(typ), Name: e.Name, Author: e.Author, Catalog: catalog,
		CatalogName: catName, Version: e.Version, Findings: []Finding{}, Hosts: orEmpty(e.Hosts),
		Commands: orEmpty(e.Commands), ModifiedFiles: []string{}, Update: old != nil, Changes: e.Changes,
	}
	if p.Name == "" {
		p.Name = id
	}
	if isCode(typ) || typ == "rices" {
		root := p.stage
		if typ == "rices" {
			root = filepath.Join(p.stage, "pieces")
		}
		if _, err := os.Stat(root); err == nil {
			p.Code = true
			p.Findings = Audit(root, e.Hosts, e.Commands)
		}
	}
	if kb := filepath.Join(p.stage, "keybinds.json"); typ == "rices" && fileExists(kb) {
		_, sum, dropped, err := riceKeybinds(kb)
		if err != nil {
			os.RemoveAll(p.stage)
			return nil, fmt.Errorf("the rice's keybinds.json is invalid: %v", err)
		}
		p.Code, p.Keybinds = true, sum
		p.Findings = append(p.Findings, auditKeybinds(sum, e.Hosts, e.Commands)...)
		for _, d := range dropped {
			p.Findings = append(p.Findings, Finding{"keybinds-dropped", "keybinds.json", 0, "won't be applied: " + d, "warn"})
		}
	}
	if old != nil {
		p.installedVersion = old.Version
		p.ModifiedFiles = h.modifiedFiles(old)
		p.CapabilitiesChanged = !sameSet(old.Hosts, e.Hosts) || !sameSet(old.Commands, e.Commands)
	}
	p.expires = time.Now().Add(TokenTTL)
	h.mu.Lock()
	if h.pending == nil {
		h.pending = map[string]*pending{}
	}
	h.pending[tok] = p
	p.timer = time.AfterFunc(TokenTTL, func() { h.Cancel(tok) })
	h.mu.Unlock()
	out := p.Prepared
	return &out, nil
}

func orEmpty(s []string) []string {
	if s == nil {
		return []string{}
	}
	return s
}

func sameSet(a, b []string) bool {
	a, b = slices.Clone(a), slices.Clone(b)
	slices.Sort(a)
	slices.Sort(b)
	return slices.Equal(slices.Compact(a), slices.Compact(b))
}

func token() (string, error) {
	b := make([]byte, 12)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// userItemPath is the user's own (receipt-less) copy of typ/id, or "".
func (h *Store) userItemPath(typ, id string) string {
	for _, it := range h.localItems(typ) {
		if it.ID == id && it.Source == "user" && (typ != "wallpapers" || filepath.Dir(it.Path) == h.userDir(typ)) {
			return it.Path
		}
	}
	return ""
}

func (h *Store) download(e Entry) ([]byte, error) {
	if !strings.HasPrefix(e.URL, "https://") {
		return nil, fmt.Errorf("refusing %q: only https downloads", e.URL)
	}
	want := strings.ToLower(strings.TrimSpace(e.SHA256))
	if len(want) != 64 {
		return nil, errors.New("the catalog entry has no valid sha256")
	}
	req, err := http.NewRequest("GET", e.URL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "AnoShell-Atelier")
	c := *h.client()
	c.Timeout = 2 * time.Minute
	resp, err := c.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("download: HTTP %s", resp.Status)
	}
	limit := int64(MaxDownload)
	if e.Type == "wallpapers" {
		limit = MaxWallpaperDownload
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(b)) > limit {
		return nil, fmt.Errorf("download is larger than %d MiB", limit>>20)
	}
	sum := sha256.Sum256(b)
	if got := hex.EncodeToString(sum[:]); got != want {
		return nil, fmt.Errorf("checksum mismatch: the download is %s, the catalog says %s; nothing was installed", got, want)
	}
	return b, nil
}

// extract checks and unpacks a .tar.gz into dst: a folder for pieces and
// rices, a single file (the archive's only entry) for the other types. It
// returns that file's extension. Nothing from the archive is ever run.
func extract(data []byte, typ, id, dst string) (string, error) {
	gz, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return "", fmt.Errorf("not a .tar.gz: %v", err)
	}
	tr := tar.NewReader(gz)
	var total int64
	files, entries, ext := 0, 0, ""
	if !singleFile(typ) {
		if err := os.Mkdir(dst, 0o755); err != nil {
			return "", err
		}
	}
	seen := map[string]bool{}
	for {
		hd, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", fmt.Errorf("archive: %v", err)
		}
		name := strings.TrimPrefix(hd.Name, "./")
		name = strings.TrimSuffix(name, "/")
		if name == "" || name == "." {
			continue
		}
		if entries++; entries > MaxFiles {
			return "", fmt.Errorf("archive has more than %d entries", MaxFiles)
		}
		if !backup.SafeRel(name) || path.IsAbs(hd.Name) {
			return "", fmt.Errorf("archive entry %q: unsafe path", hd.Name)
		}
		switch hd.Typeflag {
		case tar.TypeReg:
		case tar.TypeDir:
			if singleFile(typ) {
				return "", fmt.Errorf("archive entry %q: a %s archive holds one file", hd.Name, typ)
			}
			if err := os.MkdirAll(filepath.Join(dst, name), 0o755); err != nil {
				return "", err
			}
			continue
		case tar.TypeSymlink, tar.TypeLink:
			return "", fmt.Errorf("archive entry %q: links are not allowed", hd.Name)
		default:
			return "", fmt.Errorf("archive entry %q: only regular files and folders are allowed", hd.Name)
		}
		if seen[name] {
			return "", fmt.Errorf("archive entry %q appears twice", hd.Name)
		}
		seen[name] = true
		if files++; files > MaxFiles {
			return "", fmt.Errorf("archive has more than %d files", MaxFiles)
		}
		if total += hd.Size; hd.Size < 0 || total > MaxUnpacked {
			return "", fmt.Errorf("archive unpacks to more than %d MiB", MaxUnpacked>>20)
		}
		target := filepath.Join(dst, filepath.FromSlash(name))
		if singleFile(typ) {
			if files > 1 {
				return "", fmt.Errorf("a %s archive holds exactly one file", typ)
			}
			switch typ {
			case "wallpapers":
				if strings.Contains(name, "/") || !isImage(name) {
					return "", fmt.Errorf("archive entry %q: a wallpaper archive holds one image", name)
				}
				ext = strings.ToLower(filepath.Ext(name))
			default:
				if name != id+".json" {
					return "", fmt.Errorf("archive entry %q: want exactly %s.json", name, id)
				}
				ext = ".json"
			}
			target = dst
		} else if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
			return "", err
		}
		f, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644) // exec bits dropped
		if err != nil {
			return "", err
		}
		_, err = io.Copy(f, io.LimitReader(tr, hd.Size))
		if cerr := f.Close(); err == nil {
			err = cerr
		}
		if err != nil {
			return "", err
		}
	}
	if files == 0 {
		return "", errors.New("the archive is empty")
	}
	switch typ {
	case "pieces", "plugins", "lockscreens":
		mf := codeManifest[typ]
		if _, err := os.Stat(filepath.Join(dst, mf)); err != nil {
			return "", fmt.Errorf("a %s archive needs %s at its root", strings.TrimSuffix(typ, "s"), mf)
		}
		if m := readManifestID(filepath.Join(dst, mf)); m != "" && m != id {
			return "", fmt.Errorf("%s says id %q, the catalog says %q", mf, m, id)
		}
	case "rices":
		if _, err := os.Stat(filepath.Join(dst, "rice.json")); err != nil {
			return "", errors.New("a rice archive needs rice.json at its root")
		}
	}
	return ext, nil
}

func readManifestID(p string) string {
	b, err := os.ReadFile(p)
	if err != nil {
		return ""
	}
	var m struct {
		ID string `json:"id"`
	}
	json.Unmarshal(b, &m)
	return m.ID
}

// Commit installs a prepared item: renamed into place, receipt written,
// revision bumped. It returns the installed path.
func (h *Store) Commit(tok string) (string, error) {
	h.mu.Lock()
	p := h.pending[tok]
	delete(h.pending, tok)
	h.mu.Unlock()
	if p == nil {
		return "", errors.New("unknown or expired install token; prepare it again")
	}
	p.timer.Stop()
	defer os.RemoveAll(p.stage)
	h.itemMu.Lock()
	defer h.itemMu.Unlock()
	typ, id := p.Type, p.ID
	old := h.receipt(typ, id)
	if (old != nil) != p.Update || old != nil && old.Version != p.installedVersion {
		return "", errors.New("the installed copy changed since this install was prepared; prepare it again")
	}
	if old == nil {
		if up := h.userItemPath(typ, id); up != "" {
			return "", fmt.Errorf("you now have your own %s %q at %s; nothing was installed", strings.TrimSuffix(typ, "s"), id, up)
		}
	}
	dir := h.userDir(typ)
	var dst string
	seq := 0
	switch typ {
	case "themes", "looks":
		dst = filepath.Join(dir, id+".json")
	case "wallpapers":
		dst = filepath.Join(dir, id+p.ext)
	case "pieces", "plugins", "lockscreens":
		// A fresh folder per version: the shell never loads stale cached QML.
		seq = 1
		if old != nil {
			seq = old.Seq + 1
		}
		dst, seq = freshDir(dir, id, seq)
	case "rices":
		dst = filepath.Join(dir, id)
	}
	if fi, err := os.Lstat(dst); err == nil && fi.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("refusing to replace symlink %s", dst)
	}
	// Code: the version being replaced moves aside until the new one has
	// loaded once (Confirm deletes it, Rollback brings it back). If the
	// installed version never loaded either, the one before it stays the
	// fallback and the unconfirmed one goes.
	var prev *Receipt
	if isCode(typ) && old != nil {
		if old.Previous != nil {
			prev = old.Previous
		} else if _, err := os.Lstat(old.Path); err == nil && h.inUserDir(typ, old.Path) {
			pp := h.prevPath(typ, id)
			os.RemoveAll(pp)
			if err := os.Rename(old.Path, pp); err != nil {
				return "", err
			}
			c := *old
			c.Path = pp
			prev = &c
		}
	}
	var trash string
	if typ == "rices" {
		if _, err := os.Lstat(dst); err == nil { // a folder can't be renamed over: move the old one aside
			trash = filepath.Join(dir, oldPrefix+tok)
			if err := os.Rename(dst, trash); err != nil {
				return "", err
			}
		}
	}
	if err := os.Rename(p.stage, dst); err != nil {
		if trash != "" {
			os.Rename(trash, dst)
		}
		if prev != nil && old.Previous == nil {
			os.Rename(prev.Path, old.Path)
		}
		return "", err
	}
	if trash != "" {
		os.RemoveAll(trash)
	}
	if old != nil && old.Path != dst && strings.HasPrefix(old.Path, dir+string(filepath.Separator)) {
		os.RemoveAll(old.Path) // the previous version's folder (or a wallpaper with another extension)
	}
	files, err := hashTree(dst)
	if err != nil {
		return "", err
	}
	r := Receipt{Catalog: p.Catalog, Version: p.entry.Version, InstalledAt: time.Now().UTC(), Path: dst,
		Files: files, Hosts: orEmpty(p.entry.Hosts), Commands: orEmpty(p.entry.Commands), Seq: seq, Previous: prev}
	if err := h.writeReceipt(typ, id, r); err != nil {
		return "", err
	}
	h.bump()
	return dst, nil
}

// Cancel drops a prepared install and its staging.
func (h *Store) Cancel(tok string) bool {
	h.mu.Lock()
	p := h.pending[tok]
	delete(h.pending, tok)
	h.mu.Unlock()
	if p == nil {
		return false
	}
	p.timer.Stop()
	os.RemoveAll(p.stage)
	return true
}

// Remove deletes an item installed from a catalog and its receipt.
func (h *Store) Remove(typ, id string) error {
	if err := checkType(typ); err != nil {
		return err
	}
	h.itemMu.Lock()
	defer h.itemMu.Unlock()
	r := h.receipt(typ, id)
	if r == nil {
		for _, it := range h.localItems(typ) {
			if it.ID != id {
				continue
			}
			if it.Source == "builtin" {
				return fmt.Errorf("%s/%s is built in and can't be removed", typ, id)
			}
			return fmt.Errorf("%s/%s is your own file (%s), not an Atelier install; remove it yourself if you mean to", typ, id, it.Path)
		}
		return fmt.Errorf("%s/%s is not installed", typ, id)
	}
	if !strings.HasPrefix(r.Path, h.userDir(typ)+string(filepath.Separator)) {
		return fmt.Errorf("the receipt points outside %s; not removing %s", h.userDir(typ), r.Path)
	}
	if err := os.RemoveAll(r.Path); err != nil {
		return err
	}
	if isCode(typ) {
		os.RemoveAll(h.prevPath(typ, id))
	}
	if err := os.Remove(h.receiptPath(typ, id)); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	h.bump()
	return nil
}

// ── Keep, confirm, roll back (code types) ──────────────────────────────

const prevPrefix = ".atelier-prev-"

// prevPath is where the version before an unconfirmed update waits: a dot
// folder, so the shell's registries don't list it.
func (h *Store) prevPath(typ, id string) string {
	return filepath.Join(h.userDir(typ), prevPrefix+id)
}

func (h *Store) inUserDir(typ, p string) bool {
	return strings.HasPrefix(p, h.userDir(typ)+string(filepath.Separator))
}

// freshDir is the first <dir>/<id>~<n> (n >= seq) that doesn't exist yet.
func freshDir(dir, id string, seq int) (string, int) {
	for {
		dst := filepath.Join(dir, fmt.Sprintf("%s~%d", id, seq))
		if _, err := os.Lstat(dst); errors.Is(err, os.ErrNotExist) {
			return dst, seq
		}
		seq++
	}
}

func codeReceipt(h *Store, typ, id string) (*Receipt, error) {
	if err := checkType(typ); err != nil {
		return nil, err
	}
	if !isCode(typ) {
		return nil, fmt.Errorf("%s have no versions to confirm or roll back", typ)
	}
	if !ValidID(id) {
		return nil, fmt.Errorf("invalid id %q", id)
	}
	r := h.receipt(typ, id)
	if r == nil {
		return nil, fmt.Errorf("%s/%s is not installed from a catalog", typ, id)
	}
	return r, nil
}

// Confirm: the installed version of typ/id loaded, so the previous one kept
// for a rollback goes. path, when set, is the folder that loaded: a report
// about another version is ignored. True when a previous version was dropped.
func (h *Store) Confirm(typ, id, path string) (bool, error) {
	h.itemMu.Lock()
	defer h.itemMu.Unlock()
	r, err := codeReceipt(h, typ, id)
	if err != nil {
		return false, err
	}
	if r.Previous == nil || path != "" && path != r.Path {
		return false, nil
	}
	if pp := h.prevPath(typ, id); r.Previous.Path == pp {
		if err := os.RemoveAll(pp); err != nil {
			return false, err
		}
	}
	r.Previous = nil
	return true, h.writeReceipt(typ, id, *r)
}

// Rollback: the installed version of typ/id failed to load, so the previous
// one comes back (into a fresh <id>~<n> folder) with its receipt, and the
// failed one is deleted. It returns the version now installed.
func (h *Store) Rollback(typ, id, path string) (string, error) {
	h.itemMu.Lock()
	defer h.itemMu.Unlock()
	r, err := codeReceipt(h, typ, id)
	if err != nil {
		return "", err
	}
	if path != "" && path != r.Path {
		return "", fmt.Errorf("%s is not the installed version of %s/%s", path, typ, id)
	}
	pp := h.prevPath(typ, id)
	if r.Previous == nil || r.Previous.Path != pp {
		return "", fmt.Errorf("%s/%s has no previous version to go back to", typ, id)
	}
	if _, err := os.Lstat(pp); err != nil {
		r.Previous = nil
		h.writeReceipt(typ, id, *r)
		return "", fmt.Errorf("the previous version of %s/%s is gone", typ, id)
	}
	dst, seq := freshDir(h.userDir(typ), id, max(r.Seq, r.Previous.Seq)+1)
	if err := os.Rename(pp, dst); err != nil {
		return "", err
	}
	if h.inUserDir(typ, r.Path) {
		os.RemoveAll(r.Path)
	}
	back := *r.Previous
	back.Path, back.Seq, back.Previous = dst, seq, nil
	if err := h.writeReceipt(typ, id, back); err != nil {
		return "", err
	}
	h.bump()
	return back.Version, nil
}

// recoverPrevious tidies after a crash: a kept folder whose update never got
// its receipt goes back in place (and the half-installed newer folder goes);
// one no receipt waits on any more is deleted. An update still waiting for
// its first load keeps both folders.
func (h *Store) recoverPrevious() {
	for typ := range codeManifest {
		dir := h.userDir(typ)
		ents, _ := os.ReadDir(dir)
		for _, e := range ents {
			id, ok := strings.CutPrefix(e.Name(), prevPrefix)
			if !ok || !ValidID(id) {
				continue
			}
			pp := filepath.Join(dir, e.Name())
			r := h.receipt(typ, id)
			switch {
			case r != nil && r.Previous != nil && r.Previous.Path == pp:
				// pending: the shell confirms or rolls back
			case r != nil && h.inUserDir(typ, r.Path) && !exists(r.Path):
				for _, n := range ents { // the newer folder the crash left without a receipt
					if nid, seq := StripSeq(n.Name()); nid == id && seq > r.Seq {
						os.RemoveAll(filepath.Join(dir, n.Name()))
					}
				}
				os.Rename(pp, r.Path)
			default:
				os.RemoveAll(pp)
			}
		}
	}
}

func exists(p string) bool { _, err := os.Lstat(p); return err == nil }
