package gpu

import (
	"bufio"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"time"
)

// nvidia is one `nvidia-smi --query-gpu=… -lms <interval>` running while
// sampling: a line per card per interval, read as it comes (no spawn per sample).
type nvidia struct {
	cmd      *exec.Cmd
	interval time.Duration
	mu       sync.Mutex
	last     map[string]nvRow // pci → latest row
}

type nvRow struct {
	load, memUsed, memTotal, temp, mhz, maxMHz *float64
}

const nvQuery = "pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,clocks.gr,clocks.max.gr"

func (s *Sampler) readNvidia(g *GPU, interval time.Duration) {
	look := s.LookPath
	if look == nil {
		look = exec.LookPath
	}
	bin, err := look("nvidia-smi")
	if err != nil {
		g.Note = "no figures (install nvidia-utils)"
		return
	}
	if s.nv != nil && s.nv.interval != interval {
		s.nv.stop()
		s.nv = nil
	}
	if s.nv == nil {
		s.nv = startNvidia(bin, interval)
	}
	if s.nv == nil {
		return
	}
	s.nv.mu.Lock()
	r, ok := s.nv.last[strings.ToLower(g.PCI)]
	s.nv.mu.Unlock()
	if !ok {
		return
	}
	g.Load, g.Temp = r.load, r.temp
	g.MHz, g.MaxMHz = r.mhz, r.maxMHz
	if r.memUsed != nil {
		v := uint64(*r.memUsed * 1024 * 1024) // MiB
		g.MemUsed = &v
	}
	if r.memTotal != nil {
		v := uint64(*r.memTotal * 1024 * 1024)
		g.MemTotal = &v
	}
}

func startNvidia(bin string, interval time.Duration) *nvidia {
	n := &nvidia{interval: interval, last: map[string]nvRow{}}
	n.cmd = exec.Command(bin, "--query-gpu="+nvQuery, "--format=csv,noheader,nounits", "-lms", strconv.Itoa(int(interval/time.Millisecond)))
	out, err := n.cmd.StdoutPipe()
	if err != nil {
		return nil
	}
	if err := n.cmd.Start(); err != nil {
		return nil
	}
	go func() {
		sc := bufio.NewScanner(out)
		for sc.Scan() {
			if pci, r, ok := parseNvLine(sc.Text()); ok {
				n.mu.Lock()
				n.last[pci] = r
				n.mu.Unlock()
			}
		}
		n.cmd.Wait()
	}()
	return n
}

func (n *nvidia) stop() {
	if n.cmd != nil && n.cmd.Process != nil {
		n.cmd.Process.Kill()
	}
}

// parseNvLine: "00000000:01:00.0, 37, 1024, 8192, 54, 1410, 2100" ("[N/A]" fields are nil).
func parseNvLine(line string) (string, nvRow, bool) {
	f := strings.Split(line, ",")
	if len(f) < 7 {
		return "", nvRow{}, false
	}
	num := func(s string) *float64 {
		v, err := strconv.ParseFloat(strings.TrimSpace(s), 64)
		if err != nil {
			return nil
		}
		return &v
	}
	return normPCI(strings.TrimSpace(f[0])), nvRow{num(f[1]), num(f[2]), num(f[3]), num(f[4]), num(f[5]), num(f[6])}, true
}

// normPCI turns nvidia-smi's 8-digit domain into sysfs's 4 ("00000000:01:00.0" → "0000:01:00.0").
func normPCI(id string) string {
	id = strings.ToLower(id)
	dom, rest, ok := strings.Cut(id, ":")
	if !ok {
		return id
	}
	if len(dom) > 4 {
		dom = dom[len(dom)-4:]
	}
	return dom + ":" + rest
}
