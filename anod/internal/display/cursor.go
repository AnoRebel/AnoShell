package display

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Cursor is the pointer theme and size (spec: Cursor theme and size).
type Cursor struct {
	Theme string `json:"theme"`
	Size  int    `json:"size"`
}

// CursorTheme is an installed theme (a directory with cursors/ in an icon path).
type CursorTheme struct {
	Name  string `json:"name"`  // directory name (what XCURSOR_THEME takes)
	Title string `json:"title"` // index.theme Name=, else the directory name
	Path  string `json:"path"`
}

// IconDirs are searched in XCursor's order: user dirs first.
func IconDirs() []string {
	home, _ := os.UserHomeDir()
	data := os.Getenv("XDG_DATA_HOME")
	if data == "" {
		data = filepath.Join(home, ".local", "share")
	}
	dirs := []string{filepath.Join(home, ".icons"), filepath.Join(data, "icons")}
	sys := os.Getenv("XDG_DATA_DIRS")
	if sys == "" {
		sys = "/usr/local/share:/usr/share"
	}
	for _, d := range strings.Split(sys, ":") {
		if d != "" {
			dirs = append(dirs, filepath.Join(d, "icons"))
		}
	}
	return append(dirs, "/usr/share/pixmaps")
}

var nameRE = regexp.MustCompile(`(?m)^Name\s*=\s*(.+)$`)

// CursorThemes lists installed cursor themes (first one wins per name).
func CursorThemes(dirs []string) []CursorTheme {
	seen := map[string]bool{}
	var out []CursorTheme
	for _, d := range dirs {
		ents, _ := os.ReadDir(d)
		for _, e := range ents {
			p := filepath.Join(d, e.Name())
			if seen[e.Name()] {
				continue
			}
			if fi, err := os.Stat(filepath.Join(p, "cursors")); err != nil || !fi.IsDir() {
				continue
			}
			seen[e.Name()] = true
			t := CursorTheme{Name: e.Name(), Title: e.Name(), Path: p}
			if b, err := os.ReadFile(filepath.Join(p, "index.theme")); err == nil {
				if m := nameRE.FindSubmatch(b); m != nil {
					t.Title = strings.TrimSpace(string(m[1]))
				}
			}
			out = append(out, t)
		}
	}
	sort.Slice(out, func(i, j int) bool { return strings.ToLower(out[i].Title) < strings.ToLower(out[j].Title) })
	return out
}

// Preview renders a theme's arrow (cursors/left_ptr, else default) as PNG,
// picking the image nearest to size.
func Preview(themeDir string, size int) ([]byte, error) {
	var data []byte
	var err error
	for _, n := range []string{"left_ptr", "default", "arrow"} {
		if data, err = os.ReadFile(filepath.Join(themeDir, "cursors", n)); err == nil {
			break
		}
	}
	if err != nil {
		return nil, err
	}
	img, err := decodeXcursor(data, size)
	if err != nil {
		return nil, err
	}
	var buf bytes.Buffer
	err = png.Encode(&buf, img)
	return buf.Bytes(), err
}

