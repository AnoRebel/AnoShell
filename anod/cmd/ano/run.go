package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"

	"ano/anod/internal/config"
)

// runKinds maps `ano run <kind>` to its apps.* key.
var runKinds = map[string]string{"terminal": "terminal", "browser": "browser", "files": "fileManager"}

type appEntry struct {
	Command string   `json:"command"`
	Name    string   `json:"name"`
	Exec    []string `json:"exec"` // terminals: what goes before a command to run in it
}

// terminalArgs turns `-e cmd…` into what the chosen terminal takes (kitty and
// foot: the command alone; wezterm: start --; gnome-terminal: --). Terminals
// not in the catalogue keep -e.
func terminalArgs(term string, args []string, catalog map[string][]appEntry) []string {
	if len(args) == 0 || args[0] != "-e" {
		return args
	}
	for _, a := range catalog["terminal"] {
		if a.Command == filepath.Base(term) && a.Exec != nil {
			return append(append([]string{}, a.Exec...), args[1:]...)
		}
	}
	return args
}

// loadCatalog reads assets/default-apps.json (the preference order per key).
func loadCatalog(dir string) (map[string][]appEntry, error) {
	b, err := os.ReadFile(filepath.Join(dir, "assets", "default-apps.json"))
	if err != nil {
		return nil, err
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(b, &raw); err != nil {
		return nil, err
	}
	out := map[string][]appEntry{}
	for k, v := range raw {
		var list []appEntry
		if json.Unmarshal(v, &list) == nil {
			out[k] = list
		}
	}
	return out, nil
}

// resolveApp is the command line for an apps.* key: the configured one when its
// program is installed, else the first installed app in the catalogue's order.
func resolveApp(key, configured string, catalog map[string][]appEntry, look func(string) bool) ([]string, error) {
	if f := strings.Fields(configured); len(f) > 0 && look(f[0]) {
		return f, nil
	}
	for _, a := range catalog[key] {
		if look(a.Command) {
			return []string{a.Command}, nil
		}
	}
	if configured != "" {
		return nil, fmt.Errorf("%s %q is not installed, and none of the usual ones are", key, configured)
	}
	return nil, fmt.Errorf("no %s installed", key)
}

// launcherArgv is the launcher Super+R opens (apps.launcher): AnoShell's own
// search, or apps.launcherCommand (~ and $VARS expanded, split on spaces, run
// without a shell). An empty custom command falls back to AnoShell's.
func launcherArgv(m map[string]any) []string {
	cmd := strings.TrimSpace(config.String(m, "apps.launcherCommand", ""))
	if config.String(m, "apps.launcher", "anoshell") != "custom" || cmd == "" {
		return []string{"qs", "-c", "ano", "ipc", "call", "search", "toggle"}
	}
	home, _ := os.UserHomeDir()
	f := strings.Fields(cmd)
	for i, a := range f {
		if a == "~" || strings.HasPrefix(a, "~/") {
			a = home + a[1:]
		}
		f[i] = os.ExpandEnv(a)
	}
	return f
}

func runCmd(args []string) int {
	print := len(args) > 0 && args[0] == "--print"
	if print {
		args = args[1:]
	}
	if len(args) > 0 && args[0] == "launcher" {
		m, err := config.Effective()
		if err != nil {
			m = map[string]any{}
		}
		argv := launcherArgv(m)
		if print {
			fmt.Println(strings.Join(argv, " "))
			return 0
		}
		c := exec.Command(argv[0], argv[1:]...)
		c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
		if err := c.Start(); err != nil {
			fmt.Fprintln(os.Stderr, "ano: launcher:", err)
			return 1
		}
		return 0
	}
	if len(args) == 0 || runKinds[args[0]] == "" {
		fmt.Fprintln(os.Stderr, "usage: ano run [--print] terminal|browser|files|launcher [args…]")
		return 2
	}
	key := runKinds[args[0]]
	m, err := config.Effective()
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano:", err)
		m = map[string]any{}
	}
	catalog, err := loadCatalog(config.ShellDir())
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano: default-app catalogue:", err)
	}
	argv, err := resolveApp(key, config.String(m, "apps."+key, ""), catalog, have)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano:", err)
		return 1
	}
	extra := args[1:]
	if key == "terminal" {
		extra = terminalArgs(argv[0], extra, catalog)
	}
	argv = append(argv, extra...)
	if print {
		fmt.Println(strings.Join(argv, " "))
		return 0
	}
	path, err := exec.LookPath(argv[0])
	if err == nil {
		err = syscall.Exec(path, argv, os.Environ()) // the app replaces ano: binds spawn it directly
	}
	fmt.Fprintln(os.Stderr, "ano:", err)
	return 1
}
