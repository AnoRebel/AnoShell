package gpu

import (
	"bufio"
	"bytes"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type fdRef struct{ pid, fd string }

// counter is one engine of one DRM client: i915 reports busy nanoseconds,
// xe busy cycles against a total-cycles clock; capacity is the engine count.
type counter struct {
	ns, cycles, total, capacity uint64
}

// engineTimes: client id → engine → counter, for one device.
type engineTimes map[string]map[string]counter

// readClients reads the DRM clients' engine counters, per PCI device. Every
// process's fds are walked once a minute (34 ms for ~750 processes here);
// every 10 s only the processes started since; in between only the DRM
// fdinfo files are read. ponytail: an app already running that opens the GPU
// later is counted from the next full walk, up to a minute late.
func (s *Sampler) readClients(now time.Time) map[string]engineTimes {
	switch {
	case s.fullAt.IsZero() || now.Sub(s.fullAt) > time.Minute:
		s.scanFds(nil)
		s.fullAt, s.fdsAt = now, now
	case now.Sub(s.fdsAt) > 10*time.Second:
		s.scanFds(s.seen)
		s.fdsAt = now
	}
	out := map[string]engineTimes{}
	kept := s.fds[:0]
	read := map[string]bool{} // client ids read this time (a client often holds several fds)
	ids := map[fdRef]string{}
	for _, r := range s.fds {
		if id, ok := s.fdID[r]; ok && read[id] {
			kept, ids[r] = append(kept, r), id
			continue
		}
		raw, err := os.ReadFile(s.proc(r.pid + "/fdinfo/" + r.fd))
		if err != nil {
			continue // gone
		}
		kept = append(kept, r)
		pdev, id, engines := parseFdinfo(raw)
		if pdev == "" || id == "" || len(engines) == 0 {
			continue
		}
		ids[r], read[id] = id, true
		if out[pdev] == nil {
			out[pdev] = engineTimes{}
		}
		out[pdev][id] = engines // the same client on several fds: the same counters
	}
	s.fds, s.fdID = kept, ids
	return out
}

// scanFds finds the fds pointing at /dev/dri in the processes we may read:
// all of them (skip nil), or only those not in skip (added to the list).
func (s *Sampler) scanFds(skip map[string]bool) {
	if skip == nil {
		s.fds = s.fds[:0]
	}
	seen := map[string]bool{}
	procs, _ := os.ReadDir(s.proc(""))
	for _, p := range procs {
		pid := p.Name()
		if pid[0] < '0' || pid[0] > '9' {
			continue
		}
		seen[pid] = true
		if skip[pid] {
			continue
		}
		dir := s.proc(pid + "/fd")
		fds, err := os.ReadDir(dir)
		if err != nil {
			continue // another user's: not ours to read
		}
		for _, f := range fds {
			if l, err := os.Readlink(filepath.Join(dir, f.Name())); err == nil && strings.HasPrefix(l, "/dev/dri/") {
				s.fds = append(s.fds, fdRef{pid, f.Name()})
			}
		}
	}
	s.seen = seen
}

func parseFdinfo(raw []byte) (pdev, id string, engines map[string]counter) {
	engines = map[string]counter{}
	sc := bufio.NewScanner(bytes.NewReader(raw))
	for sc.Scan() {
		k, v, ok := strings.Cut(sc.Text(), ":")
		if !ok {
			continue
		}
		v = strings.TrimSpace(v)
		num := func() uint64 { n, _ := strconv.ParseUint(strings.Fields(v + " 0")[0], 10, 64); return n }
		set := func(e string, f func(*counter)) {
			c := engines[e]
			f(&c)
			engines[e] = c
		}
		switch {
		case k == "drm-pdev":
			pdev = v
		case k == "drm-client-id":
			id = v
		case strings.HasPrefix(k, "drm-engine-capacity-"):
			n := num()
			set(strings.TrimPrefix(k, "drm-engine-capacity-"), func(c *counter) { c.capacity = n })
		case strings.HasPrefix(k, "drm-engine-"):
			n := num()
			set(strings.TrimPrefix(k, "drm-engine-"), func(c *counter) { c.ns = n })
		case strings.HasPrefix(k, "drm-total-cycles-"):
			n := num()
			set(strings.TrimPrefix(k, "drm-total-cycles-"), func(c *counter) { c.total = n })
		case strings.HasPrefix(k, "drm-cycles-"):
			n := num()
			set(strings.TrimPrefix(k, "drm-cycles-"), func(c *counter) { c.cycles = n })
		}
	}
	return pdev, id, engines
}

// busy is the busiest engine class over the interval, 0..100. Clients seen
// only now count from the next sample (their totals cover their whole life).
func busy(prev, now engineTimes, dt time.Duration) (float64, bool) {
	if prev == nil || dt <= 0 || dt > 30*time.Second {
		return 0, false
	}
	type acc struct{ ns, cycles, total, capacity uint64 }
	per := map[string]*acc{}
	for id, engines := range now {
		before, ok := prev[id]
		if !ok {
			continue
		}
		for e, c := range engines {
			b, ok := before[e]
			if !ok {
				continue
			}
			a := per[e]
			if a == nil {
				a = &acc{}
				per[e] = a
			}
			a.capacity = max(a.capacity, c.capacity, 1)
			if c.ns >= b.ns {
				a.ns += c.ns - b.ns
			}
			if c.cycles >= b.cycles {
				a.cycles += c.cycles - b.cycles
			}
			if c.total > b.total {
				a.total = max(a.total, c.total-b.total)
			}
		}
	}
	best := 0.0
	for _, a := range per {
		u := 0.0
		if a.total > 0 {
			u = float64(a.cycles) / float64(a.total*a.capacity)
		} else {
			u = float64(a.ns) / (float64(dt.Nanoseconds()) * float64(a.capacity))
		}
		best = max(best, u)
	}
	return min(best*100, 100), true
}
