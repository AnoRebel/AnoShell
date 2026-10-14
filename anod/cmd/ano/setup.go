package main

// ano setup: install, update and refresh the shell checkout and binaries.
//
// The shell is a git checkout at config.ShellDir() (~/.config/quickshell/ano).
// install clones it if missing and builds anod + ano; update fast-forwards it
// from its remote; refresh rebuilds, migrates the user config (with a backup)
// and restarts what is running. Every external command is an argv list.

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"ano/anod/internal/config"
	"ano/anod/internal/ipc"
)

const defaultRepo = "https://github.com/AnoRebel/AnoShell.git"

const setupUsage = `usage: ano setup <command> [flags]

  status  [--fetch] [--json]          checkout, upstream and binary versions
  install [--repo URL] [--branch B]   clone the shell if missing, build anod + ano, run doctor
  update                              fast-forward the checkout from its remote, then refresh
  refresh                             rebuild, migrate the user config (backup), restart anod / reload the shell

  install, update and refresh take --dry-run (print the steps only) and
  --no-restart (leave anod and the shell running as they are).
`

func setupCmd(args []string) int {
	if len(args) == 0 {
		fmt.Fprint(os.Stderr, setupUsage)
		return 2
	}
	fs := flag.NewFlagSet("setup "+args[0], flag.ExitOnError)
	dry := fs.Bool("dry-run", false, "print the steps without running them")
	noRestart := fs.Bool("no-restart", false, "don't restart anod or reload the shell")
	fetch := fs.Bool("fetch", false, "fetch the remote before comparing (status)")
	asJSON := fs.Bool("json", false, "machine-readable output (status)")
	repo := fs.String("repo", defaultRepo, "git URL to clone (install)")
	branch := fs.String("branch", "main", "branch to clone (install)")
	fs.Parse(args[1:])

	r := &runner{dry: *dry, dir: config.ShellDir()}
	var err error
	switch args[0] {
	case "status":
		return setupStatus(r.dir, *fetch, *asJSON)
	case "install":
		err = setupInstall(r, *repo, *branch)
	case "update":
		err = setupUpdate(r)
		if err == nil {
			err = setupRefresh(r, *noRestart)
		}
	case "refresh":
		err = setupRefresh(r, *noRestart)
	case "help", "-h", "--help":
		fmt.Print(setupUsage)
		return 0
	default:
		fmt.Fprintf(os.Stderr, "ano: unknown setup command %q\n\n%s", args[0], setupUsage)
		return 2
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano setup:", err)
		return 1
	}
	return 0
}

// runner prints each step and runs it unless dry.
type runner struct {
	dry bool
	dir string
}

func (r *runner) run(dir, name string, argv ...string) error {
	fmt.Printf("→ %s\n  $ %s\n", name, strings.Join(argv, " "))
	if r.dry {
		return nil
	}
	c := exec.Command(argv[0], argv[1:]...)
	c.Dir = dir
	c.Stdout, c.Stderr = os.Stdout, os.Stderr
	if err := c.Run(); err != nil {
		return fmt.Errorf("%s: %w", name, err)
	}
	return nil
}

// git runs a git query in the checkout and returns trimmed stdout.
func git(dir string, args ...string) (string, error) {
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).Output()
	return strings.TrimSpace(string(out)), err
}

// upstream is the ref the checkout follows: its tracking branch, else
// origin/<branch>.
func upstream(dir string) (string, error) {
	if u, err := git(dir, "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"); err == nil && u != "" {
		return u, nil
	}
	b, err := git(dir, "symbolic-ref", "--short", "HEAD")
	if err != nil {
		return "", errors.New("detached HEAD: check out a branch first")
	}
	return "origin/" + b, nil
}

// parseAheadBehind reads `git rev-list --left-right --count HEAD...U`.
func parseAheadBehind(s string) (ahead, behind int, err error) {
	f := strings.Fields(s)
	if len(f) != 2 {
		return 0, 0, fmt.Errorf("unexpected rev-list output %q", s)
	}
	if ahead, err = strconv.Atoi(f[0]); err != nil {
		return
	}
	behind, err = strconv.Atoi(f[1])
	return
}

func setupStatus(dir string, fetch, asJSON bool) int {
	st := map[string]any{"shellDir": dir, "userConfig": config.UserPath()}
	if _, err := os.Stat(filepath.Join(dir, "shell.qml")); err != nil {
		st["installed"] = false
	} else {
		st["installed"] = true
		if fetch {
			git(dir, "fetch", "--quiet", "origin")
		}
		st["branch"], _ = git(dir, "symbolic-ref", "--short", "HEAD")
		st["commit"], _ = git(dir, "rev-parse", "--short", "HEAD")
		dirty, _ := git(dir, "status", "--porcelain")
		st["dirty"] = dirty != ""
		if u, err := upstream(dir); err == nil {
			st["upstream"] = u
			if s, err := git(dir, "rev-list", "--left-right", "--count", "HEAD..."+u); err == nil {
				if a, b, err := parseAheadBehind(s); err == nil {
					st["ahead"], st["behind"] = a, b
				}
			}
		}
	}
	st["cli"] = versionString()
	if res, err := ipc.Call(ipc.DefaultSocketPath(), "version", nil); err == nil {
		var v struct{ Version string }
		json.Unmarshal(res, &v)
		st["anod"] = v.Version
	}
	if _, err := os.Stat(config.UserPath()); err == nil {
		st["userConfigExists"] = true
	}
	if asJSON {
		b, _ := json.MarshalIndent(st, "", "  ")
		fmt.Println(string(b))
		return 0
	}
	if st["installed"] == false {
		fmt.Printf("shell   not installed at %s (ano setup install)\n", dir)
		return 1
	}
	dirtyMark := ""
	if st["dirty"] == true {
		dirtyMark = ", uncommitted changes"
	}
	fmt.Printf("shell   %s on %v at %v%s\n", dir, st["branch"], st["commit"], dirtyMark)
	if u, ok := st["upstream"]; ok {
		if _, known := st["ahead"]; known {
			fmt.Printf("remote  %v: %v ahead, %v behind%s\n", u, st["ahead"], st["behind"], map[bool]string{true: "", false: " (as of the last fetch; --fetch to refresh)"}[fetch])
		} else {
			fmt.Printf("remote  %v not fetched yet (--fetch)\n", u)
		}
	}
	fmt.Printf("cli     %v\n", st["cli"])
	if v, ok := st["anod"]; ok {
		fmt.Printf("anod    running %v\n", v)
	} else {
		fmt.Println("anod    not running")
	}
	cfg := "missing (defaults apply)"
	if st["userConfigExists"] == true {
		cfg = "present"
	}
	fmt.Printf("config  %s %s\n", config.UserPath(), cfg)
	return 0
}

