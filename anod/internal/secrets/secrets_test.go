package secrets

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSetModesAndRoundTrip(t *testing.T) {
	data := t.TempDir()
	t.Setenv("XDG_DATA_HOME", data)
	dir := filepath.Join(data, "anoshell", "secrets")
	// A directory someone made too loose is tightened.
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	os.Chmod(dir, 0o755)

	if err := Set("wallhaven", "  abc123\n"); err != nil {
		t.Fatal(err)
	}
	fi, err := os.Stat(filepath.Join(dir, "wallhaven"))
	if err != nil {
		t.Fatal(err)
	}
	if got := fi.Mode().Perm(); got != 0o600 {
		t.Errorf("file mode = %o, want 600", got)
	}
	di, _ := os.Stat(dir)
	if got := di.Mode().Perm(); got != 0o700 {
		t.Errorf("dir mode = %o, want 700", got)
	}
	if v, err := Get("wallhaven"); err != nil || v != "abc123" {
		t.Errorf("Get = %q, %v", v, err)
	}
	// Overwrite keeps 0600 and leaves no temp files behind.
	if err := Set("wallhaven", "xyz"); err != nil {
		t.Fatal(err)
	}
	ents, _ := os.ReadDir(dir)
	if len(ents) != 1 {
		t.Errorf("dir has %d entries, want 1 (temp file left?)", len(ents))
	}
	fi, _ = os.Stat(filepath.Join(dir, "wallhaven"))
	if got := fi.Mode().Perm(); got != 0o600 {
		t.Errorf("file mode after overwrite = %o, want 600", got)
	}
	// Empty removes.
	if err := Set("wallhaven", ""); err != nil {
		t.Fatal(err)
	}
	if v, err := Get("wallhaven"); err != nil || v != "" {
		t.Errorf("after clear Get = %q, %v", v, err)
	}
}

func TestFreshDirIs0700(t *testing.T) {
	data := t.TempDir()
	t.Setenv("XDG_DATA_HOME", data)
	if err := Set("k", "v"); err != nil {
		t.Fatal(err)
	}
	di, _ := os.Stat(filepath.Join(data, "anoshell", "secrets"))
	if got := di.Mode().Perm(); got != 0o700 {
		t.Errorf("dir mode = %o, want 700", got)
	}
}

func TestBadNames(t *testing.T) {
	t.Setenv("XDG_DATA_HOME", t.TempDir())
	for _, n := range []string{"", "../x", "a/b", "Wallhaven", "a.b", "a b"} {
		if err := Set(n, "v"); err == nil {
			t.Errorf("Set(%q) accepted", n)
		}
	}
}
