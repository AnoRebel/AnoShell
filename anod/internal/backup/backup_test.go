package backup

import (
	"archive/tar"
	"compress/gzip"
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"
)

func put(t *testing.T, home, rel, body string, mode os.FileMode) {
	t.Helper()
	p := filepath.Join(home, rel)
	os.MkdirAll(filepath.Dir(p), 0o755)
	if err := os.WriteFile(p, []byte(body), mode); err != nil {
		t.Fatal(err)
	}
}

func read(_ *testing.T, home, rel string) string {
	b, _ := os.ReadFile(filepath.Join(home, rel))
	return string(b)
}

func TestRoundTripPerCategory(t *testing.T) {
	src, dst := t.TempDir(), t.TempDir()
	put(t, src, ".config/anoshell/config.json", `{"a":1}`, 0o644)
	put(t, src, ".config/anoshell/themes/x.json", `theme`, 0o644)
	put(t, src, ".local/share/anoshell/secrets/ai-keys.json", `key`, 0o600)
	put(t, src, ".local/share/anoshell/notes.json", `notes`, 0o644)
	arc := filepath.Join(t.TempDir(), "b.tar.gz")
	now := time.Unix(0, 0)

	// Defaults never include secrets, and data excludes the secrets dir.
	cats, _ := Lookup(nil)
	m, err := Create(src, arc, cats, now)
	if err != nil || m.Files != 3 || slices.Contains(m.Categories, "secrets") {
		t.Fatalf("create: %+v %v", m, err)
	}
	if got, _ := ReadManifest(arc); got.Files != 3 {
		t.Fatalf("manifest: %+v", got)
	}

	// Restoring only themes writes only the theme.
	themes, _ := Lookup([]string{"themes"})
	got, err := Restore(dst, arc, themes, "", false, now)
	if err != nil || len(got) != 1 || read(t, dst, ".config/anoshell/themes/x.json") != "theme" || read(t, dst, ".config/anoshell/config.json") != "" {
		t.Fatalf("restore themes: %v %v", got, err)
	}

	// A restore snapshots what it replaces first.
	put(t, dst, ".config/anoshell/config.json", `{"old":true}`, 0o644)
	snap := filepath.Join(t.TempDir(), "snap.tar.gz")
	config, _ := Lookup([]string{"config"})
	if _, err := Restore(dst, arc, config, snap, false, now); err != nil {
		t.Fatal(err)
	}
	if read(t, dst, ".config/anoshell/config.json") != `{"a":1}` {
		t.Fatal("config not restored")
	}
	back := t.TempDir()
	Restore(back, snap, config, "", false, now)
	if read(t, back, ".config/anoshell/config.json") != `{"old":true}` {
		t.Fatal("snapshot did not hold the replaced file")
	}
}

func TestSecretsKeepMode(t *testing.T) {
	src, dst := t.TempDir(), t.TempDir()
	put(t, src, ".local/share/anoshell/secrets/ai-keys.json", `key`, 0o600)
	arc := filepath.Join(t.TempDir(), "b.tar.gz")
	sec, _ := Lookup([]string{"secrets"})
	Create(src, arc, sec, time.Now())
	Restore(dst, arc, sec, "", false, time.Now())
	fi, err := os.Stat(filepath.Join(dst, ".local/share/anoshell/secrets/ai-keys.json"))
	if err != nil || fi.Mode().Perm() != 0o600 {
		t.Fatalf("secret mode: %v %v", fi, err)
	}
}

// A crafted archive cannot write outside home or through a symlink.
func TestRestoreRejectsUnsafePaths(t *testing.T) {
	home := t.TempDir()
	outside := t.TempDir()
	os.MkdirAll(filepath.Join(home, ".config"), 0o755)
	os.Symlink(outside, filepath.Join(home, ".config/anoshell"))
	arc := filepath.Join(t.TempDir(), "evil.tar.gz")
	f, _ := os.Create(arc)
	gz := gzip.NewWriter(f)
	tw := tar.NewWriter(gz)
	for _, n := range []string{"../escape", "/etc/evil", ".config/anoshell/config.json"} {
		tw.WriteHeader(&tar.Header{Name: n, Mode: 0o644, Size: 1, Typeflag: tar.TypeReg})
		tw.Write([]byte("x"))
	}
	tw.Close()
	gz.Close()
	f.Close()

	all := Categories
	if _, err := Restore(home, arc, all, "", true, time.Now()); err == nil {
		t.Fatal("a dry run must refuse what the restore would refuse")
	}
	_, err := Restore(home, arc, all, "", false, time.Now())
	if err == nil {
		t.Fatal("want an error restoring through a symlink")
	}
	if _, e := os.Stat(filepath.Join(outside, "config.json")); e == nil {
		t.Fatal("wrote through the symlink")
	}
	if _, e := os.Stat(filepath.Join(filepath.Dir(home), "escape")); e == nil {
		t.Fatal("wrote outside home")
	}
}

func TestSafeRel(t *testing.T) {
	for name, want := range map[string]bool{
		".config/anoshell/config.json": true, "../x": false, "/abs": false,
		"a/../b": false, "./a": false, "": false, "a//b": false,
	} {
		if SafeRel(name) != want {
			t.Errorf("safeRel(%q) = %v", name, !want)
		}
	}
}

// Stow-style: a category root symlinked to a dotfiles dir inside home is
// backed up and restored through the link.
func TestSymlinkedRootInsideHome(t *testing.T) {
	home := t.TempDir()
	put(t, home, "dotfiles/hypr/hyprland.lua", "lua", 0o644)
	os.MkdirAll(filepath.Join(home, ".config"), 0o755)
	os.Symlink(filepath.Join(home, "dotfiles/hypr"), filepath.Join(home, ".config/hypr"))
	arc := filepath.Join(t.TempDir(), "b.tar.gz")
	comp, _ := Lookup([]string{"compositor"})
	if m, err := Create(home, arc, comp, time.Now()); err != nil || m.Files != 1 {
		t.Fatalf("create through symlinked root: %+v %v", m, err)
	}
	put(t, home, "dotfiles/hypr/hyprland.lua", "changed", 0o644)
	if _, err := Restore(home, arc, comp, "", false, time.Now()); err != nil {
		t.Fatal(err)
	}
	if read(t, home, "dotfiles/hypr/hyprland.lua") != "lua" {
		t.Fatal("restore did not write through the in-home symlink")
	}
}

// One refused destination stops the restore before anything is written.
func TestRestoreIsAllOrNothing(t *testing.T) {
	src, dst := t.TempDir(), t.TempDir()
	put(t, src, ".config/anoshell/config.json", "new", 0o644)
	put(t, src, ".config/anoshell/themes/x.json", "theme", 0o644)
	arc := filepath.Join(t.TempDir(), "b.tar.gz")
	cats, _ := Lookup([]string{"config", "themes"})
	Create(src, arc, cats, time.Now())
	put(t, dst, "elsewhere.json", "target", 0o644)
	os.MkdirAll(filepath.Join(dst, ".config/anoshell"), 0o755)
	os.Symlink(filepath.Join(dst, "elsewhere.json"), filepath.Join(dst, ".config/anoshell/config.json"))
	got, err := Restore(dst, arc, cats, "", false, time.Now())
	if err == nil || len(got) != 0 {
		t.Fatalf("want a refusal with nothing written, got %v %v", got, err)
	}
	if _, e := os.Stat(filepath.Join(dst, ".config/anoshell/themes/x.json")); e == nil {
		t.Fatal("a file was written before the refusal")
	}
}
