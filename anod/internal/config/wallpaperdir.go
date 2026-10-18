package config

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
)

// PicturesDir is XDG_PICTURES_DIR from user-dirs.dirs (what the shell's
// StandardPaths reads too), or ~/Pictures.
func PicturesDir() string {
	home, _ := os.UserHomeDir()
	if f, err := os.Open(filepath.Join(configHome(), "user-dirs.dirs")); err == nil {
		defer f.Close()
		sc := bufio.NewScanner(f)
		for sc.Scan() {
			v, ok := strings.CutPrefix(strings.TrimSpace(sc.Text()), "XDG_PICTURES_DIR=")
			if !ok {
				continue
			}
			v = strings.Trim(v, `"`)
			v = strings.Replace(v, "$HOME", home, 1)
			if filepath.IsAbs(v) && filepath.Clean(v) != filepath.Clean(home) {
				return v
			}
		}
	}
	return filepath.Join(home, "Pictures")
}

// WallpaperDir is the wallpaper folder: background.wallpaperDir, or
// <Pictures>/Wallpapers when unset. "~" is expanded.
func WallpaperDir(m map[string]any) string {
	d := strings.TrimRight(strings.TrimSpace(String(m, "background.wallpaperDir", "")), "/")
	if d == "" {
		return filepath.Join(PicturesDir(), "Wallpapers")
	}
	if d == "~" || strings.HasPrefix(d, "~/") {
		home, _ := os.UserHomeDir()
		d = filepath.Join(home, strings.TrimPrefix(d, "~"))
	}
	return d
}

// RotationDir is background.randomize.directory, or the wallpaper folder.
func RotationDir(m map[string]any) string {
	if d := strings.TrimSpace(String(m, "background.randomize.directory", "")); d != "" {
		return d
	}
	return WallpaperDir(m)
}
