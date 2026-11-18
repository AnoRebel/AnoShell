// Package sysmon reads the busiest processes, one process's details, per-app totals and the temperature sensors
// straight from /proc and /sys, for the Bubble Monitor. CPU shares are measured between two samples, so the first
// call after a pause reports 0 for everyone; samples are taken at most once per second, however often callers ask.
package sysmon

import (
	"bufio"
	"bytes"
	"cmp"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

// clkTck is USER_HZ, the unit of the jiffy counts in /proc/<pid>/stat.
// ponytail: fixed at 100 as on every mainstream Linux arch; read sysconf(_SC_CLK_TCK) via cgo if one differs.
const clkTck = 100

// minGap: calls closer than this share the last sample.
const minGap = 900 * time.Millisecond

// pfKthread is the kernel-thread bit of the flags field in /proc/<pid>/stat.
const pfKthread = 0x00200000

type Proc struct {
	PID      int     `json:"pid"`
	PPID     int     `json:"ppid"`
	Name     string  `json:"name"`
	CPU      float64 `json:"cpu"`      // share of the whole machine since the last sample, 0..1
	Mem      uint64  `json:"mem"`      // resident bytes
	MemShare float64 `json:"memShare"` // of MemTotal, 0..1
	Threads  int     `json:"threads"`
	User     string  `json:"user"`
	Start    int64   `json:"start"` // ms since the epoch
	State    string  `json:"state"`
	Paused   bool    `json:"paused"`
	Cmd      string  `json:"cmd,omitempty"`
}

type Top struct {
	Procs []Proc `json:"procs"`
	Count int    `json:"count"` // user processes seen
	Cores int    `json:"cores"`
}

// Group is a set of processes to total: an app's window pids, each with its descendants. Without pids (a compositor
// that doesn't report them), the processes named like one of Names (the app id's last part) stand in.
type Group struct {
	App   string   `json:"app"`
	PIDs  []int    `json:"pids"`
	Names []string `json:"names"`
}

type AppUse struct {
	App      string  `json:"app"`
	CPU      float64 `json:"cpu"`
	Mem      uint64  `json:"mem"`
	MemShare float64 `json:"memShare"`
	Procs    int     `json:"procs"`
	Top      []Proc  `json:"top"` // its busiest processes, at most 5
}

type Sensor struct {
	Chip  string  `json:"chip"`
	Label string  `json:"label"`
	C     float64 `json:"c"`
}

type key struct{ pid, start int64 }

type Sampler struct {
	Proc, Sys, Passwd string // default /proc, /sys, /etc/passwd
	Now               func() time.Time

	mu        sync.Mutex
	last      time.Time
	prevTotal uint64
	prevTicks map[key]uint64
	procs     map[int]*Proc
	cores     int
	users     map[uint32]string
}

func (s *Sampler) root() string { return cmp.Or(s.Proc, "/proc") }
func (s *Sampler) now() time.Time {
	if s.Now != nil {
		return s.Now()
	}
	return time.Now()
}

// sample refreshes the process table unless the last one is under minGap old. Holds s.mu.
func (s *Sampler) sample() {
	now := s.now()
	if !s.last.IsZero() && now.Sub(s.last) < minGap && s.procs != nil {
		return
	}
	s.last = now
	total, cores, btime := s.readStat()
	memTotal := s.memTotal()
	page := uint64(os.Getpagesize())
	dTotal := total - s.prevTotal
	if s.prevTotal == 0 || total < s.prevTotal {
		dTotal = 0
	}
	ticks := map[key]uint64{}
	procs := map[int]*Proc{}
	ents, _ := os.ReadDir(s.root())
	for _, e := range ents {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		dir := filepath.Join(s.root(), e.Name())
		raw, err := os.ReadFile(filepath.Join(dir, "stat"))
		if err != nil {
			continue
		}
		p, t, start, ok := parseStat(raw, page)
		if !ok {
			continue
		}
		p.PID = pid
		p.Start = (btime*clkTck + start) * 1000 / clkTck
		k := key{int64(pid), start}
		ticks[k] = t
		if prev, seen := s.prevTicks[k]; seen && dTotal > 0 && t >= prev {
			p.CPU = float64(t-prev) / float64(dTotal)
		}
		if memTotal > 0 {
			p.MemShare = float64(p.Mem) / float64(memTotal)
		}
		if fi, err := os.Stat(dir); err == nil {
			if st, ok := fi.Sys().(*syscall.Stat_t); ok {
				p.User = s.user(st.Uid)
			}
		}
		procs[pid] = p
	}
	s.prevTotal, s.prevTicks, s.procs, s.cores = total, ticks, procs, cores
}

// parseStat reads /proc/<pid>/stat. Kernel threads are left out (ok false). The command name may hold spaces and
// parentheses, so the fields are counted from the last ')'.
func parseStat(raw []byte, page uint64) (p *Proc, ticks uint64, start int64, ok bool) {
	open, end := bytes.IndexByte(raw, '('), bytes.LastIndexByte(raw, ')')
	if open < 0 || end < open {
		return nil, 0, 0, false
	}
	f := strings.Fields(string(raw[end+1:]))
	// f[0] is field 3 (state); field n is f[n-3].
	if len(f) < 22 {
		return nil, 0, 0, false
	}
	num := func(n int) uint64 { v, _ := strconv.ParseUint(f[n-3], 10, 64); return v }
	if num(9)&pfKthread != 0 {
		return nil, 0, 0, false
	}
	p = &Proc{
		Name:    string(raw[open+1 : end]),
		State:   f[0],
		PPID:    int(num(4)),
		Threads: int(num(20)),
		Mem:     num(24) * page,
	}
	p.Paused = p.State == "T" || p.State == "t"
	return p, num(14) + num(15), int64(num(22)), true
}

// readStat: total jiffies of the "cpu" line, the number of cores, and the boot time in seconds.
func (s *Sampler) readStat() (total uint64, cores int, btime int64) {
	f, err := os.Open(filepath.Join(s.root(), "stat"))
	if err != nil {
		return 0, 0, 0
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "cpu "):
			for _, v := range strings.Fields(line)[1:] {
				n, _ := strconv.ParseUint(v, 10, 64)
				total += n
			}
		case strings.HasPrefix(line, "cpu"):
			cores++
		case strings.HasPrefix(line, "btime "):
			btime, _ = strconv.ParseInt(strings.TrimSpace(line[6:]), 10, 64)
		}
	}
	return total, cores, btime
}

