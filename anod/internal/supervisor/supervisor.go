// Package supervisor runs `qs -c ano` and restarts it after crashes, with
// exponential backoff and a crash-loop stop.
package supervisor

import (
	"context"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"sync"
	"syscall"
	"time"
)

type State string

const (
	Running   State = "running"
	Backoff   State = "backoff"
	Stopped   State = "stopped"    // the shell exited cleanly (user quit) or anod is stopping
	CrashLoop State = "crash-loop" // gave up after MaxCrashes within Window
)

type Supervisor struct {
	Cmd        []string
	MaxCrashes int           // default 5
	Window     time.Duration // default 2 min
	BaseDelay  time.Duration // default 1 s, doubled per recent crash
	MaxDelay   time.Duration // default 30 s
	// Notify is called once when the crash loop stops restarts.
	Notify func(title, body string)
	// CrashReport returns the newest crash report written after `since` ("" if none).
	CrashReport func(since time.Time) string
	// Alive reports whether the session the shell draws on still exists. A
	// crash is not restarted once it's gone (the compositor exited: logout).
	Alive func() bool
	// NoHugePages turns transparent huge pages off for the shell
	// (PR_SET_THP_DISABLE on anod, which the child inherits through fork and
	// exec): about 100 MB less RSS for qs, no CPU cost (baselines.md, 13.1).
	NoHugePages bool

	mu        sync.Mutex
	started   time.Time // first child start; crash reports older than this aren't ours
	state     State
	pid       int
	crashes   []time.Time
	restarts  int
	lastCrash string
	lastExit  string
}

type Status struct {
	State     State  `json:"state"`
	PID       int    `json:"pid,omitempty"`
	Restarts  int    `json:"restarts"`
	Recent    int    `json:"recentCrashes"`
	LastExit  string `json:"lastExit,omitempty"`
	LastCrash string `json:"lastCrashReport,omitempty"`
	since     time.Time
}

func (s *Supervisor) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	return Status{s.state, s.pid, s.restarts, len(s.crashes), s.lastExit, s.lastCrash, s.started}
}

func (st Status) startedAt() time.Time { return st.since }

func (s *Supervisor) defaults() {
	if s.MaxCrashes == 0 {
		s.MaxCrashes = 5
	}
	if s.Window == 0 {
		s.Window = 2 * time.Minute
	}
	if s.BaseDelay == 0 {
		s.BaseDelay = time.Second
	}
	if s.MaxDelay == 0 {
		s.MaxDelay = 30 * time.Second
	}
}

func (s *Supervisor) set(f func()) { s.mu.Lock(); f(); s.mu.Unlock() }

// Run supervises until ctx ends, the shell exits cleanly, or a crash loop.
func (s *Supervisor) Run(ctx context.Context) State {
	s.defaults()
	s.set(func() { s.started = time.Now() })
	if s.NoHugePages {
		const prSetTHPDisable = 41
		if _, _, errno := syscall.RawSyscall6(syscall.SYS_PRCTL, prSetTHPDisable, 1, 0, 0, 0, 0); errno != 0 {
			log.Printf("supervisor: huge pages stay on: %v", errno)
		}
	}
	raiseNoFile()
	for {
		cmd := exec.Command(s.Cmd[0], s.Cmd[1:]...)
		cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		if err := cmd.Start(); err != nil {
			s.set(func() { s.lastExit = err.Error() })
			if s.crashed(ctx) {
				return s.Status().State
			}
			continue
		}
		s.set(func() { s.state, s.pid = Running, cmd.Process.Pid })

		done := make(chan error, 1)
		go func() { done <- cmd.Wait() }()
		var err error
		select {
		case err = <-done:
		case <-ctx.Done():
			syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
			select {
			case <-done:
			case <-time.After(5 * time.Second):
				syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
				<-done
			}
			s.set(func() { s.state, s.pid = Stopped, 0 })
			return Stopped
		}

		s.set(func() { s.pid = 0; s.lastExit = exitText(cmd.ProcessState, err) })
		if err == nil { // exit 0: the user quit the shell on purpose
			s.set(func() { s.state = Stopped })
			return Stopped
		}
		if s.crashed(ctx) {
			return s.Status().State
		}
	}
}

