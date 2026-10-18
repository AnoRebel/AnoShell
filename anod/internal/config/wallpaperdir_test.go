package config

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWallpaperDir(t *testing.T) {
	cfg := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", cfg)
	home, _ := os.UserHomeDir()
	if got := WallpaperDir(map[string]any{}); got != filepath.Join(home, "Pictures", "Wallpapers") {
		t.Errorf("default without user-dirs = %q", got)
	}
	os.WriteFile(filepath.Join(cfg, "user-dirs.dirs"), []byte("XDG_PICTURES_DIR=\"$HOME/Bilder\"\n"), 0o644)
	if got := WallpaperDir(map[string]any{}); got != filepath.Join(home, "Bilder", "Wallpapers") {
		t.Errorf("default with user-dirs = %q", got)
	}
	m := map[string]any{"background": map[string]any{"wallpaperDir": "~/walls/"}}
	if got := WallpaperDir(m); got != filepath.Join(home, "walls") {
		t.Errorf("set = %q", got)
	}
	if got := RotationDir(m); got != filepath.Join(home, "walls") {
		t.Errorf("rotation falls back = %q", got)
	}
	m["background"].(map[string]any)["randomize"] = map[string]any{"directory": "/srv/rot"}
	if got := RotationDir(m); got != "/srv/rot" {
		t.Errorf("rotation own = %q", got)
	}
}