func (s *Sampler) memTotal() uint64 {
	raw, _ := os.ReadFile(filepath.Join(s.root(), "meminfo"))
	for line := range strings.SplitSeq(string(raw), "\n") {
		if rest, ok := strings.CutPrefix(line, "MemTotal:"); ok {
			kb, _ := strconv.ParseUint(strings.TrimSuffix(strings.TrimSpace(rest), " kB"), 10, 64)
			return kb * 1024
		}
	}
	return 0
}

func (s *Sampler) user(uid uint32) string {
	if s.users == nil {
		s.users = map[uint32]string{}
		raw, _ := os.ReadFile(cmp.Or(s.Passwd, "/etc/passwd"))
		for line := range strings.SplitSeq(string(raw), "\n") {
			f := strings.Split(line, ":")
			if len(f) > 2 {
				if n, err := strconv.ParseUint(f[2], 10, 32); err == nil {
					s.users[uint32(n)] = f[0]
				}
			}
		}
	}
	if name, ok := s.users[uid]; ok {
		return name
	}
	return strconv.FormatUint(uint64(uid), 10)
}

func (s *Sampler) cmdline(pid int) string {
	raw, _ := os.ReadFile(filepath.Join(s.root(), strconv.Itoa(pid), "cmdline"))
	return strings.TrimSpace(string(bytes.ReplaceAll(raw, []byte{0}, []byte{' '})))
}

func byUse(a, b *Proc) int {
	if c := cmp.Compare(b.CPU, a.CPU); c != 0 {
		return c
	}
	if c := cmp.Compare(b.Mem, a.Mem); c != 0 {
		return c
	}
	return cmp.Compare(a.PID, b.PID)
}

