// Package stats samples the machine for the shell (CPU, memory, network,
// temperature, disks) while something on screen shows it, and hands each
// sample to a push function. One sampler replaces the shell's own /proc
// readers (services/ResourceUsage.qml, services/NetworkUsage.qml and
// pieces/_bioma/SystemMonitor.qml).
package stats

import (
	"bytes"
	"cmp"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// CPU: Total and Cores are 0..1, nil/empty until two readings exist.
type CPU struct {
	Total  *float64  `json:"total"`
	Cores  []float64 `json:"cores"`
	Count  int       `json:"count"`
	MHz    float64   `json:"mhz"`    // average current clock, 0 when unknown
	MinMHz float64   `json:"minMHz"` // cpu0's range, 0 when unknown
	MaxMHz float64   `json:"maxMHz"`
}

type Mem struct {
	TotalKB     uint64 `json:"totalKB"`
	AvailKB     uint64 `json:"availKB"`
	SwapTotalKB uint64 `json:"swapTotalKB"`
	SwapFreeKB  uint64 `json:"swapFreeKB"`
}

// Net counts the machine's own links (virtual ones carry the same traffic
// again). Rx/Tx are bytes per second, nil until two readings exist or when a
// counter went backwards (a link left).
type Net struct {
	Rx      *float64 `json:"rx"`
	Tx      *float64 `json:"tx"`
	RxBytes uint64   `json:"rxBytes"`
	TxBytes uint64   `json:"txBytes"`
	Links   int      `json:"links"`
}

type Temp struct {
	C      *float64 `json:"c"`
	Sensor string   `json:"sensor"` // chip/label or zone type
}

type Disk struct {
	Mount string `json:"mount"`
	Size  uint64 `json:"size"`
	Used  uint64 `json:"used"`
}

type Sample struct {
	T        int64  `json:"t"` // unix ms
	Interval int    `json:"interval"`
	CPU      CPU    `json:"cpu"`
	Mem      Mem    `json:"mem"`
	Net      Net    `json:"net"`
	Temp     Temp   `json:"temp"`
	Disks    []Disk `json:"disks"`
	GPUs     []any  `json:"gpus"`
}

// VirtualLinks are left out of the network figures (as the Bioma monitor did).
var VirtualLinks = regexp.MustCompile(`^(lo|veth|docker|br-|virbr|vnet|tun|tap|wg|tailscale|zt|vboxnet|vmnet|nm-|dummy|bond|team)`)

type cpuTicks struct{ total, idle uint64 }

// Reader turns two consecutive readings into rates. Not safe for concurrent use.
type Reader struct {
	Proc, Sys string        // roots, for tests ("/proc", "/sys" when empty)
	Mounts    []string      // disks to report ("/" when empty)
	Sensor    func() string // a configured sensor (substring of its path), may be nil

	prevCPU  []cpuTicks // [0] total, then cores
	prevNet  *[2]uint64
	prevT    time.Time
	tempPath string
	tempName string
	probed   time.Time
}

func (r *Reader) proc(p string) string { return filepath.Join(cmp.Or(r.Proc, "/proc"), p) }
func (r *Reader) sys(p string) string  { return filepath.Join(cmp.Or(r.Sys, "/sys"), p) }

// Reset forgets the previous reading: after a pause, the next rates would
// otherwise be an average over the whole pause.
func (r *Reader) Reset() { r.prevCPU, r.prevNet = nil, nil }

func (r *Reader) read(path string) []byte {
	b, _ := os.ReadFile(path)
	return b
}

// Read takes one sample.
func (r *Reader) Read(now time.Time) Sample {
	s := Sample{T: now.UnixMilli()}
	dt := now.Sub(r.prevT).Seconds()
	r.readCPU(&s.CPU)
	r.readMem(&s.Mem)
	r.readNet(&s.Net, dt)
	r.readTemp(&s.Temp, now)
	mounts := r.Mounts
	if len(mounts) == 0 {
		mounts = []string{"/"}
	}
	for _, m := range mounts {
		var st unix.Statfs_t
		if unix.Statfs(m, &st) == nil && st.Blocks > 0 {
			bs := uint64(st.Bsize)
			s.Disks = append(s.Disks, Disk{Mount: m, Size: st.Blocks * bs, Used: (st.Blocks - st.Bfree) * bs})
		}
	}
	r.prevT = now
	return s
}

func (r *Reader) readCPU(c *CPU) {
	raw := r.read(r.proc("stat"))
	var cur []cpuTicks
	for _, line := range bytes.Split(raw, []byte{'\n'}) {
		if !bytes.HasPrefix(line, []byte("cpu")) {
			break // the cpu lines come first
		}
		f := strings.Fields(string(line))
		if len(f) < 6 {
			continue
		}
		var t cpuTicks
		for i, v := range f[1:min(len(f), 8)] { // user..softirq, as top counts
			n, _ := strconv.ParseUint(v, 10, 64)
			t.total += n
			if i == 3 || i == 4 { // idle + iowait
				t.idle += n
			}
		}
		cur = append(cur, t)
	}
	if len(cur) == 0 {
		return
	}
	c.Count = len(cur) - 1
	if len(r.prevCPU) == len(cur) {
		use := func(a, b cpuTicks) float64 {
			if b.total <= a.total {
				return 0
			}
			return 1 - float64(b.idle-a.idle)/float64(b.total-a.total)
		}
		t := use(r.prevCPU[0], cur[0])
		c.Total = &t
		c.Cores = make([]float64, c.Count)
		for i := range c.Count {
			c.Cores[i] = use(r.prevCPU[i+1], cur[i+1])
		}
	}
	r.prevCPU = cur
	var sum float64
	var n int
	for i := range c.Count {
		if khz, ok := readUint(r.sys("devices/system/cpu/cpu" + strconv.Itoa(i) + "/cpufreq/scaling_cur_freq")); ok {
			sum += float64(khz) / 1000
			n++
		}
	}
	if n > 0 {
		c.MHz = sum / float64(n)
	}
	if v, ok := readUint(r.sys("devices/system/cpu/cpu0/cpufreq/cpuinfo_min_freq")); ok {
		c.MinMHz = float64(v) / 1000
	}
	if v, ok := readUint(r.sys("devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")); ok {
		c.MaxMHz = float64(v) / 1000
	}
}

func (r *Reader) readMem(m *Mem) {
	for _, line := range bytes.Split(r.read(r.proc("meminfo")), []byte{'\n'}) {
		k, v, ok := bytes.Cut(line, []byte{':'})
		if !ok {
			continue
		}
		n, _ := strconv.ParseUint(strings.Fields(string(v) + " 0")[0], 10, 64)
		switch string(k) {
		case "MemTotal":
			m.TotalKB = n
		case "MemAvailable":
			m.AvailKB = n
		case "SwapTotal":
			m.SwapTotalKB = n
		case "SwapFree":
			m.SwapFreeKB = n
		}
	}
}

func (r *Reader) readNet(n *Net, dt float64) {
	var rx, tx uint64
	for _, line := range bytes.Split(r.read(r.proc("net/dev")), []byte{'\n'}) {
		name, rest, ok := bytes.Cut(line, []byte{':'})
		if !ok {
			continue
		}
		if VirtualLinks.Match(bytes.TrimSpace(name)) {
			continue
		}
		f := strings.Fields(string(rest))
		if len(f) < 9 {
			continue
		}
		a, _ := strconv.ParseUint(f[0], 10, 64)
		b, _ := strconv.ParseUint(f[8], 10, 64)
		rx, tx = rx+a, tx+b
		n.Links++
	}
	n.RxBytes, n.TxBytes = rx, tx
	if p := r.prevNet; p != nil && dt > 0 && rx >= p[0] && tx >= p[1] {
		a, b := float64(rx-p[0])/dt, float64(tx-p[1])/dt
		n.Rx, n.Tx = &a, &b
	}
	r.prevNet = &[2]uint64{rx, tx}
}

// sensor is one temperature input found by probe.
type sensor struct{ kind, name, label, path string }

// probeTemp picks the CPU temperature input: a configured one (a substring of
// its path), else in order of trust the vendor's package sensor, then the
// thermal zones.
func (r *Reader) probeTemp() {
	var found []sensor
	hw, _ := filepath.Glob(r.sys("class/hwmon/hwmon*"))
	for _, h := range hw {
		name := readTrim(filepath.Join(h, "name"))
		ins, _ := filepath.Glob(filepath.Join(h, "temp*_input"))
		for _, in := range ins {
			found = append(found, sensor{"hwmon", name, readTrim(strings.TrimSuffix(in, "_input") + "_label"), in})
		}
	}
	zones, _ := filepath.Glob(r.sys("class/thermal/thermal_zone*"))
	for _, z := range zones {
		if _, err := os.Stat(filepath.Join(z, "temp")); err == nil {
			found = append(found, sensor{"zone", readTrim(filepath.Join(z, "type")), "", filepath.Join(z, "temp")})
		}
	}
	tests := []func(s sensor) bool{
		func(s sensor) bool { return s.name == "k10temp" && s.label == "Tctl" },
		func(s sensor) bool { return s.name == "zenpower" && s.label == "Tdie" },
		func(s sensor) bool { return s.name == "k10temp" },
		func(s sensor) bool { return s.name == "coretemp" && strings.HasPrefix(s.label, "Package") },
		func(s sensor) bool { return s.kind == "zone" && s.name == "x86_pkg_temp" },
		func(s sensor) bool { return s.kind == "zone" && strings.HasPrefix(s.name, "cpu") },
		func(s sensor) bool { return s.kind == "zone" && s.name == "acpitz" },
		func(s sensor) bool { return true },
	}
	if r.Sensor != nil {
		if want := r.Sensor(); want != "" {
			tests = append([]func(s sensor) bool{func(s sensor) bool { return strings.Contains(s.path, want) }}, tests...)
		}
	}
	r.tempPath, r.tempName = "", ""
	for _, t := range tests {
		for _, s := range found {
			if t(s) {
				r.tempPath, r.tempName = s.path, strings.Trim(s.name+"/"+s.label, "/")
				return
			}
		}
	}
}

func (r *Reader) readTemp(t *Temp, now time.Time) {
	// Sensors don't come and go: look again only every few minutes.
	if r.probed.IsZero() || now.Sub(r.probed) > 5*time.Minute {
		r.probeTemp()
		r.probed = now
	}
	if r.tempPath == "" {
		return
	}
	if v, ok := readUint(r.tempPath); ok {
		c := float64(v) / 1000
		t.C, t.Sensor = &c, r.tempName
	}
}

func readTrim(path string) string {
	b, _ := os.ReadFile(path)
	return strings.TrimSpace(string(b))
}

func readUint(path string) (uint64, bool) {
	n, err := strconv.ParseUint(readTrim(path), 10, 64)
	return n, err == nil
}
