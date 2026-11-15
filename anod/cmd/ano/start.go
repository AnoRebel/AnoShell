package main

// ano start | stop | restart: one command for a compositor's startup line.
// start runs `anod --supervise`, which starts `qs -c ano`, restarts it after
// crashes and raises its open-file limit.

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"syscall"
	"time"

	"ano/anod/internal/ipc"
)

// anodPath finds anod on PATH, else next to this ano (a compositor's startup
// PATH often lacks ~/.local/bin).
func anodPath() (string, error) {
	if p, err := exec.LookPath("anod"); err == nil {
		return p, nil
	}
	if self, err := os.Executable(); err == nil {
		p := filepath.Join(filepath.Dir(self), "anod")
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}
	return "", fmt.Errorf("anod not found (install it with anod/install.sh or your package manager)")
}

// anodStatus returns anod's status, or ok=false when none answers.
func anodStatus() (st struct {
	PID        int `json:"pid"`
	Supervisor *struct {
		State string `json:"state"`
		PID   int    `json:"pid"`
	} `json:"supervisor"`
}, ok bool) {
	raw, err := ipc.CallTimeout(ipc.DefaultSocketPath(), "status", nil, 2*time.Second)
	if err != nil {
		return st, false
	}
	return st, json.Unmarshal(raw, &st) == nil
}

func startCmd(args []string) int {
	fs := flag.NewFlagSet("start", flag.ExitOnError)
	detach := fs.Bool("d", false, "start in the background and return once it answers")
	fs.Parse(args)

	if st, ok := anodStatus(); ok {
		if st.Supervisor != nil {
			fmt.Printf("already running (anod %d, shell %d)\n", st.PID, st.Supervisor.PID)
			return 0
		}
		fmt.Fprintf(os.Stderr, "ano: anod %d is running without the shell supervisor; use: ano restart\n", st.PID)
		return 1
	}
	anod, err := anodPath()
	if err != nil {
		fmt.Fprintln(os.Stderr, "ano:", err)
		return 1
	}
	argv := []string{anod, "--supervise"}
	if !*detach {
		// Replace ano so the compositor (or terminal) owns anod directly.
		err = syscall.Exec(anod, argv, os.Environ())
		fmt.Fprintln(os.Stderr, "ano:", err)
		return 1
	}
	c := exec.Command(anod, argv[1:]...)
	c.SysProcAttr = &syscall.SysProcAttr{Setsid: true} // outlives this terminal
	if err := c.Start(); err != nil {                  // anod logs to ~/.local/state/ano/anod.log
		fmt.Fprintln(os.Stderr, "ano:", err)
		return 1
	}
	c.Process.Release()
	for range 50 {
		if st, ok := anodStatus(); ok {
			fmt.Printf("started (anod %d)\n", st.PID)
			return 0
		}
		time.Sleep(100 * time.Millisecond)
	}
	fmt.Fprintln(os.Stderr, "ano: anod didn't answer within 5 s; see ~/.local/state/ano/anod.log")
	return 1
}

func stopCmd() int {
	stopped := false
	if _, ok := anodStatus(); ok {
		// anod stops the shell it supervises on the way out.
		ipc.Call(ipc.DefaultSocketPath(), "shutdown", nil)
		for range 50 {
			if _, ok := anodStatus(); !ok {
				break
			}
			time.Sleep(100 * time.Millisecond)
		}
		if _, ok := anodStatus(); ok {
			fmt.Fprintln(os.Stderr, "ano: anod didn't stop within 5 s")
			return 1
		}
		stopped = true
	}
	// A shell started on its own (`qs -c ano`), not by anod.
	if exec.Command("qs", "kill", "-c", "ano").Run() == nil {
		stopped = true
	}
	if stopped {
		fmt.Println("stopped")
	} else {
		fmt.Println("not running")
	}
	return 0
}