// crashed records a crash and either sleeps the backoff (false) or gives up (true).
func (s *Supervisor) crashed(ctx context.Context) bool {
	if s.Alive != nil && !s.Alive() {
		s.set(func() { s.state = Stopped })
		return true
	}
	now := time.Now()
	report := ""
	if s.CrashReport != nil {
		report = s.CrashReport(s.Status().startedAt())
	}
	s.mu.Lock()
	recent := s.crashes[:0]
	for _, t := range s.crashes {
		if now.Sub(t) < s.Window {
			recent = append(recent, t)
		}
	}
	s.crashes = append(recent, now)
	if report != "" {
		s.lastCrash = report
	}
	n := len(s.crashes)
	if n >= s.MaxCrashes {
		s.state = CrashLoop
		s.mu.Unlock()
		if s.Notify != nil {
			body := "ano crashed repeatedly and was not restarted."
			if report != "" {
				body += " Crash report: " + report
			}
			s.Notify("ano shell stopped", body)
		}
		return true
	}
	s.state = Backoff
	s.mu.Unlock()

	delay := s.BaseDelay << (n - 1)
	if delay > s.MaxDelay || delay <= 0 {
		delay = s.MaxDelay
	}
	select {
	case <-time.After(delay):
	case <-ctx.Done():
		s.set(func() { s.state = Stopped })
		return true
	}
	s.set(func() { s.restarts++ })
	return false
}

func exitText(ps *os.ProcessState, err error) string {
	if ps == nil {
		if err != nil {
			return err.Error()
		}
		return ""
	}
	return ps.String() // "exit status 1" / "signal: segmentation fault"
}

// QuickshellCrashReport returns the newest dir under Quickshell's crash cache
// that was written after since.
func QuickshellCrashReport(since time.Time) string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		home, _ := os.UserHomeDir()
		base = filepath.Join(home, ".cache")
	}
	p := NewestEntry(filepath.Join(base, "quickshell", "crashes"))
	if fi, err := os.Stat(p); p == "" || err != nil || fi.ModTime().Before(since) {
		return ""
	}
	return p
}

// NewestEntry returns the most recently modified entry in dir ("" if none).
func NewestEntry(dir string) string {
	ents, err := os.ReadDir(dir)
	if err != nil || len(ents) == 0 {
		return ""
	}
	type e struct {
		p string
		t time.Time
	}
	var list []e
	for _, d := range ents {
		if fi, err := d.Info(); err == nil {
			list = append(list, e{filepath.Join(dir, d.Name()), fi.ModTime()})
		}
	}
	sort.Slice(list, func(i, j int) bool { return list[i].t.After(list[j].t) })
	if len(list) == 0 {
		return ""
	}
	return list[0].p
}

// raiseNoFile lifts the open-file soft limit to 65536 (or the hard limit)
// for the shell it starts: a compositor hands its children 1024, and a shell
// that reloads on every scale change has run out of descriptors after a day.
// An explicit Setrlimit also stops os/exec from restoring the old limit in
// the child (which it does after Go raises its own limit at start).
func raiseNoFile() {
	var r syscall.Rlimit
	if err := syscall.Getrlimit(syscall.RLIMIT_NOFILE, &r); err != nil {
		return
	}
	want := min(uint64(65536), r.Max)
	if want <= r.Cur {
		want = r.Cur
	}
	r.Cur = want
	if err := syscall.Setrlimit(syscall.RLIMIT_NOFILE, &r); err != nil {
		log.Printf("supervisor: open-file limit stays: %v", err)
	}
}
