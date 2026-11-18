package sysmon

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
	"time"
)

type fakeProc struct {
	pid, ppid      int
	name, state    string
	ticks, rssPage uint64
	flags          uint64
	cmd            string
}

// writeTree lays out a /proc with the given processes and a /proc/stat whose cpu line totals `total` jiffies.
func writeTree(t *testing.T, root string, total uint64, procs []fakeProc) {
	t.Helper()
	os.MkdirAll(root, 0o755)
	stat := fmt.Sprintf("cpu  %d 0 0 0 0 0 0 0 0 0\ncpu0 1 0 0 0\ncpu1 1 0 0 0\nintr 1\nbtime 1700000000\n", total)
	os.WriteFile(filepath.Join(root, "stat"), []byte(stat), 0o644)
	os.WriteFile(filepath.Join(root, "meminfo"), []byte("MemTotal:       1000 kB\nMemFree: 1 kB\n"), 0o644)
	for _, p := range procs {
		dir := filepath.Join(root, fmt.Sprint(p.pid))
		os.MkdirAll(dir, 0o755)
		// fields 3..24: state ppid pgrp session tty tpgid flags minflt cminflt majflt cmajflt utime stime cutime cstime
		// priority nice threads itrealvalue starttime vsize rss
		line := fmt.Sprintf("%d (%s) %s %d 1 1 0 -1 %d 0 0 0 0 %d 0 0 0 20 0 3 0 500 1000 %d 0\n",
			p.pid, p.name, p.state, p.ppid, p.flags, p.ticks, p.rssPage)
		os.WriteFile(filepath.Join(dir, "stat"), []byte(line), 0o644)
		os.WriteFile(filepath.Join(dir, "cmdline"), []byte(p.cmd), 0o644)
	}
}

func newSampler(t *testing.T) (*Sampler, string, *time.Time) {
	dir := t.TempDir()
	passwd := filepath.Join(dir, "passwd")
	os.WriteFile(passwd, []byte(fmt.Sprintf("root:x:0:0::/root:/bin/sh\ntester:x:%d:%d::/home/t:/bin/sh\n", os.Getuid(), os.Getgid())), 0o644)
	now := time.Unix(1700001000, 0)
	s := &Sampler{Proc: filepath.Join(dir, "proc"), Sys: filepath.Join(dir, "sys"), Passwd: passwd, Now: func() time.Time { return now }}
	return s, dir, &now
}

func TestTopMeasuresBetweenSamples(t *testing.T) {
	s, dir, now := newSampler(t)
	root := filepath.Join(dir, "proc")
	procs := []fakeProc{
		{pid: 10, ppid: 1, name: "web browser (main)", state: "S", ticks: 100, rssPage: 10, cmd: "firefox\x00--new"},
		{pid: 20, ppid: 1, name: "editor", state: "T", ticks: 50, rssPage: 20, cmd: "nvim\x00a.go"},
		{pid: 2, ppid: 0, name: "kthreadd", state: "S", ticks: 999, flags: pfKthread},
	}
	writeTree(t, root, 1000, procs)
	first := s.Top(5)
	if first.Count != 2 || first.Cores != 2 {
		t.Fatalf("kernel thread must be left out, cores counted: %+v", first)
	}
	for _, p := range first.Procs {
		if p.CPU != 0 {
			t.Fatalf("first sample has no interval: %+v", p)
		}
	}

	procs[0].ticks, procs[1].ticks = 160, 70 // +60 and +20 of +200 total
	writeTree(t, root, 1200, procs)
	*now = now.Add(500 * time.Millisecond)
	if s.Top(5).Procs[0].CPU != 0 {
		t.Fatal("a call inside a second must reuse the last sample")
	}
	*now = now.Add(time.Second)
	top := s.Top(5)
	p := top.Procs[0]
	if p.PID != 10 || p.CPU != 0.3 || p.Name != "web browser (main)" || p.Cmd != "firefox --new" || p.Threads != 3 {
		t.Fatalf("busiest: %+v", p)
	}
	if p.Mem != 10*uint64(os.Getpagesize()) || p.User != "tester" || p.Start != (1700000000*100+500)*10 {
		t.Fatalf("mem/user/start: %+v", p)
	}
	if q := top.Procs[1]; q.PID != 20 || q.CPU != 0.1 || !q.Paused {
		t.Fatalf("second: %+v", q)
	}
}