// decodeXcursor reads the image whose nominal size is nearest to want from an
// XCursor file (header "Xcur", a table of chunks; images are 0xfffd0002 with
// premultiplied ARGB pixels, little-endian).
func decodeXcursor(b []byte, want int) (image.Image, error) {
	le := binary.LittleEndian
	if len(b) < 16 || string(b[:4]) != "Xcur" {
		return nil, errors.New("not an XCursor file")
	}
	n := int(le.Uint32(b[12:]))
	best, bestPos := -1, 0
	for i := 0; i < n; i++ {
		o := 16 + i*12
		if o+12 > len(b) {
			break
		}
		if le.Uint32(b[o:]) != 0xfffd0002 {
			continue
		}
		size := int(le.Uint32(b[o+4:]))
		if best < 0 || abs(size-want) < abs(best-want) {
			best, bestPos = size, int(le.Uint32(b[o+8:]))
		}
	}
	if best < 0 || bestPos+36 > len(b) {
		return nil, errors.New("no image in the cursor")
	}
	w, h := int(le.Uint32(b[bestPos+16:])), int(le.Uint32(b[bestPos+20:]))
	px := b[bestPos+36:]
	if w <= 0 || h <= 0 || w > 1024 || h > 1024 || len(px) < w*h*4 {
		return nil, errors.New("bad cursor image")
	}
	img := image.NewNRGBA(image.Rect(0, 0, w, h))
	for i := 0; i < w*h; i++ {
		argb := le.Uint32(px[i*4:])
		a := uint8(argb >> 24)
		c := color.NRGBA{A: a}
		if a > 0 { // un-premultiply
			c.R = uint8(uint32(uint8(argb>>16)) * 255 / uint32(a))
			c.G = uint8(uint32(uint8(argb>>8)) * 255 / uint32(a))
			c.B = uint8(uint32(uint8(argb)) * 255 / uint32(a))
		}
		img.SetNRGBA(i%w, i/w, c)
	}
	return img, nil
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

// ── Applying ──────────────────────────────────────────────────────────

func validCursor(c Cursor) error {
	if c.Theme == "" || strings.ContainsAny(c.Theme, "/\"'\\\n") {
		return fmt.Errorf("bad cursor theme %q", c.Theme)
	}
	if c.Size < 8 || c.Size > 256 {
		return fmt.Errorf("cursor size %d out of range (8–256)", c.Size)
	}
	return nil
}

// SetCursor applies the cursor live (Hyprland: hyprctl setcursor; niri reads
// it from the managed file), exports it for apps (gsettings, GTK
// settings.ini keys that already exist; XCURSOR_* through the managed file
// for apps started later) and persists it.
func (s *Service) SetCursor(c Cursor) error {
	if err := validCursor(c); err != nil {
		return err
	}
	s.mu.Lock()
	s.cursor = &c
	s.mu.Unlock()
	run := s.Exec
	if run == nil {
		run = func(name string, args ...string) error { return exec.Command(name, args...).Run() }
	}
	if s.Backend.Name() == "hyprland" {
		if err := run("hyprctl", "setcursor", c.Theme, strconv.Itoa(c.Size)); err != nil {
			s.logf("hyprctl setcursor: %v", err)
		}
	}
	run("gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", c.Theme)
	run("gsettings", "set", "org.gnome.desktop.interface", "cursor-size", strconv.Itoa(c.Size))
	for _, f := range s.GtkSettings {
		if err := setIniKeys(f, map[string]string{"gtk-cursor-theme-name": c.Theme, "gtk-cursor-theme-size": strconv.Itoa(c.Size)}); err != nil {
			s.logf("%s: %v", f, err)
		}
	}
	cur, err := s.Backend.Current()
	if err != nil {
		return err
	}
	return s.writeManaged(cur)
}

// setIniKeys replaces the values of keys already present (never adds any,
// never rewrites a file that doesn't have them).
func setIniKeys(path string, kv map[string]string) error {
	b, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	var out []string
	changed := false
	sc := bufio.NewScanner(bytes.NewReader(b))
	for sc.Scan() {
		l := sc.Text()
		if k, _, ok := strings.Cut(l, "="); ok {
			if v, ok := kv[strings.TrimSpace(k)]; ok {
				nl := strings.TrimSpace(k) + "=" + v
				if nl != l {
					l, changed = nl, true
				}
			}
		}
		out = append(out, l)
	}
	if !changed {
		return nil
	}
	return writeAtomic(path, strings.Join(out, "\n")+"\n")
}

func hyprCursor(c Cursor) string {
	sz := strconv.Itoa(c.Size)
	return fmt.Sprintf("hl.env(\"XCURSOR_THEME\", %q)\nhl.env(\"XCURSOR_SIZE\", %q)\nhl.env(\"HYPRCURSOR_THEME\", %q)\nhl.env(\"HYPRCURSOR_SIZE\", %q)\n",
		c.Theme, sz, c.Theme, sz)
}

func niriCursor(c Cursor) string {
	return fmt.Sprintf("cursor {\n    xcursor-theme %q\n    xcursor-size %d\n}\n", c.Theme, c.Size)
}