// Top returns the n busiest processes (by CPU, then memory), with their command lines.
func (s *Sampler) Top(n int) Top {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sample()
	all := make([]*Proc, 0, len(s.procs))
	for _, p := range s.procs {
		all = append(all, p)
	}
	slices.SortFunc(all, byUse)
	n = min(max(n, 1), 50, len(all))
	out := make([]Proc, n)
	for i, p := range all[:n] {
		out[i] = *p
		out[i].Cmd = s.cmdline(p.PID)
	}
	return Top{Procs: out, Count: len(s.procs), Cores: s.cores}
}

// Details returns one process (false when it has gone).
func (s *Sampler) Details(pid int) (Proc, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sample()
	p, ok := s.procs[pid]
	if !ok {
		return Proc{}, false
	}
	out := *p
	out.Cmd = s.cmdline(pid)
	return out, true
}

// Apps totals each group's processes and their descendants. A process is counted once, in the first group that
// reaches it.
func (s *Sampler) Apps(groups []Group) []AppUse {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.sample()
	kids := map[int][]int{}
	for _, p := range s.procs {
		kids[p.PPID] = append(kids[p.PPID], p.PID)
	}
	taken := map[int]bool{}
	out := make([]AppUse, 0, len(groups))
	for _, g := range groups {
		a := AppUse{App: g.App}
		var members []*Proc
		stack := slices.Clone(g.PIDs)
		if len(stack) == 0 {
			for _, p := range s.procs {
				if nameMatches(p.Name, g.Names) {
					stack = append(stack, p.PID)
				}
			}
		}
		for len(stack) > 0 {
			pid := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			p, ok := s.procs[pid]
			if !ok || taken[pid] {
				continue
			}
			taken[pid] = true
			members = append(members, p)
			a.CPU += p.CPU
			a.Mem += p.Mem
			a.MemShare += p.MemShare
			stack = append(stack, kids[pid]...)
		}
		a.Procs = len(members)
		slices.SortFunc(members, byUse)
		for _, p := range members[:min(5, len(members))] {
			a.Top = append(a.Top, *p)
		}
		out = append(out, a)
	}
	slices.SortStableFunc(out, func(x, y AppUse) int { return cmp.Compare(y.CPU, x.CPU) })
	return out
}

// nameMatches: the kernel keeps 15 bytes of a command name.
func nameMatches(comm string, names []string) bool {
	for _, n := range names {
		if n != "" && (strings.EqualFold(comm, n) || len(n) > 15 && strings.EqualFold(comm, n[:15])) {
			return true
		}
	}
	return false
}

// Sensors reads every hwmon temperature; without hwmon, the thermal zones.
func (s *Sampler) Sensors() []Sensor {
	sys := cmp.Or(s.Sys, "/sys")
	var out []Sensor
	inputs, _ := filepath.Glob(filepath.Join(sys, "class/hwmon/hwmon*/temp*_input"))
	for _, in := range inputs {
		dir := filepath.Dir(in)
		c, ok := readMilli(in)
		if !ok {
			continue
		}
		label := strings.TrimSuffix(filepath.Base(in), "_input")
		if l := readTrim(strings.TrimSuffix(in, "_input") + "_label"); l != "" {
			label = l
		}
		out = append(out, Sensor{Chip: readTrim(filepath.Join(dir, "name")), Label: label, C: c})
	}
	if len(out) == 0 {
		zones, _ := filepath.Glob(filepath.Join(sys, "class/thermal/thermal_zone*"))
		for _, z := range zones {
			if c, ok := readMilli(filepath.Join(z, "temp")); ok {
				out = append(out, Sensor{Chip: "thermal", Label: readTrim(filepath.Join(z, "type")), C: c})
			}
		}
	}
	slices.SortStableFunc(out, func(a, b Sensor) int { return cmp.Or(cmp.Compare(a.Chip, b.Chip), cmp.Compare(a.Label, b.Label)) })
	return out
}

func readTrim(path string) string {
	raw, _ := os.ReadFile(path)
	return strings.TrimSpace(string(raw))
}

func readMilli(path string) (float64, bool) {
	n, err := strconv.ParseInt(readTrim(path), 10, 64)
	if err != nil {
		return 0, false
	}
	return float64(n) / 1000, true
}
