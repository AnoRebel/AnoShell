package reader

import (
	"bufio"
	"net"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestResumeAt(t *testing.T) {
	for _, c := range []struct {
		p    epProgress
		want float64
	}{
		{epProgress{Pos: 600, Dur: 1440}, 597},
		{epProgress{Pos: 10, Dur: 1440}, 0},                 // barely started
		{epProgress{Pos: 1420, Dur: 1440}, 0},               // nearly over
		{epProgress{Pos: 600, Dur: 1440, Watched: true}, 0}, // watched: from the start
	} {
		if got := resumeAt(c.p); got != c.want {
			t.Errorf("resumeAt(%+v) = %v, want %v", c.p, got, c.want)
		}
	}
}

// A fake mpv: answers the observe commands with property changes, then quits.
func TestWatchMPVSavesProgress(t *testing.T) {
	s := newService(t)
	sock := filepath.Join(t.TempDir(), "mpv.sock")
	ln, err := net.Listen("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		r := bufio.NewReader(c)
		for i := 0; i < 2; i++ { // the two observe_property commands
			if l, _ := r.ReadString('\n'); !strings.Contains(l, "observe_property") {
				t.Errorf("unexpected command %q", l)
			}
		}
		for _, ev := range []string{
			`{"event":"property-change","id":2,"name":"duration","data":1000}`,
			`{"event":"property-change","id":1,"name":"time-pos","data":120.5}`,
			`{"event":"property-change","id":1,"name":"time-pos","data":950}`,
			`{"event":"property-change","id":1,"name":"time-pos","data":null}`,
		} {
			c.Write([]byte(ev + "\n"))
		}
	}()
	done := make(chan struct{})
	finished := make(chan struct{})
	go func() { s.watchMPV(sock, PlayRequest{Show: "abc", Episode: "3"}, done); close(finished) }()
	select {
	case <-finished:
	case <-time.After(5 * time.Second):
		t.Fatal("watcher didn't finish when mpv closed the socket")
	}
	p := s.Progress("abc")["3"]
	if p.Pos != 950 || p.Dur != 1000 || !p.Watched {
		t.Fatalf("progress = %+v, want pos 950 of 1000, watched", p)
	}
	// A later, shorter session doesn't unwatch it.
	s.saveProgress("abc", "3", epProgress{Pos: 30, Dur: 1000})
	if !s.Progress("abc")["3"].Watched {
		t.Fatal("rewatching unwatched the episode")
	}
}

// anime/latest is the source's latest-releases list; the new-episode badges
// have their own route (a clash once broke Browse → Latest).
func TestAiredRouteDoesNotShadowLatest(t *testing.T) {
	s := newService(t)
	st, err := s.Open("anime")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Shutdown()
	if code, body := get(t, st.URL+"anime/aired?ids="); code != 200 || strings.TrimSpace(body) != "{}" {
		t.Fatalf("aired with no ids = %d %q", code, body)
	}
	// Whatever the network does, the provider answers, not the badge route.
	if _, body := get(t, st.URL+"anime/latest?limit=1&page=1&mode=sub&country=ALL"); strings.TrimSpace(body) == "{}" {
		t.Fatal("anime/latest reached the aired-episodes route")
	}
}
