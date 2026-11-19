// Package events reads system events once for the shell and pushes them as
// IPC events: udev (USB and block devices, from udevd's netlink group),
// NetworkManager, logind, GameMode and KDE Connect (D-Bus). A source runs only
// while a connection wants it (events.want), so nothing is watched for a
// feature that is off; D-Bus services are never started by watching them.
// They replace the shell's resident nmcli/udevadm/gdbus/dbus-monitor helpers.
package events

import (
	"context"
	"fmt"
	"log"
	"sync"
)

// Push sends an event to the shell (ipc.Server.Broadcast).
type Push func(name string, data any)

// Source runs until ctx ends, pushing its events. An error before it is
// running (no bus, no session) is returned at once; the shell then falls back.
type Source func(ctx context.Context, push Push, ready func()) error

type running struct {
	refs    map[uint64]int
	cancel  context.CancelFunc
	started chan struct{} // closed once it is watching or has failed (err)
	err     error
}

// Manager starts a source on its first want and stops it after the last.
type Manager struct {
	Push    Push
	Sources map[string]Source

	mu  sync.Mutex
	run map[string]*running
}

// Want adds (on) or drops one want of a source for a connection. Starting a
// source waits until it is watching (or failed): the shell's fallback only
// stops once anod really delivers.
func (m *Manager) Want(conn uint64, name string, on bool) error {
	src, ok := m.Sources[name]
	if !ok {
		return fmt.Errorf("unknown event source %q", name)
	}
	m.mu.Lock()
	if m.run == nil {
		m.run = map[string]*running{}
	}
	r := m.run[name]
	if !on {
		if r != nil && r.refs[conn] > 0 {
			if r.refs[conn]--; r.refs[conn] == 0 {
				delete(r.refs, conn)
			}
			m.stopIfUnused(name, r)
		}
		m.mu.Unlock()
		return nil
	}
	if r != nil {
		// Running or starting: wait for the start, so a failed one is reported to every asker.
		r.refs[conn]++
		m.mu.Unlock()
		<-r.started
		return r.err
	}
	ctx, cancel := context.WithCancel(context.Background())
	r = &running{refs: map[uint64]int{conn: 1}, cancel: cancel, started: make(chan struct{})}
	m.run[name] = r
	m.mu.Unlock()

	var once sync.Once
	done := func(err error) {
		once.Do(func() {
			r.err = err
			close(r.started)
		})
	}
	go func() {
		err := src(ctx, func(n string, d any) { m.Push(n, d) }, func() { done(nil) })
		if err != nil && ctx.Err() == nil {
			log.Printf("events: %s: %v", name, err)
		}
		wasRunning := r.err == nil && isClosed(r.started)
		done(err)
		m.mu.Lock()
		if m.run[name] == r {
			delete(m.run, name)
		}
		m.mu.Unlock()
		// Ended on its own after it was watching (the bus went away): the
		// shell asks again or goes back to its own watcher.
		if wasRunning && ctx.Err() == nil {
			m.Push("events_lost", map[string]string{"source": name})
		}
	}()
	<-r.started
	if r.err != nil {
		cancel()
	}
	return r.err
}

func isClosed(c chan struct{}) bool {
	select {
	case <-c:
		return true
	default:
		return false
	}
}

func (m *Manager) stopIfUnused(name string, r *running) {
	if len(r.refs) == 0 {
		r.cancel()
		delete(m.run, name)
	}
}

// Drop releases every want of a closed connection.
func (m *Manager) Drop(conn uint64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	for name, r := range m.run {
		if r.refs[conn] > 0 {
			delete(r.refs, conn)
			m.stopIfUnused(name, r)
		}
	}
}

// Running lists the sources running now (for status and tests).
func (m *Manager) Running() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]string, 0, len(m.run))
	for n := range m.run {
		out = append(out, n)
	}
	return out
}
