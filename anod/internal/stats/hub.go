package stats

import (
	"context"
	"log"
	"sync"
	"time"
)

type lease struct {
	conn     uint64
	interval time.Duration
}

// Hub samples while at least one lease is held, at the shortest leased
// interval, and pushes each sample. Leases belong to a connection: Drop
// releases a connection's leases when it closes (a shell restart or crash).
type Hub struct {
	Reader *Reader
	Push   func(Sample)
	Now    func() time.Time // for tests

	mu     sync.Mutex
	leases map[uint64]lease
	next   uint64
	wake   chan struct{}
	// Extra, if set, adds to each sample before it is pushed (the GPUs).
	Extra func(*Sample)
}

func NewHub(r *Reader, push func(Sample)) *Hub {
	return &Hub{Reader: r, Push: push, leases: map[uint64]lease{}, wake: make(chan struct{}, 1)}
}

// Intervals are clamped to 0.5–10 s.
func clampInterval(ms int) time.Duration {
	return time.Duration(min(max(ms, 500), 10000)) * time.Millisecond
}

// Watch adds a lease and returns its id.
func (h *Hub) Watch(conn uint64, ms int) uint64 {
	h.mu.Lock()
	h.next++
	id := h.next
	h.leases[id] = lease{conn, clampInterval(ms)}
	h.mu.Unlock()
	h.poke()
	return id
}

// Unwatch releases a lease (unknown ids are ignored).
func (h *Hub) Unwatch(id uint64) {
	h.mu.Lock()
	delete(h.leases, id)
	h.mu.Unlock()
	h.poke()
}

// Drop releases every lease of a connection.
func (h *Hub) Drop(conn uint64) {
	h.mu.Lock()
	for id, l := range h.leases {
		if l.conn == conn {
			delete(h.leases, id)
		}
	}
	h.mu.Unlock()
	h.poke()
}

func (h *Hub) poke() {
	select {
	case h.wake <- struct{}{}:
	default:
	}
}

// interval is the shortest leased one, 0 when nothing is leased.
func (h *Hub) interval() time.Duration {
	h.mu.Lock()
	defer h.mu.Unlock()
	var d time.Duration
	for _, l := range h.leases {
		if d == 0 || l.interval < d {
			d = l.interval
		}
	}
	return d
}

func (h *Hub) now() time.Time {
	if h.Now != nil {
		return h.Now()
	}
	return time.Now()
}

// Run samples until ctx ends.
func (h *Hub) Run(ctx context.Context) {
	var t *time.Timer
	stop := func() {
		if t != nil {
			t.Stop()
			t = nil
		}
	}
	defer stop()
	running := false
	var logged time.Duration // 0: nothing logged at start
	for {
		d := h.interval()
		if d != logged {
			if d == 0 {
				log.Printf("stats: no view shows them, sampling stopped")
			} else {
				log.Printf("stats: sampling every %v", d)
			}
			logged = d
		}
		var tick <-chan time.Time
		switch {
		case d == 0:
			if running {
				h.Reader.Reset() // rates after a pause must not average over it
				running = false
			}
			stop()
		case !running:
			running = true
			h.sample(d) // the first sample at once (rates pending)
			stop()
			t = time.NewTimer(d)
		case t == nil:
			t = time.NewTimer(d)
		}
		if t != nil {
			tick = t.C
		}
		select {
		case <-ctx.Done():
			return
		case <-h.wake:
			// A changed lease set: a shorter interval takes effect now.
			if nd := h.interval(); nd != 0 && nd != d && running {
				stop()
				t = time.NewTimer(nd)
			}
		case <-tick:
			h.sample(d)
			t = time.NewTimer(d)
		}
	}
}

func (h *Hub) sample(d time.Duration) {
	s := h.Reader.Read(h.now())
	s.Interval = int(d / time.Millisecond)
	if h.Extra != nil {
		h.Extra(&s)
	}
	h.Push(s)
}
