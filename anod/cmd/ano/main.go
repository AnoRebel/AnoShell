// ano is the command-line front end for the ano shell and anod.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"time"

	"ano/anod/internal/config"
	"ano/anod/internal/hooks"
	"ano/anod/internal/ipc"
	"ano/anod/internal/version"
)

const usage = `usage: ano <command> [args]

  status [--json]            anod and shell state
  doctor [--json]            check deps, config, sockets and crashes (exit 1 on failures)
  reload                     reload the shell (qs -c ano)
  ipc <args…>                pass through to "qs -c ano ipc" (e.g. ano ipc call settings open)
  emit <event> [k=v …]       send a shell event to anod (runs its hook); events:
                             ` + "%s" + `
  config validate [--file F] [--json]
  config migrate  [--file F] [--prune-unknown] [--dry-run]
  version
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, usage, eventList())
		os.Exit(2)
	}
	cmd, args := os.Args[1], os.Args[2:]
	var err error
	switch cmd {
	case "version", "--version", "-v":
		fmt.Printf("ano %s (API v%d)\n", version.Version, version.API)
	case "status":
		err = status(args)
	case "doctor":
		os.Exit(doctor(args))
	case "reload":
		os.Exit(shellIPC("call", "shell", "reload"))
	case "ipc":
		os.Exit(shellIPC(args...))
	case "emit":
		err = emit(args)
	case "config":
		os.Exit(configCmd(args))
	case "help", "-h", "--help":
		fmt.Printf(usage, eventList())
	default:
		fmt.Fprintf(os.Stderr, "ano: unknown command %q\n\n"+usage, cmd, eventList())
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano:", err)
		os.Exit(1)
	}
}

func eventList() string {
	names := make([]string, 0, len(hooks.Events))
	for e := range hooks.Events {
		names = append(names, e)
	}
	sortStrings(names)
	return strings.Join(names, ", ")
}

// shellIPC runs `qs -c ano ipc <args>` with the terminal attached.
func shellIPC(args ...string) int {
	c := exec.Command("qs", append([]string{"-c", "ano", "ipc"}, args...)...)
	c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := c.Run(); err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return ee.ExitCode()
		}
		fmt.Fprintln(os.Stderr, "ano:", err)
		return 1
	}
	return 0
}

// shellCall captures a shell IPC reply (with a timeout so doctor never hangs).
func shellCall(args ...string) (string, error) {
	if _, err := exec.LookPath("qs"); err != nil {
		return "", err
	}
	c := exec.Command("qs", append([]string{"-c", "ano", "ipc", "call"}, args...)...)
	done := make(chan struct{})
	var out []byte
	var err error
	go func() { out, err = c.Output(); close(done) }()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		c.Process.Kill()
		<-done
		return "", errors.New("shell IPC timed out")
	}
	if err != nil {
		return "", fmt.Errorf("shell not reachable")
	}
	return strings.TrimSpace(string(out)), nil
}

func status(args []string) error {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	asJSON := fs.Bool("json", false, "machine-readable output")
	fs.Parse(args)

	out := map[string]any{}
	if res, err := ipc.Call(ipc.DefaultSocketPath(), "status", nil); err == nil {
		out["anod"] = json.RawMessage(res)
	} else {
		out["anod"] = map[string]any{"running": false, "error": err.Error()}
	}
	if res, err := shellCall("compositor", "status"); err == nil {
		var cs struct {
			Backend string `json:"backend"`
		}
		json.Unmarshal([]byte(res), &cs)
		out["shell"] = map[string]any{"running": true, "backend": cs.Backend}
	} else {
		out["shell"] = map[string]any{"running": false}
	}
	if *asJSON {
		b, _ := json.MarshalIndent(out, "", "  ")
		fmt.Println(string(b))
		return nil
	}
	if a, ok := out["anod"].(json.RawMessage); ok {
		var st map[string]any
		d := json.NewDecoder(strings.NewReader(string(a)))
		d.UseNumber() // pids and counters print as integers
		d.Decode(&st)
		fmt.Printf("anod   running  v%v, pid %v, up %vs, %v client(s)\n", st["version"], st["pid"], st["uptimeSeconds"], st["clients"])
		if sup, ok := st["supervisor"].(map[string]any); ok {
			fmt.Printf("       supervisor %v, %v restart(s)\n", sup["state"], sup["restarts"])
		}
	} else {
		fmt.Println("anod   not running")
	}
	sh := out["shell"].(map[string]any)
	if sh["running"] == true {
		fmt.Printf("shell  running  backend %v\n", sh["backend"])
	} else {
		fmt.Println("shell  not running")
	}
	return nil
}

func emit(args []string) error {
	if len(args) == 0 {
		return fmt.Errorf("usage: ano emit <event> [key=value …]")
	}
	data := map[string]string{}
	for _, kv := range args[1:] {
		k, v, ok := strings.Cut(kv, "=")
		if !ok {
			return fmt.Errorf("bad data %q (want key=value)", kv)
		}
		data[k] = v
	}
	res, err := ipc.Call(ipc.DefaultSocketPath(), "event.emit", map[string]any{"event": args[0], "data": data})
	if err != nil {
		return err
	}
	fmt.Println(string(res))
	return nil
}

func configCmd(args []string) int {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "usage: ano config validate|migrate [flags]")
		return 2
	}
	fs := flag.NewFlagSet("config "+args[0], flag.ExitOnError)
	file := fs.String("file", config.UserPath(), "config file")
	asJSON := fs.Bool("json", false, "machine-readable output (validate)")
	prune := fs.Bool("prune-unknown", false, "also remove keys the schema doesn't know (migrate)")
	dry := fs.Bool("dry-run", false, "report changes without writing (migrate)")
	fs.Parse(args[1:])
	s, err := config.LoadSchema()
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano:", err)
		return 1
	}
	switch args[0] {
	case "validate":
		m, err := config.Load(*file)
		if err != nil {
			fmt.Fprintln(os.Stderr, "ano:", err)
			return 1
		}
		issues := s.Validate(m)
		if *asJSON {
			b, _ := json.MarshalIndent(issues, "", "  ")
			fmt.Println(string(b))
		} else {
			for _, is := range issues {
				fmt.Println(is)
			}
			fmt.Printf("%s: %d issue(s)\n", *file, len(issues))
		}
		for _, is := range issues {
			if is.Level == "error" {
				return 1
			}
		}
		return 0
	case "migrate":
		backup, log, err := config.MigrateFile(*file, s, *prune, *dry, time.Now())
		for _, l := range log {
			fmt.Println(l)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, "ano:", err)
			return 1
		}
		switch {
		case len(log) == 0:
			fmt.Println("nothing to migrate")
		case *dry:
			fmt.Println("dry run: nothing written")
		default:
			fmt.Println("backup:", backup)
		}
		return 0
	}
	fmt.Fprintf(os.Stderr, "ano: unknown config command %q\n", args[0])
	return 2
}
