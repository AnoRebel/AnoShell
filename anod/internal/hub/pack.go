package hub

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// PackOptions fill in what the item's manifest doesn't say.
type PackOptions struct {
	Type, ID, Version, URLBase, OutDir string
}

// Pack archives an item (a folder for widgets/rices, a file for the other
// types) in the catalog archive format, checks the result installs, and
// returns the archive path and its index entry.
func Pack(src string, o PackOptions) (string, Entry, error) {
	fi, err := os.Stat(src)
	if err != nil {
		return "", Entry{}, err
	}
	var m meta
	var mid string
	if fi.IsDir() {
		for _, mf := range []string{"widget.json", "plugin.json", "lockscreen.json", "rice.json"} {
			p := filepath.Join(src, mf)
			if fileExists(p) {
				m, mid = readMeta(p, ""), readManifestID(p)
				if o.Type == "" {
					o.Type = map[string]string{"widget.json": "widgets", "plugin.json": "plugins", "lockscreen.json": "lockscreens", "rice.json": "rices"}[mf]
				}
				break
			}
		}
		if mid == "" {
			mid, _ = StripSeq(filepath.Base(filepath.Clean(src)))
		}
	} else {
		mid = strings.TrimSuffix(filepath.Base(src), filepath.Ext(src))
		if strings.HasSuffix(src, ".json") {
			m = readMeta(src, "_meta") // a theme
			if m.Name == "" {
				m = readMeta(src, "") // a look
			}
		} else if isImage(src) && o.Type == "" {
			o.Type = "wallpapers"
		}
	}
	if o.ID == "" {
		o.ID = mid
	}
	if o.Version == "" {
		o.Version = m.Version
	}
	switch {
	case checkType(o.Type) != nil:
		return "", Entry{}, fmt.Errorf("--type: %v", checkType(o.Type))
	case !ValidID(o.ID):
		return "", Entry{}, fmt.Errorf("id %q must match ^[a-z0-9-]+$ (pass --id)", o.ID)
	case o.Version == "":
		return "", Entry{}, errors.New("no version in the manifest (pass --version)")
	case fi.IsDir() != !singleFile(o.Type):
		return "", Entry{}, fmt.Errorf("%s are packed from a %s", o.Type, map[bool]string{true: "file", false: "folder"}[singleFile(o.Type)])
	}

	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	add := func(name, path string) error {
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if err := tw.WriteHeader(&tar.Header{Name: name, Mode: 0o644, Size: int64(len(b)), Typeflag: tar.TypeReg}); err != nil {
			return err
		}
		_, err = tw.Write(b)
		return err
	}
	if fi.IsDir() {
		var files []string
		err := filepath.WalkDir(src, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() {
				if d.Name() == ".git" {
					return filepath.SkipDir
				}
				return nil
			}
			if !d.Type().IsRegular() {
				return fmt.Errorf("%s: only regular files can be packed (no symlinks)", p)
			}
			rel, _ := filepath.Rel(src, p)
			files = append(files, filepath.ToSlash(rel))
			return nil
		})
		if err != nil {
			return "", Entry{}, err
		}
		sort.Strings(files)
		for _, f := range files {
			if err := add(f, filepath.Join(src, filepath.FromSlash(f))); err != nil {
				return "", Entry{}, err
			}
		}
	} else {
		name := o.ID + strings.ToLower(filepath.Ext(src))
		if err := add(name, src); err != nil {
			return "", Entry{}, err
		}
	}
	if err := tw.Close(); err != nil {
		return "", Entry{}, err
	}
	if err := gz.Close(); err != nil {
		return "", Entry{}, err
	}

	// The archive must pass the same checks an install runs.
	check, err := os.MkdirTemp("", "anoshell-pack-")
	if err != nil {
		return "", Entry{}, err
	}
	defer os.RemoveAll(check)
	if _, err := extract(buf.Bytes(), o.Type, o.ID, filepath.Join(check, "x")); err != nil {
		return "", Entry{}, fmt.Errorf("the packed archive would be refused: %v", err)
	}
	if buf.Len() > MaxDownload && o.Type != "wallpapers" || buf.Len() > MaxWallpaperDownload {
		return "", Entry{}, errors.New("the archive is over the download size cap")
	}

	out := filepath.Join(o.OutDir, fmt.Sprintf("%s-%s.tar.gz", o.ID, o.Version))
	if err := os.WriteFile(out, buf.Bytes(), 0o644); err != nil {
		return "", Entry{}, err
	}
	sum := sha256.Sum256(buf.Bytes())
	e := Entry{ID: o.ID, Type: o.Type, Name: m.Name, Version: o.Version, Author: m.Author, Licence: m.Licence, Description: m.Description,
		SHA256: hex.EncodeToString(sum[:]), URL: filepath.Base(out)}
	if o.URLBase != "" {
		e.URL = strings.TrimRight(o.URLBase, "/") + "/" + e.URL
	}
	if e.Name == "" {
		e.Name = o.ID
	}
	if strings.HasPrefix(m.Preview, "https://") {
		e.Preview = m.Preview
	}
	return out, e, nil
}