func TestDetailsAndApps(t *testing.T) {
	s, dir, now := newSampler(t)
	root := filepath.Join(dir, "proc")
	procs := []fakeProc{
		{pid: 100, ppid: 1, name: "code", state: "S", ticks: 0, rssPage: 1},
		{pid: 101, ppid: 100, name: "code-helper", state: "S", ticks: 0, rssPage: 2},
		{pid: 102, ppid: 101, name: "node", state: "R", ticks: 0, rssPage: 3},
		{pid: 200, ppid: 1, name: "kitty", state: "S", ticks: 0, rssPage: 1},
	}
	writeTree(t, root, 1000, procs)
	s.Top(1)
	procs[2].ticks, procs[3].ticks = 40, 10
	writeTree(t, root, 1100, procs)
	*now = now.Add(2 * time.Second)

	if _, ok := s.Details(999); ok {
		t.Fatal("unknown pid")
	}
	if d, ok := s.Details(102); !ok || d.Name != "node" || d.CPU != 0.4 {
		t.Fatalf("details: %+v", d)
	}
	apps := s.Apps([]Group{{App: "kitty", PIDs: []int{200}}, {App: "Code", PIDs: []int{100, 101}}, {App: "gone", PIDs: []int{5}}})
	if len(apps) != 3 || apps[0].App != "Code" || apps[0].Procs != 3 || apps[0].CPU != 0.4 || apps[0].Top[0].PID != 102 {
		t.Fatalf("apps: %+v", apps)
	}
	if byName := s.Apps([]Group{{App: "Kitty", Names: []string{"KITTY"}}}); byName[0].Procs != 1 || byName[0].CPU != 0.1 {
		t.Fatalf("by name: %+v", byName)
	}
	if apps[0].Mem != 6*uint64(os.Getpagesize()) || apps[1].App != "kitty" || apps[1].CPU != 0.1 || apps[2].Procs != 0 {
		t.Fatalf("apps totals: %+v", apps)
	}
}

func TestSensors(t *testing.T) {
	s, dir, _ := newSampler(t)
	hw := filepath.Join(dir, "sys/class/hwmon/hwmon0")
	os.MkdirAll(hw, 0o755)
	os.WriteFile(filepath.Join(hw, "name"), []byte("coretemp\n"), 0o644)
	os.WriteFile(filepath.Join(hw, "temp1_input"), []byte("45500\n"), 0o644)
	os.WriteFile(filepath.Join(hw, "temp1_label"), []byte("Package id 0\n"), 0o644)
	os.WriteFile(filepath.Join(hw, "temp2_input"), []byte("41000\n"), 0o644)
	got := s.Sensors()
	if len(got) != 2 || got[0].Label != "Package id 0" || got[0].C != 45.5 || got[1].Label != "temp2" || got[0].Chip != "coretemp" {
		t.Fatalf("hwmon: %+v", got)
	}

	s2, dir2, _ := newSampler(t)
	z := filepath.Join(dir2, "sys/class/thermal/thermal_zone0")
	os.MkdirAll(z, 0o755)
	os.WriteFile(filepath.Join(z, "type"), []byte("x86_pkg_temp\n"), 0o644)
	os.WriteFile(filepath.Join(z, "temp"), []byte("50000\n"), 0o644)
	if got := s2.Sensors(); len(got) != 1 || got[0].Label != "x86_pkg_temp" || got[0].C != 50 {
		t.Fatalf("thermal fallback: %+v", got)
	}
}

func TestLiveProc(t *testing.T) {
	if _, err := os.Stat("/proc/self/stat"); err != nil {
		t.Skip("no /proc")
	}
	s := &Sampler{}
	if top := s.Top(5); top.Count == 0 || len(top.Procs) == 0 || top.Cores == 0 {
		t.Fatalf("live: %+v", top)
	}
	if _, ok := s.Details(os.Getpid()); !ok {
		t.Fatal("own process")
	}
}
