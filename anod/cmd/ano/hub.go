package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"ano/anod/internal/config"
	"ano/anod/internal/hub"
	"ano/anod/internal/ipc"
)

const hubUsage = `usage: ano hub [themes|looks|widgets|wallpapers|rices]   open Settings on the Hub
       ano hub list [type] [--json]
       ano hub refresh
       ano hub install <type> <id> [--catalog URL] [--yes]
       ano hub remove <type> <id>
       ano hub pack <dir|file> [--type T] [--id ID] [--version V] [--url-base URL] [--out DIR]`

func hubCmd(args []string) int {
	if len(args) == 0 || isHubType(args[0]) {
		tab := ""
		if len(args) > 0 {
			tab = args[0]
		}
		return hubOpen(tab)
	}
	sock := ipc.DefaultSocketPath()
	fail := func(err error) int {
		fmt.Fprintln(os.Stderr, "ano hub:", err)
		return 1
	}
	switch args[0] {
	case "list", "refresh":
		fs := flag.NewFlagSet("hub "+args[0], flag.ExitOnError)
		asJSON := fs.Bool("json", false, "machine-readable output")
		fs.Parse(args[1:])
		req := map[string]any{"type": fs.Arg(0)}
		raw, err := ipc.CallTimeout(sock, "hub."+args[0], req, 2*time.Minute)
		if err != nil {
			return fail(err)
		}
		if *asJSON {
			fmt.Println(string(raw))
			return 0
		}
		var res hub.ListResult
		json.Unmarshal(raw, &res)
		for _, c := range res.Catalogs {
			state := "ok"
			if c.Offline {
				state = "offline (cached): " + c.Error
			} else if !c.OK {
				state = c.Error
			}
			fmt.Printf("catalog  %s  %s\n", c.Name, state)
		}
		for _, it := range res.Items {
			extra := ""
			if it.Update != "" {
				extra += "  update " + it.Update
			}
			if it.Modified {
				extra += "  modified"
			}
			if it.Revoked {
				extra += "  REVOKED"
			}
			fmt.Printf("%-10s %-24s %-9s %s%s\n", it.Type, it.ID, it.Source, it.Version, extra)
		}
		for _, c := range res.Catalog {
			state := "available"
			if c.Installed {
				state = "installed"
			}
			if c.Unavailable != "" {
				state = c.Unavailable
			}
			fmt.Printf("%-10s %-24s %-9s %s  %s (%s)\n", c.Type, c.ID, "catalog", c.Version, state, c.CatalogName)
		}
		return 0
	case "install":
		fs := flag.NewFlagSet("hub install", flag.ExitOnError)
		catalog := fs.String("catalog", "", "the catalog URL (default: the first that lists it)")
		yes := fs.Bool("yes", false, "install code content without asking")
		pos := parseInterleaved(fs, args[1:])
		if len(pos) != 2 {
			fmt.Fprintln(os.Stderr, hubUsage)
			return 2
		}
		raw, err := ipc.CallTimeout(sock, "hub.prepare", map[string]any{"type": pos[0], "id": pos[1], "catalog": *catalog}, 3*time.Minute)
		if err != nil {
			return fail(err)
		}
		var p hub.Prepared
		json.Unmarshal(raw, &p)
		cancel := func() { ipc.Call(sock, "hub.cancel", map[string]any{"token": p.Token}) }
		fmt.Printf("%s %s by %s, from %s\n", p.Name, p.Version, orDash(p.Author), p.CatalogName)
		if len(p.ModifiedFiles) > 0 {
			fmt.Printf("You changed these files since installing; the update replaces them: %s\n", strings.Join(p.ModifiedFiles, ", "))
		}
		ask := len(p.ModifiedFiles) > 0
		if p.Code || p.CapabilitiesChanged {
			ask = true
			fmt.Println("This item contains code that runs with your shell's rights, unsandboxed.")
			fmt.Println("Catalog review is not a security audit.")
			fmt.Printf("Declared hosts: %s\nDeclared commands: %s\n", orDash(strings.Join(p.Hosts, ", ")), orDash(strings.Join(p.Commands, ", ")))
			if p.CapabilitiesChanged {
				fmt.Println("Its declared hosts or commands changed since the installed version.")
			}
			if len(p.Findings) == 0 {
				fmt.Println("Static audit: no findings.")
			}
			for _, f := range p.Findings {
				fmt.Printf("  [%s] %s  %s:%d  %s\n", f.Severity, f.Rule, f.File, f.Line, f.Detail)
			}
		}
		if ask && !*yes && !confirm("Install? [y/N] ") {
			cancel()
			fmt.Println("Nothing installed.")
			return 1
		}
		raw, err = ipc.CallTimeout(sock, "hub.commit", map[string]any{"token": p.Token}, time.Minute)
		if err != nil {
			cancel()
			return fail(err)
		}
		var c struct{ Path string }
		json.Unmarshal(raw, &c)
		fmt.Println("Installed:", c.Path)
		return 0
	case "remove":
		if len(args) != 3 {
			fmt.Fprintln(os.Stderr, hubUsage)
			return 2
		}
		if _, err := ipc.Call(sock, "hub.remove", map[string]any{"type": args[1], "id": args[2]}); err != nil {
			return fail(err)
		}
		fmt.Println("Removed.")
		return 0
	case "pack":
		fs := flag.NewFlagSet("hub pack", flag.ExitOnError)
		var o hub.PackOptions
		fs.StringVar(&o.Type, "type", "", "content type (default: from the manifest)")
		fs.StringVar(&o.ID, "id", "", "item id (default: from the manifest or folder name)")
		fs.StringVar(&o.Version, "version", "", "version (default: from the manifest)")
		fs.StringVar(&o.URLBase, "url-base", "", "https URL of the folder the archive will be published in")
		fs.StringVar(&o.OutDir, "out", ".", "folder for the archive")
		pos := parseInterleaved(fs, args[1:])
		if len(pos) != 1 {
			fmt.Fprintln(os.Stderr, hubUsage)
			return 2
		}
		out, e, err := hub.Pack(pos[0], o)
		if err != nil {
			return fail(err)
		}
		fmt.Fprintln(os.Stderr, "wrote", out)
		if o.URLBase == "" {
			fmt.Fprintln(os.Stderr, "no --url-base: fill in the entry's url (https) before publishing")
		}
		b, _ := json.MarshalIndent(e, "", "  ")
		fmt.Println(string(b))
		return 0
	case "help", "-h", "--help":
		fmt.Println(hubUsage)
		return 0
	}
	fmt.Fprintln(os.Stderr, hubUsage)
	return 2
}

