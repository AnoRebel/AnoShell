// Package gpu reads GPU load, clock, memory and temperature without root:
// amdgpu from its sysfs counters; Intel (i915, xe) from the engine time each
// DRM client reports in /proc/<pid>/fdinfo (the way nvtop does it); NVIDIA
// from one resident `nvidia-smi -lms` while sampling. A figure the hardware
// doesn't report is nil.
package gpu

import (
	"bufio"
	"cmp"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
)

type GPU struct {
	Card       string   `json:"card"` // card1
	PCI        string   `json:"pci"`  // 0000:00:02.0
	Vendor     string   `json:"vendor"`
	Driver     string   `json:"driver"`
	Name       string   `json:"name"`
	Integrated bool     `json:"integrated"`
	Shown      bool     `json:"shown"` // the one the shell shows (vitals.gpu_card, else discrete, else first)
	Load       *float64 `json:"load"`  // 0..100
	MHz        *float64 `json:"mhz"`
	MinMHz     *float64 `json:"minMHz"`
	MaxMHz     *float64 `json:"maxMHz"`
	MemUsed    *uint64  `json:"memUsed"` // bytes, dedicated memory
	MemTotal   *uint64  `json:"memTotal"`
	Temp       *float64 `json:"temp"` // °C
	Note       string   `json:"note,omitempty"`
}

type card struct {
	GPU
	dev string // /sys/class/drm/cardN/device
	dir string // /sys/class/drm/cardN
}

// Sampler is not safe for concurrent use.
type Sampler struct {
	Proc, Sys string        // roots, for tests
	PCIIDs    string        // pci.ids path, for names
	Want      func() string // configured card (vitals.gpu_card), may be nil
	LookPath  func(string) (string, error)

	cards  []card
	found  time.Time
	fds    []fdRef // DRM fds of readable processes
	fdsAt  time.Time
	fullAt time.Time              // last walk of every process
	seen   map[string]bool        // pids walked so far
	names  map[string]string      // vendor:device → pci.ids name (never changes)
	fdID   map[fdRef]string       // fd → its DRM client id, from the last read
	prev   map[string]engineTimes // pdev → per client id → engine → value
	prevAt time.Time
	nv     *nvidia
}

func (s *Sampler) sys(p string) string  { return filepath.Join(cmp.Or(s.Sys, "/sys"), p) }
func (s *Sampler) proc(p string) string { return filepath.Join(cmp.Or(s.Proc, "/proc"), p) }

var cardRe = regexp.MustCompile(`^card[0-9]+$`)

// Cards looks the GPUs up afresh (a changed vitals.gpu_card applies at once);
// samples look them up again every minute.
func (s *Sampler) Cards(now time.Time) []GPU {
	s.found = time.Time{}
	s.discover(now)
	out := make([]GPU, len(s.cards))
	for i, c := range s.cards {
		out[i] = c.GPU
	}
	return out
}

func (s *Sampler) discover(now time.Time) {
	if !s.found.IsZero() && now.Sub(s.found) < time.Minute {
		return
	}
	s.found = now
	entries, _ := os.ReadDir(s.sys("class/drm"))
	var cards []card
	for _, e := range entries {
		if !cardRe.MatchString(e.Name()) {
			continue
		}
		dir := s.sys("class/drm/" + e.Name())
		dev := filepath.Join(dir, "device")
		vendor := readTrim(filepath.Join(dev, "vendor"))
		if vendor == "" {
			continue
		}
		link, _ := os.Readlink(dev)
		drv, _ := os.Readlink(filepath.Join(dev, "driver"))
		c := card{dev: dev, dir: dir}
		c.Card, c.PCI, c.Driver = e.Name(), filepath.Base(link), filepath.Base(drv)
		switch vendor {
		case "0x1002":
			c.Vendor = "AMD"
		case "0x8086":
			c.Vendor = "Intel"
		case "0x10de":
			c.Vendor = "NVIDIA"
		default:
			c.Vendor = vendor
		}
		devID := readTrim(filepath.Join(dev, "device"))
		if s.names == nil {
			s.names = map[string]string{}
		}
		name, ok := s.names[vendor+":"+devID]
		if !ok {
			name = s.pciName(vendor, devID)
			s.names[vendor+":"+devID] = name
		}
		c.Name = name
		if c.Name == "" {
			c.Name = c.Vendor + " GPU"
		}
		if v, ok := readUint(filepath.Join(dev, "mem_info_vram_total")); ok && v > 0 {
			c.MemTotal = &v
		}
		// Integrated: Intel without its own memory (i915/xe report none here), or an AMD APU's small carve-out.
		c.Integrated = c.Vendor == "Intel" || (c.Vendor == "AMD" && (c.MemTotal == nil || *c.MemTotal <= 1<<30))
		cards = append(cards, c)
	}
	// The shown one: configured, else the largest dedicated memory (a discrete card), else the first.
	want := ""
	if s.Want != nil {
		want = s.Want()
	}
	pick := -1
	for i, c := range cards {
		if want != "" && (c.Card == want || c.PCI == want) {
			pick = i
		}
	}
	if pick < 0 {
		var best uint64
		for i, c := range cards {
			m := uint64(0)
			if c.MemTotal != nil {
				m = *c.MemTotal
			}
			if !c.Integrated && (pick < 0 || m > best) {
				pick, best = i, m
			}
		}
	}
	if pick < 0 && len(cards) > 0 {
		pick = 0
	}
	for i := range cards {
		cards[i].Shown = i == pick
	}
	s.cards = cards
}

