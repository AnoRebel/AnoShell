package events

import (
	"context"
	"encoding/binary"
	"errors"
	"slices"
	"sync"
	"testing"
	"time"
)

type pushed struct {
	mu  sync.Mutex
	got []string
}

func (p *pushed) push(n string, d any) {
	p.mu.Lock()
	p.got = append(p.got, n)
	p.mu.Unlock()
}

func (p *pushed) has(n string) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return slices.Contains(p.got, n)
}

func TestManagerRefsAndDrop(t *testing.T) {
	starts := 0
	var mu sync.Mutex
	src := func(ctx context.Context, push Push, ready func()) error {
		mu.Lock()
		starts++
		mu.Unlock()
		ready()
		<-ctx.Done()
		return nil
	}
	p := &pushed{}
	m := &Manager{Push: p.push, Sources: map[string]Source{"s": src}}
	if err := m.Want(1, "s", true); err != nil {
		t.Fatal(err)
	}
	m.Want(2, "s", true)
	if starts != 1 || len(m.Running()) != 1 {
		t.Fatalf("one start for two wants: %d %v", starts, m.Running())
	}
	m.Want(1, "s", false)
	if len(m.Running()) != 1 {
		t.Fatal("still wanted by 2")
	}
	m.Drop(2) // the connection closed
	if len(m.Running()) != 0 {
		t.Fatal("stopped after the last want")
	}
	if err := m.Want(1, "nope", true); err == nil {
		t.Fatal("unknown source")
	}
	time.Sleep(50 * time.Millisecond)
	if p.has("events_lost") {
		t.Fatal("a stop we asked for is not a loss")
	}
}

func TestManagerFailedStartAndLoss(t *testing.T) {
	gate := make(chan struct{})
	bad := func(ctx context.Context, push Push, ready func()) error {
		<-gate
		return errors.New("no bus")
	}
	lose := make(chan struct{})
	flaky := func(ctx context.Context, push Push, ready func()) error {
		ready()
		<-lose
		return errors.New("bus closed")
	}
	p := &pushed{}
	m := &Manager{Push: p.push, Sources: map[string]Source{"bad": bad, "flaky": flaky}}
	errs := make(chan error, 2)
	go func() { errs <- m.Want(1, "bad", true) }()
	go func() { errs <- m.Want(2, "bad", true) }()
	time.Sleep(50 * time.Millisecond)
	close(gate)
	for range 2 {
		if err := <-errs; err == nil {
			t.Fatal("both askers hear that the start failed")
		}
	}
	if err := m.Want(1, "flaky", true); err != nil {
		t.Fatal(err)
	}
	close(lose)
	deadline := time.Now().Add(time.Second)
	for !p.has("events_lost") && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if !p.has("events_lost") || len(m.Running()) != 0 {
		t.Fatalf("a source that ends on its own is reported: %v %v", p.got, m.Running())
	}
}

func udevMsg(props ...string) []byte {
	body := []byte{}
	for _, p := range props {
		body = append(append(body, p...), 0)
	}
	h := make([]byte, 40)
	copy(h, "libudev\x00")
	binary.BigEndian.PutUint32(h[8:], 0xfeedcafe)
	binary.NativeEndian.PutUint32(h[12:], 40)
	binary.NativeEndian.PutUint32(h[16:], 40)
	binary.NativeEndian.PutUint32(h[20:], uint32(len(body)))
	return append(h, body...)
}

func TestParseUdev(t *testing.T) {
	p, ok := parseUdev(udevMsg("ACTION=add", "SUBSYSTEM=usb", "DEVTYPE=usb_device", "ID_MODEL_FROM_DATABASE=Mass Storage"))
	if !ok || p["ACTION"] != "add" || p["ID_MODEL_FROM_DATABASE"] != "Mass Storage" || !wanted(p) {
		t.Fatalf("parse: %v %v", p, ok)
	}
	if p, _ := parseUdev(udevMsg("ACTION=add", "SUBSYSTEM=usb", "DEVTYPE=usb_interface")); wanted(p) {
		t.Fatal("interfaces are left out")
	}
	if _, ok := parseUdev([]byte("add@/devices/pci0000:00\x00ACTION=add\x00")); ok {
		t.Fatal("kernel uevents (no libudev header) are not udev's")
	}
	bad := udevMsg("ACTION=add")
	binary.NativeEndian.PutUint32(bad[20:], 9999)
	if _, ok := parseUdev(bad); ok {
		t.Fatal("a length past the end is refused")
	}
}