func isHubType(s string) bool {
	for _, t := range hub.Types {
		if s == t {
			return true
		}
	}
	return false
}

// hubOpen shows the Hub page: through the running shell, else standalone Settings.
func hubOpen(tab string) int {
	args := []string{"hub", "open"}
	if tab != "" {
		args = append(args, tab)
	}
	if _, err := shellCall(args...); err == nil {
		return 0
	}
	c := exec.Command("qs", "-n", "-p", filepath.Join(config.ShellDir(), "settings.qml"))
	c.Env = append(os.Environ(), "ANO_SETTINGS_PAGE=hub", "ANO_HUB_TAB="+tab)
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := c.Start(); err != nil {
		fmt.Fprintln(os.Stderr, "ano hub:", err)
		return 1
	}
	c.Process.Release()
	return 0
}

// parseInterleaved lets flags follow positional arguments.
func parseInterleaved(fs *flag.FlagSet, args []string) []string {
	var pos []string
	for {
		fs.Parse(args)
		args = fs.Args()
		if len(args) == 0 {
			return pos
		}
		pos, args = append(pos, args[0]), args[1:]
	}
}

func confirm(prompt string) bool {
	fmt.Print(prompt)
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	a := strings.ToLower(strings.TrimSpace(line))
	return a == "y" || a == "yes"
}

func orDash(s string) string {
	if s == "" {
		return "—"
	}
	return s
}
