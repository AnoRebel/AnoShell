package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"ano/anod/internal/backup"
)

const backupUsage = `usage: ano backup <command> [flags]

  categories                         what can be backed up (default ones marked *)
  create  [--only a,b] [--add a,b] [-o FILE]
                                     archive the default categories, only some
                                     (--only), or the defaults plus opt-in ones (--add)
  list                               backups in the default folder
  restore FILE [--only a,b] [--dry-run] [--no-snapshot]
                                     restore every category in FILE, or only some;
                                     the files it replaces are snapshotted first
`

func backupCmd(args []string) int {
	if len(args) == 0 {
		fmt.Fprint(os.Stderr, backupUsage)
		return 2
	}
	home, _ := os.UserHomeDir()
	fs := flag.NewFlagSet("backup "+args[0], flag.ExitOnError)
	only := fs.String("only", "", "comma-separated categories")
	add := fs.String("add", "", "opt-in categories to add to the defaults (create)")
	out := fs.String("o", "", "archive path (create)")
	dry := fs.Bool("dry-run", false, "list what would be restored (restore)")
	noSnap := fs.Bool("no-snapshot", false, "don't save the replaced files first (restore)")
	// Flags may follow the archive path: ano backup restore FILE --only config
	var pos []string
	rest := args[1:]
	for len(rest) > 0 {
		fs.Parse(rest)
		rest = fs.Args()
		if len(rest) > 0 {
			pos, rest = append(pos, rest[0]), rest[1:]
		}
	}
	split := func(s string) []string {
		var out []string
		for _, p := range strings.Split(s, ",") {
			if p = strings.TrimSpace(p); p != "" {
				out = append(out, p)
			}
		}
		return out
	}
	now := time.Now()
	stamp := now.Format("20060102-150405")
	fail := func(err error) int { fmt.Fprintln(os.Stderr, "ano backup:", err); return 1 }

	switch args[0] {
	case "categories":
		for _, c := range backup.Categories {
			mark := " "
			if c.Default {
				mark = "*"
			}
			fmt.Printf("%s %-11s %s\n", mark, c.Name, c.Desc)
		}
		return 0
	case "create":
		names := split(*only)
		if len(names) == 0 && *add != "" {
			for _, c := range backup.Categories {
				if c.Default {
					names = append(names, c.Name)
				}
			}
			names = append(names, split(*add)...)
		}
		cats, err := backup.Lookup(names)
		if err != nil {
			return fail(err)
		}
		dest := *out
		if dest == "" {
			dest = filepath.Join(backup.DefaultDir(home), "anoshell-"+stamp+".tar.gz")
		}
		// A live file count on a terminal (wallpapers can be large).
		var prog []backup.Progress
		if fi, err := os.Stdout.Stat(); err == nil && fi.Mode()&os.ModeCharDevice != 0 {
			last := time.Time{}
			prog = append(prog, func(done, total int) {
				if done == total || time.Since(last) > 100*time.Millisecond {
					fmt.Printf("\r  archiving %d/%d file(s)…", done, total)
					last = time.Now()
				}
				if done == total {
					fmt.Print("\r\033[K")
				}
			})
		}
		m, err := backup.Create(home, dest, cats, now, prog...)
		if err != nil {
			return fail(err)
		}
		fmt.Printf("backed up %d file(s) [%s] to %s\n", m.Files, strings.Join(m.Categories, ", "), dest)
		return 0
	case "list":
		dir := backup.DefaultDir(home)
		files, _ := filepath.Glob(filepath.Join(dir, "*.tar.gz"))
		sort.Sort(sort.Reverse(sort.StringSlice(files)))
		if len(files) == 0 {
			fmt.Println("no backups in", dir)
		}
		for _, f := range files {
			if m, err := backup.ReadManifest(f); err == nil {
				fmt.Printf("%s  %s  %d file(s)  [%s]\n", m.Created.Local().Format("2006-01-02 15:04"), f, m.Files, strings.Join(m.Categories, ", "))
			}
		}
		return 0
	case "restore":
		if len(pos) != 1 {
			fmt.Fprint(os.Stderr, backupUsage)
			return 2
		}
		m, err := backup.ReadManifest(pos[0])
		if err != nil {
			return fail(err)
		}
		names := split(*only)
		if len(names) == 0 {
			names = m.Categories
		}
		for _, n := range names {
			found := false
			for _, c := range m.Categories {
				found = found || c == n
			}
			if !found {
				return fail(fmt.Errorf("%q is not in this backup (it has: %s)", n, strings.Join(m.Categories, ", ")))
			}
		}
		cats, err := backup.Lookup(names)
		if err != nil {
			return fail(err)
		}
		snap := ""
		if !*noSnap {
			snap = filepath.Join(backup.DefaultDir(home), "pre-restore-"+stamp+".tar.gz")
		}
		files, err := backup.Restore(home, pos[0], cats, snap, *dry, now)
		for _, f := range files {
			fmt.Println("  ~/" + f)
		}
		if err != nil {
			return fail(err)
		}
		switch {
		case *dry:
			fmt.Printf("dry run: %d file(s) would be restored\n", len(files))
		default:
			fmt.Printf("restored %d file(s) [%s]\n", len(files), strings.Join(names, ", "))
			if snap != "" && len(files) > 0 {
				fmt.Println("replaced files saved to", snap)
			}
			fmt.Println("reload to apply: ano reload (and your compositor's reload for compositor configs)")
		}
		return 0
	}
	fmt.Fprintf(os.Stderr, "ano: unknown backup command %q\n\n%s", args[0], backupUsage)
	return 2
}
