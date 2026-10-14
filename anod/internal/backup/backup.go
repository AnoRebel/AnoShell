// Package backup archives and restores AnoShell's user data by category.
//
// An archive is a .tar.gz whose entries are paths relative to $HOME, plus a
// manifest.json naming the categories it holds. Restore writes only entries
// that belong to the categories asked for, never outside $HOME, never through
// symlinks, and snapshots the files it is about to replace first.
package backup

import (
	"archive/tar"
	"compress/gzip"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"time"
)

// Category is one selectable part of the setup. Paths are relative to $HOME.
type Category struct {
	Name, Desc string
	Paths      []string
	Exclude    []string // relative paths skipped inside Paths
	Default    bool     // part of a backup when no categories are named
}

// Categories lists every part of the setup that can be backed up.
var Categories = []Category{
	{"config", "settings (config.json, including anod hooks)", []string{".config/anoshell/config.json"}, nil, true},
	{"themes", "your themes", []string{".config/anoshell/themes"}, nil, true},
	{"widgets", "your desktop widgets", []string{".config/anoshell/widgets"}, nil, true},
	{"data", "calendar, chats, notes and other shell data", []string{
		".config/anoshell/calendar-events.json", ".config/anoshell/calendar-sync.json",
		".config/anoshell/holidays.json", ".local/share/anoshell",
	}, []string{".local/share/anoshell/secrets", ".local/share/anoshell/backups"}, true},
	{"secrets", "API keys (sensitive; opt-in)", []string{".local/share/anoshell/secrets"}, nil, false},
	{"compositor", "Hyprland and niri configs (opt-in)", []string{".config/hypr", ".config/niri"}, nil, false},
	{"wallpapers", "the wallpaper folder (large; opt-in)", []string{"Pictures/hyprwallpapers"}, nil, false},
	{"avatar", "your avatar (~/.face)", []string{".face", ".face.icon"}, nil, false},
}

// Lookup returns the named categories, or the defaults when names is empty.
func Lookup(names []string) ([]Category, error) {
	if len(names) == 0 {
		var out []Category
		for _, c := range Categories {
			if c.Default {
				out = append(out, c)
			}
		}
		return out, nil
	}
	var out []Category
	for _, n := range names {
		i := slices.IndexFunc(Categories, func(c Category) bool { return c.Name == n })
		if i < 0 {
			return nil, fmt.Errorf("unknown category %q", n)
		}
		out = append(out, Categories[i])
	}
	return out, nil
}

// Manifest describes an archive.
type Manifest struct {
	Version    int       `json:"version"`
	Created    time.Time `json:"created"`
	Host       string    `json:"host"`
	Categories []string  `json:"categories"`
	Files      int       `json:"files"`
}

const manifestName = "manifest.json"

func (c Category) owns(rel string) bool {
	for _, x := range c.Exclude {
		if rel == x || strings.HasPrefix(rel, x+"/") {
			return false
		}
	}
	for _, p := range c.Paths {
		if rel == p || strings.HasPrefix(rel, p+"/") {
			return true
		}
	}
	return false
}

// Create writes the categories' files under home into a new archive at dest.
// Missing paths are skipped; symlinks are not followed.
func Create(home, dest string, cats []Category, now time.Time) (Manifest, error) {
	host, _ := os.Hostname()
	m := Manifest{Version: 1, Created: now, Host: host}
	var files []string
	for _, c := range cats {
		m.Categories = append(m.Categories, c.Name)
		for _, p := range c.Paths {
			// A category root may be a symlink (dotfile managers like stow):
			// walk its target, but record paths under the root's name.
			root := filepath.Join(home, p)
			real, err := filepath.EvalSymlinks(root)
			if err != nil {
				continue // missing
			}
			filepath.WalkDir(real, func(path string, d fs.DirEntry, err error) error {
				if err != nil {
					return nil // unreadable: skip
				}
				sub, _ := filepath.Rel(real, path)
				rel := filepath.ToSlash(filepath.Join(p, sub))
				if !c.owns(rel) {
					if d.IsDir() {
						return filepath.SkipDir
					}
					return nil
				}
				if d.Type().IsRegular() {
					files = append(files, rel)
				}
				return nil
			})
		}
	}
	sort.Strings(files)
	files = slices.Compact(files)
	m.Files = len(files)

	if err := os.MkdirAll(filepath.Dir(dest), 0o700); err != nil {
		return m, err
	}
	f, err := os.OpenFile(dest, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return m, err
	}
	defer f.Close()
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	mb, _ := json.MarshalIndent(m, "", "  ")
	if err := writeEntry(tw, manifestName, 0o644, now, mb); err != nil {
		return m, err
	}
	for _, rel := range files {
		if err := addFile(tw, home, rel); err != nil {
			return m, err
		}
	}
	if err := tw.Close(); err != nil {
		return m, err
	}
	if err := gz.Close(); err != nil {
		return m, err
	}
	return m, f.Close()
}

