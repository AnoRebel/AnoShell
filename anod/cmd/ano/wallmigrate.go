package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	"ano/anod/internal/config"
)

// rotatorLine matches a compositor autostart of the old randomize scripts and
// captures its folder and optional interval.
var rotatorLine = regexp.MustCompile(`awww_randomize(?:_multi)?\.sh\s+([^\s"')]+)(?:\s+(\d+))?`)

// rotatorEdit is one autostart line to disable.
type rotatorEdit struct {
	File     string
	Line     int
	Text     string
	Dir      string
	Interval int
}

// findRotatorAutostarts scans the user's Hyprland and niri configs.
func findRotatorAutostarts(home string) []rotatorEdit {
	files := []string{}
	for _, g := range []string{".config/hypr/*.lua", ".config/hypr/*.conf", ".config/hypr/**/*.lua", ".config/niri/*.kdl"} {
		m, _ := filepath.Glob(filepath.Join(home, g))
		files = append(files, m...)
	}
	var out []rotatorEdit
	seen := map[string]bool{}
	for _, f := range files {
		if seen[f] {
			continue
		}
		seen[f] = true
		fh, err := os.Open(f)
		if err != nil {
			continue
		}
		sc := bufio.NewScanner(fh)
		for n := 1; sc.Scan(); n++ {
			t := sc.Text()
			trim := strings.TrimSpace(t)
			if strings.HasPrefix(trim, "--") || strings.HasPrefix(trim, "//") || strings.HasPrefix(trim, "#") {
				continue
			}
			if m := rotatorLine.FindStringSubmatch(t); m != nil {
				e := rotatorEdit{File: f, Line: n, Text: t, Dir: m[1], Interval: 300}
				if m[2] != "" {
					e.Interval, _ = strconv.Atoi(m[2])
				}
				out = append(out, e)
			}
		}
		if err := sc.Err(); err != nil {
			fmt.Fprintf(os.Stderr, "ano: reading %s: %v\n", f, err)
		}
		fh.Close()
	}
	return out
}

// applyRotatorMigration backs up and comments out each line, enables anod's
// rotation with the same folder/interval, and returns the backups made.
func applyRotatorMigration(edits []rotatorEdit, userConfig string, now time.Time) ([]string, error) {
	var backups []string
	byFile := map[string][]rotatorEdit{}
	for _, e := range edits {
		byFile[e.File] = append(byFile[e.File], e)
	}
	stamp := now.Format("20060102-150405")
	for f, es := range byFile {
		b, err := os.ReadFile(f)
		if err != nil {
			return backups, err
		}
		bak := f + ".bak-" + stamp
		if err := os.WriteFile(bak, b, 0o644); err != nil {
			return backups, err
		}
		backups = append(backups, bak)
		lines := strings.Split(string(b), "\n")
		comment := "-- "
		if strings.HasSuffix(f, ".kdl") {
			comment = "// "
		} else if strings.HasSuffix(f, ".conf") {
			comment = "# "
		}
		for _, e := range es {
			i := e.Line - 1
			if i < len(lines) && lines[i] == e.Text {
				indent := lines[i][:len(lines[i])-len(strings.TrimLeft(lines[i], " \t"))]
				lines[i] = indent + comment + "(anod rotates wallpapers now) " + strings.TrimLeft(lines[i], " \t")
			}
		}
		if err := os.WriteFile(f, []byte(strings.Join(lines, "\n")), 0o644); err != nil {
			return backups, err
		}
	}
	// Turn on anod's rotation with the first script's folder and interval.
	m := map[string]any{}
	if b, err := os.ReadFile(userConfig); err == nil {
		if err := json.Unmarshal(b, &m); err != nil {
			return backups, fmt.Errorf("%s: %w", userConfig, err)
		}
		bak := userConfig + ".bak-" + stamp
		if err := os.WriteFile(bak, b, 0o644); err != nil {
			return backups, err
		}
		backups = append(backups, bak)
	}
	bg, _ := m["background"].(map[string]any)
	if bg == nil {
		bg = map[string]any{}
	}
	bg["randomize"] = map[string]any{"enable": true, "directory": edits[0].Dir, "interval": edits[0].Interval}
	m["background"] = bg
	b, _ := json.MarshalIndent(m, "", "  ")
	if err := os.MkdirAll(filepath.Dir(userConfig), 0o755); err != nil {
		return backups, err
	}
	return backups, os.WriteFile(userConfig, append(b, '\n'), 0o644)
}

// stopRotators ends running copies of the old scripts (by PID; never ours).
func stopRotators() int {
	n := 0
	dirs, _ := filepath.Glob("/proc/[0-9]*/cmdline")
	for _, p := range dirs {
		b, err := os.ReadFile(p)
		if err != nil || !strings.Contains(string(b), "awww_randomize") {
			continue
		}
		pid, err := strconv.Atoi(filepath.Base(filepath.Dir(p)))
		if err != nil || pid == os.Getpid() {
			continue
		}
		if syscall.Kill(pid, syscall.SIGTERM) == nil {
			n++
		}
	}
	return n
}

// wallpaperMigrate: `ano wallpaper migrate [--yes] [--dry-run]`.
func wallpaperMigrate(args []string) int {
	yes, dry := false, false
	for _, a := range args {
		switch a {
		case "--yes", "-y":
			yes = true
		case "--dry-run":
			dry = true
		}
	}
	home, _ := os.UserHomeDir()
	edits := findRotatorAutostarts(home)
	if len(edits) == 0 {
		fmt.Println("No awww randomize autostart found in your Hyprland or niri config.")
		return 0
	}
	fmt.Println("These start a wallpaper rotator that fights anod's rotation:")
	for _, e := range edits {
		fmt.Printf("  %s:%d  %s\n", e.File, e.Line, strings.TrimSpace(e.Text))
	}
	fmt.Printf("\nanod will rotate %s every %ds instead (background.randomize), with colours and hooks.\n", edits[0].Dir, edits[0].Interval)
	fmt.Println("Each file is backed up first; the lines are commented out, not deleted.")
	if dry {
		fmt.Println("\nDry run: nothing changed.")
		return 0
	}
	if !yes {
		fmt.Print("\nProceed? [y/N] ")
		var ans string
		fmt.Scanln(&ans)
		if a := strings.ToLower(strings.TrimSpace(ans)); a != "y" && a != "yes" {
			fmt.Println("Nothing changed.")
			return 1
		}
	}
	backups, err := applyRotatorMigration(edits, config.UserPath(), time.Now())
	for _, b := range backups {
		fmt.Println("backup:", b)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano wallpaper migrate:", err)
		return 1
	}
	fmt.Printf("Stopped %d running copy(ies) of the old rotator.\n", stopRotators())
	fmt.Println("Done. anod's rotation is on; `ano wallpaper next` changes it now.")
	return 0
}
