package gtkcss

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var colors = map[string]string{"primary": "#aabbcc", "on_primary": "#001122", "surface": "#111111", "on_surface": "#eeeeee"}

func read(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// The user's rules survive apply, re-apply and remove.
func TestUserRulesKept(t *testing.T) {
	dir := t.TempDir()
	css := filepath.Join(dir, "gtk.css")
	own := "window { border: 1px solid red; }\n"
	os.WriteFile(css, []byte(own), 0o644)
	for range 2 {
		if err := Apply(dir, Block(colors, true)); err != nil {
			t.Fatal(err)
		}
	}
	got := read(t, css)
	if !strings.HasPrefix(got, own) || strings.Count(got, begin) != 1 || !strings.Contains(got, "--accent-bg-color: #aabbcc;") {
		t.Fatalf("after apply:\n%s", got)
	}
	if err := Remove(dir); err != nil {
		t.Fatal(err)
	}
	if got := read(t, css); got != own {
		t.Fatalf("after remove: %q", got)
	}
}

// A linked theme file is imported, and the link comes back on remove.
func TestSymlinkImportedAndRestored(t *testing.T) {
	dir, theme := t.TempDir(), t.TempDir()
	target := filepath.Join(theme, "gtk.css")
	os.WriteFile(target, []byte("@define-color accent_color #ff0000;\n"), 0o644)
	css := filepath.Join(dir, "gtk.css")
	os.Symlink(target, css)
	if err := Apply(dir, Block(colors, true)); err != nil {
		t.Fatal(err)
	}
	if fi, _ := os.Lstat(css); fi.Mode()&os.ModeSymlink != 0 {
		t.Fatal("still a link")
	}
	if got := read(t, css); !strings.Contains(got, `@import url("file://`+target+`");`) {
		t.Fatalf("no import:\n%s", got)
	}
	if read(t, target) != "@define-color accent_color #ff0000;\n" {
		t.Fatal("theme file changed")
	}
	if err := Remove(dir); err != nil {
		t.Fatal(err)
	}
	if l, err := os.Readlink(css); err != nil || l != target {
		t.Fatalf("link not restored: %q %v", l, err)
	}
}

// iNiR's generated file is backed up and replaced; GTK 3 gets no CSS variables.
func TestInirReplaced(t *testing.T) {
	dir := t.TempDir()
	css := filepath.Join(dir, "gtk.css")
	inirCSS := "/*\n * GTK Colors - Generated with iNiR theming\n */\n@define-color accent_color #B4C7ED;\n"
	os.WriteFile(css, []byte(inirCSS), 0o644)
	if err := Apply(dir, Block(colors, false)); err != nil {
		t.Fatal(err)
	}
	got := read(t, css)
	if strings.Contains(got, "iNiR") || strings.Contains(got, ":root") || !strings.HasPrefix(got, begin) {
		t.Fatalf("after apply:\n%s", got)
	}
	if read(t, css+".ano-backup") != inirCSS {
		t.Fatal("no backup")
	}
	if err := Remove(dir); err != nil {
		t.Fatal(err)
	}
	if read(t, css) != inirCSS {
		t.Fatal("iNiR's file not restored")
	}
	if _, err := os.Stat(css + ".ano-backup"); !os.IsNotExist(err) {
		t.Fatal("backup left behind")
	}
}