func writeEntry(tw *tar.Writer, name string, mode int64, mod time.Time, b []byte) error {
	if err := tw.WriteHeader(&tar.Header{Name: name, Mode: mode, Size: int64(len(b)), ModTime: mod, Typeflag: tar.TypeReg}); err != nil {
		return err
	}
	_, err := tw.Write(b)
	return err
}

func addFile(tw *tar.Writer, home, rel string) error {
	path, err := filepath.EvalSymlinks(filepath.Join(home, rel))
	if err != nil {
		return nil
	}
	fi, err := os.Lstat(path)
	if err != nil || !fi.Mode().IsRegular() {
		return nil
	}
	src, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer src.Close()
	if err := tw.WriteHeader(&tar.Header{Name: rel, Mode: int64(fi.Mode().Perm()), Size: fi.Size(), ModTime: fi.ModTime(), Typeflag: tar.TypeReg}); err != nil {
		return err
	}
	_, err = io.Copy(tw, src)
	return err
}

// ReadManifest returns an archive's manifest.
func ReadManifest(archive string) (Manifest, error) {
	var m Manifest
	err := walk(archive, func(h *tar.Header, r io.Reader) error {
		if h.Name == manifestName {
			if err := json.NewDecoder(r).Decode(&m); err != nil {
				return err
			}
			return errStop
		}
		return nil
	})
	if errors.Is(err, errStop) {
		return m, nil
	}
	if err == nil {
		err = errors.New("not an AnoShell backup (no manifest)")
	}
	return m, err
}

var errStop = errors.New("stop")

func walk(archive string, fn func(*tar.Header, io.Reader) error) error {
	f, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer f.Close()
	gz, err := gzip.NewReader(f)
	if err != nil {
		return err
	}
	tr := tar.NewReader(gz)
	for {
		h, err := tr.Next()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
		if err := fn(h, tr); err != nil {
			return err
		}
	}
}

// safeRel rejects absolute paths, `..` and anything not already clean.
func safeRel(name string) bool {
	if name == "" || filepath.IsAbs(name) || strings.Contains(name, "\\") {
		return false
	}
	c := filepath.ToSlash(filepath.Clean(name))
	return c == name && c != "." && c != ".." && !strings.HasPrefix(c, "../")
}

// Restore extracts the archive's files that belong to cats into home. The
// files it would replace are first saved to snapshot (skipped when "" or on a
// dry run). It returns the paths written (or that would be written).
func Restore(home, archive string, cats []Category, snapshot string, dryRun bool, now time.Time) ([]string, error) {
	var picked []string
	err := walk(archive, func(h *tar.Header, _ io.Reader) error {
		if h.Name == manifestName || h.Typeflag != tar.TypeReg || !safeRel(h.Name) {
			return nil
		}
		for _, c := range cats {
			if c.owns(h.Name) {
				picked = append(picked, h.Name)
				break
			}
		}
		return nil
	})
	if err != nil || dryRun || len(picked) == 0 {
		return picked, err
	}
	if snapshot != "" {
		if _, err := Create(home, snapshot, cats, now); err != nil {
			return nil, fmt.Errorf("snapshot before restore: %w", err)
		}
	}
	want := map[string]bool{}
	for _, p := range picked {
		want[p] = true
	}
	err = walk(archive, func(h *tar.Header, r io.Reader) error {
		if !want[h.Name] {
			return nil
		}
		return writeFile(home, h.Name, os.FileMode(h.Mode).Perm(), r)
	})
	return picked, err
}

// within reports whether path resolves (through any symlinks in its existing
// part) to somewhere inside home.
func within(home, path string) bool {
	realHome, err := filepath.EvalSymlinks(home)
	if err != nil {
		return false
	}
	p := path
	for {
		if r, err := filepath.EvalSymlinks(p); err == nil {
			rest, _ := filepath.Rel(p, path)
			r = filepath.Join(r, rest)
			return r == realHome || strings.HasPrefix(r, realHome+string(filepath.Separator))
		}
		parent := filepath.Dir(p)
		if parent == p {
			return false
		}
		p = parent
	}
}

// writeFile writes home/rel atomically. Symlinked directories are followed
// only while they stay inside home (stow-style dotfiles); a symlink at the
// file itself is never overwritten.
func writeFile(home, rel string, mode os.FileMode, r io.Reader) error {
	dst := filepath.Join(home, rel)
	dir := filepath.Dir(dst)
	if !within(home, dir) {
		return fmt.Errorf("refusing to restore %s: it resolves outside %s", rel, home)
	}
	if fi, err := os.Lstat(dst); err == nil && fi.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("refusing to overwrite symlink %s", dst)
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".restore-*")
	if err != nil {
		return err
	}
	if _, err := io.Copy(tmp, r); err != nil {
		tmp.Close()
		os.Remove(tmp.Name())
		return err
	}
	tmp.Close()
	if err := os.Chmod(tmp.Name(), mode); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return os.Rename(tmp.Name(), dst)
}

// DefaultDir is where backups go unless told otherwise.
func DefaultDir(home string) string {
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		return filepath.Join(d, "anoshell", "backups")
	}
	return filepath.Join(home, ".local", "share", "anoshell", "backups")
}
