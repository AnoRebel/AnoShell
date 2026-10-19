package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"time"

	"ano/anod/internal/keybinds"
)

// keybindsCmd: ano keybinds list|apply|migrate [--dry-run|--revert].
func keybindsCmd(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: ano keybinds list [--json] | apply | migrate [--dry-run] | migrate --revert")
		return 2
	}
	p := keybinds.DefaultPaths()
	d, err := keybinds.LoadDefaults()
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano: defaults:", err)
		return 1
	}
	fail := func(err error) int { fmt.Fprintln(os.Stderr, "ano:", err); return 1 }
	switch args[0] {
	case "list":
		o, err := keybinds.LoadOverrides(p.Overrides)
		if err != nil {
			return fail(err)
		}
		eff := keybinds.Effective(d, o)
		if slices.Contains(args[1:], "--json") {
			b, _ := json.MarshalIndent(eff, "", "  ")
			fmt.Println(string(b))
			return 0
		}
		for _, b := range eff {
			where := "both"
			switch {
			case b.On("hyprland") && !b.On("niri"):
				where = "hyprland"
			case b.On("niri") && !b.On("hyprland"):
				where = "niri"
			}
			sub := ""
			if b.Submap != "" {
				sub = " [" + b.Submap + "]"
			}
			fmt.Printf("%-30s %-9s %s%s\n", b.Chord, where, b.Describe(), sub)
		}
		return 0
	case "apply":
		o, err := keybinds.LoadOverrides(p.Overrides)
		if err != nil {
			return fail(err)
		}
		h, n, err := keybinds.Generate(p, keybinds.Effective(d, o), d.Helpers)
		if err != nil {
			return fail(err)
		}
		if h {
			if err := keybinds.Reload(); err != nil {
				return fail(err)
			}
		}
		fmt.Printf("wrote %s (changed: %v) and %s (changed: %v)\n", p.HyprBinds, h, p.NiriBinds, n)
		return 0
	case "migrate":
		if slices.Contains(args[1:], "--revert") {
			files, err := keybinds.Revert(p)
			if err != nil {
				return fail(err)
			}
			for _, f := range files {
				fmt.Println("restored", f)
			}
			if os.Getenv("HYPRLAND_INSTANCE_SIGNATURE") != "" {
				exec.Command("hyprctl", "reload").Run() // back to the restored config's own binds
			}
			return 0
		}
		dry := slices.Contains(args[1:], "--dry-run")
		res, err := keybinds.Migrate(p, d, time.Now(), dry)
		if err != nil {
			return fail(err)
		}
		for f, n := range res.Moved {
			fmt.Printf("%s: %d bind statement(s) moved to ano\n", f, n)
		}
		for _, l := range res.Report {
			fmt.Println(" ", l)
		}
		if dry {
			fmt.Println("dry run: nothing written")
			return 0
		}
		for f, b := range res.Backups {
			fmt.Printf("backup: %s → %s\n", f, b)
		}
		if err := keybinds.Reload(); err != nil {
			return fail(err)
		}
		fmt.Println("done; undo with: ano keybinds migrate --revert")
		return 0
	}
	fmt.Fprintf(os.Stderr, "ano: unknown keybinds command %q\n", args[0])
	return 2
}
