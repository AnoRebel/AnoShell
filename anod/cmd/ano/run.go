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
	Command string `json:"command"`
	Name    string `json:"name"`
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

func runCmd(args []string) int {
	print := len(args) > 0 && args[0] == "--print"
	if print {
		args = args[1:]
	}
	if len(args) == 0 || runKinds[args[0]] == "" {
		fmt.Fprintln(os.Stderr, "usage: ano run [--print] terminal|browser|files [args…]")
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
	argv = append(argv, args[1:]...)
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