// pciName looks a device up in pci.ids ("Alder Lake-UP3 GT2 [Iris Xe Graphics]").
func (s *Sampler) pciName(vendor, device string) string {
	path := cmp.Or(s.PCIIDs, "/usr/share/hwdata/pci.ids")
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	v, d := strings.TrimPrefix(vendor, "0x"), strings.TrimPrefix(device, "0x")
	in := false
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		if line[0] != '\t' {
			if in {
				return ""
			}
			in = strings.HasPrefix(line, v+"  ")
			continue
		}
		if in && len(line) > 1 && line[1] != '\t' && strings.HasPrefix(line[1:], d+"  ") {
			return strings.TrimSpace(line[1+len(d)+2:])
		}
	}
	return ""
}

// Read samples every GPU.
func (s *Sampler) Read(now time.Time, interval time.Duration) []GPU {
	s.discover(now)
	// The fd walk is the costly part: only for an Intel card that is shown
	// (a hybrid laptop showing its discrete GPU doesn't pay for it).
	needFds := false
	for _, c := range s.cards {
		if c.Vendor == "Intel" && c.Shown {
			needFds = true
		}
	}
	var clients map[string]engineTimes
	if needFds {
		clients = s.readClients(now)
	}
	dt := now.Sub(s.prevAt)
	out := make([]GPU, len(s.cards))
	for i, c := range s.cards {
		g := c.GPU
		switch {
		case c.Driver == "amdgpu":
			s.readAMD(c, &g)
		case c.Vendor == "Intel":
			s.readIntel(c, &g, clients[c.PCI], dt) // no load unless shown (clients is nil)
		case c.Vendor == "NVIDIA":
			s.readNvidia(&g, interval)
		}
		g.Temp = cmp.Or(g.Temp, hwmonTemp(c.dev))
		out[i] = g
	}
	s.prev, s.prevAt = clients, now
	return out
}

// Stop ends what runs between samples (nvidia-smi).
func (s *Sampler) Stop() {
	if s.nv != nil {
		s.nv.stop()
		s.nv = nil
	}
	s.prev = nil
}

func (s *Sampler) readAMD(c card, g *GPU) {
	if v, ok := readUint(filepath.Join(c.dev, "gpu_busy_percent")); ok {
		f := float64(v)
		g.Load = &f
	}
	if v, ok := readUint(filepath.Join(c.dev, "mem_info_vram_used")); ok {
		g.MemUsed = &v
	}
	// pp_dpm_sclk: "0: 500Mhz\n1: 1200Mhz *\n2: 2400Mhz": the starred level now, the first and last the range.
	var levels []float64
	for _, line := range strings.Split(readTrim(filepath.Join(c.dev, "pp_dpm_sclk")), "\n") {
		_, rest, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		f := strings.Fields(rest)
		if len(f) == 0 {
			continue
		}
		mhz, err := strconv.ParseFloat(strings.TrimSuffix(strings.ToLower(f[0]), "mhz"), 64)
		if err != nil {
			continue
		}
		levels = append(levels, mhz)
		if len(f) > 1 && f[1] == "*" {
			v := mhz
			g.MHz = &v
		}
	}
	if len(levels) > 0 {
		lo, hi := slices.Min(levels), slices.Max(levels)
		g.MinMHz, g.MaxMHz = &lo, &hi
	}
}

func (s *Sampler) readIntel(c card, g *GPU, now engineTimes, dt time.Duration) {
	// i915: card's gt_act_freq_mhz (or gt/gt0/rps_*); xe: device/tile0/gt0/freq0/*.
	for _, set := range [][3]string{
		{"gt_act_freq_mhz", "gt_min_freq_mhz", "gt_max_freq_mhz"},
		{"gt/gt0/rps_act_freq_mhz", "gt/gt0/rps_min_freq_mhz", "gt/gt0/rps_max_freq_mhz"},
		{"device/tile0/gt0/freq0/act_freq", "device/tile0/gt0/freq0/min_freq", "device/tile0/gt0/freq0/max_freq"},
	} {
		if v, ok := readUint(filepath.Join(c.dir, set[0])); ok {
			a := float64(v)
			g.MHz = &a
			if lo, ok := readUint(filepath.Join(c.dir, set[1])); ok {
				f := float64(lo)
				g.MinMHz = &f
			}
			if hi, ok := readUint(filepath.Join(c.dir, set[2])); ok {
				f := float64(hi)
				g.MaxMHz = &f
			}
			break
		}
	}
	if load, ok := busy(s.prev[c.PCI], now, dt); ok {
		g.Load = &load
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

// hwmonTemp: the card's own temperature sensor (amdgpu edge, discrete Intel), nil without one.
func hwmonTemp(dev string) *float64 {
	ins, _ := filepath.Glob(filepath.Join(dev, "hwmon/hwmon*/temp1_input"))
	for _, in := range ins {
		if v, ok := readUint(in); ok {
			c := float64(v) / 1000
			return &c
		}
	}
	return nil
}