func setupInstall(r *runner, repo, branch string) error {
	if _, err := os.Stat(filepath.Join(r.dir, "shell.qml")); err == nil {
		fmt.Printf("shell already at %s (use `ano setup update` to update it)\n", r.dir)
	} else if _, err := os.Stat(r.dir); err == nil {
		return fmt.Errorf("%s exists but is not an ano checkout; move it aside first", r.dir)
	} else {
		if !have("git") {
			return errors.New("git is required")
		}
		if err := os.MkdirAll(filepath.Dir(r.dir), 0o755); err != nil && !r.dry {
			return err
		}
		if err := r.run("", "clone the shell", "git", "clone", "--branch", branch, "--", repo, r.dir); err != nil {
			return err
		}
	}
	if err := build(r); err != nil {
		return err
	}
	if r.dry {
		fmt.Println("→ run doctor")
		return nil
	}
	fmt.Println("→ run doctor")
	if doctor(nil) != 0 {
		fmt.Println("doctor reported failures; fix them, then `ano setup refresh`")
	}
	fmt.Println("start the shell with `qs -c ano` (or `anod --supervise`)")
	return nil
}

func setupUpdate(r *runner) error {
	if dirty, err := git(r.dir, "status", "--porcelain"); err != nil {
		return fmt.Errorf("%s is not a git checkout", r.dir)
	} else if dirty != "" {
		return errors.New("the checkout has uncommitted changes; commit or stash them first")
	}
	u, err := upstream(r.dir)
	if err != nil {
		return err
	}
	remote, _, _ := strings.Cut(u, "/")
	before, _ := git(r.dir, "rev-parse", "--short", "HEAD")
	if err := r.run(r.dir, "fetch "+remote, "git", "fetch", "--quiet", remote); err != nil {
		return err
	}
	// Fast-forward only: local commits are never rewritten or merged.
	if err := r.run(r.dir, "fast-forward to "+u, "git", "merge", "--ff-only", u); err != nil {
		return fmt.Errorf("%w (local commits diverge from %s; rebase or merge by hand)", err, u)
	}
	if !r.dry {
		after, _ := git(r.dir, "rev-parse", "--short", "HEAD")
		if after == before {
			fmt.Println("already up to date")
		} else {
			fmt.Printf("updated %s → %s\n", before, after)
		}
	}
	return nil
}

func build(r *runner) error {
	if !have("go") {
		return errors.New("go is required to build anod and ano")
	}
	return r.run(filepath.Join(r.dir, "anod"), "build anod + ano", "bash", "install.sh")
}

func setupRefresh(r *runner, noRestart bool) error {
	if err := build(r); err != nil {
		return err
	}
	if _, err := os.Stat(config.UserPath()); err == nil {
		// The freshly built ano carries the current schema.
		if err := r.run("", "migrate the user config (backup kept)", binPath("ano"), "config", "migrate"); err != nil {
			return err
		}
	}
	if noRestart {
		return nil
	}
	if res, err := ipc.Call(ipc.DefaultSocketPath(), "status", nil); err == nil {
		var st struct {
			Supervisor json.RawMessage `json:"supervisor"`
		}
		json.Unmarshal(res, &st)
		return restartAnod(r, len(st.Supervisor) > 0)
	}
	if _, err := shellCall("compositor", "status"); err == nil {
		fmt.Println("→ reload the shell")
		if !r.dry && shellIPC("call", "shell", "reload") != 0 {
			return errors.New("shell reload failed")
		}
	}
	return nil
}

// restartAnod asks the running anod to stop and starts the new build in its
// place, detached; with --supervise it brings the shell back up as well.
func restartAnod(r *runner, supervise bool) error {
	argv := []string{binPath("anod")}
	if supervise {
		argv = append(argv, "--supervise")
	}
	fmt.Printf("→ restart anod\n  $ %s\n", strings.Join(argv, " "))
	if r.dry {
		return nil
	}
	sock := ipc.DefaultSocketPath()
	ipc.Call(sock, "shutdown", nil)
	for deadline := time.Now().Add(5 * time.Second); time.Now().Before(deadline); time.Sleep(200 * time.Millisecond) {
		if _, err := ipc.Call(sock, "ping", nil); err != nil {
			break
		}
	}
	c := exec.Command(argv[0], argv[1:]...)
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := c.Start(); err != nil {
		return fmt.Errorf("start anod: %w", err)
	}
	return c.Process.Release()
}

// binPath is where install.sh puts the binaries.
func binPath(name string) string {
	if p := os.Getenv("PREFIX"); p != "" {
		return filepath.Join(p, "bin", name)
	}
	h, _ := os.UserHomeDir()
	return filepath.Join(h, ".local", "bin", name)
}
