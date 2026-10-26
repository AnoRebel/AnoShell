package reader

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"sync/atomic"
	"time"
)

// ── Anime playback progress (resume, watched) and AniSkip ───────────────
//
// mpv gets a private JSON IPC socket; a watcher follows time-pos and
// duration, saves the position per show and episode, marks the episode
// watched past FinishedRatio and, with SkipIntro, seeks past AniSkip's
// opening/ending intervals (looked up by the show's MAL id). Ideas from
// Ryoku's AnimeWatch/MpvIpc, kept in anod instead of shell scripts.

type epProgress struct {
	Pos     float64 `json:"pos"`
	Dur     float64 `json:"dur"`
	Watched bool    `json:"watched"`
	At      int64   `json:"at"`
}

func (s *Service) progressPath() string { return filepath.Join(s.DataDir, "anime-progress.json") }

// readProgress loads show → episode → progress; caller holds libMu.
func (s *Service) readProgress() map[string]map[string]epProgress {
	all := map[string]map[string]epProgress{}
	if b, err := os.ReadFile(s.progressPath()); err == nil {
		if json.Unmarshal(b, &all) != nil {
			// Keep it rather than overwrite it on the next save.
			_ = os.Rename(s.progressPath(), s.progressPath()+".bak")
			s.logf("anime progress file unreadable; kept as %s.bak", s.progressPath())
			all = map[string]map[string]epProgress{}
		}
	}
	return all
}

// Progress returns a show's episodes' progress.
func (s *Service) Progress(show string) map[string]epProgress {
	s.libMu.Lock()
	defer s.libMu.Unlock()
	if p := s.readProgress()[show]; p != nil {
		return p
	}
	return map[string]epProgress{}
}

func (s *Service) saveProgress(show, ep string, p epProgress) {
	if show == "" || ep == "" {
		return
	}
	s.libMu.Lock()
	defer s.libMu.Unlock()
	all := s.readProgress()
	if all[show] == nil {
		all[show] = map[string]epProgress{}
	}
	if old, ok := all[show][ep]; ok && old.Watched {
		p.Watched = true // rewatching doesn't unwatch
	}
	p.At = time.Now().Unix()
	all[show][ep] = p
	b, err := json.Marshal(all)
	if err == nil {
		err = os.MkdirAll(s.DataDir, 0o700)
	}
	if err == nil {
		err = writeFileAtomic(s.progressPath(), b, 0o600)
	}
	if err != nil {
		s.logf("saving anime progress: %v", err)
	}
}

// resumeAt is where to start an episode: its saved position unless it was
// watched, barely started or nearly over.
func resumeAt(p epProgress) float64 {
	if p.Watched || p.Pos < 15 || (p.Dur > 0 && p.Pos > p.Dur-30) {
		return 0
	}
	return p.Pos - 3
}

var mpvSeq atomic.Int64

// mpvSocket is a fresh socket path in a private (0700) runtime folder, unique
// per play: the previous player's watcher removes its own socket on exit and
// must never hit the new one's.
func mpvSocket() (string, error) {
	dir := os.Getenv("XDG_RUNTIME_DIR")
	if dir == "" {
		dir = os.TempDir()
	}
	dir = filepath.Join(dir, "anoshell")
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	if err := os.Chmod(dir, 0o700); err != nil {
		return "", err
	}
	p := filepath.Join(dir, fmt.Sprintf("mpv-%d-%d.sock", os.Getpid(), mpvSeq.Add(1)))
	_ = os.Remove(p)
	return p, nil
}

type skipRange struct{ start, end float64 }

// aniskip fetches opening/ending intervals for a MAL id and episode.
func aniskip(ctx context.Context, mal, ep string) ([]skipRange, error) {
	if _, err := strconv.Atoi(mal); err != nil {
		return nil, fmt.Errorf("no MAL id")
	}
	if _, err := strconv.Atoi(ep); err != nil {
		return nil, fmt.Errorf("episode %q is not a whole number", ep)
	}
	u := fmt.Sprintf("https://api.aniskip.com/v2/skip-times/%s/%s?types[]=op&types[]=ed&episodeLength=0",
		url.PathEscape(mal), url.PathEscape(ep))
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	resp, err := (&http.Client{Timeout: 8 * time.Second}).Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotFound {
		return nil, nil // no times submitted for this episode
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("aniskip: %s", resp.Status)
	}
	var r struct {
		Results []struct {
			Interval struct {
				StartTime float64 `json:"startTime"`
				EndTime   float64 `json:"endTime"`
			} `json:"interval"`
		} `json:"results"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&r); err != nil {
		return nil, err
	}
	var out []skipRange
	for _, x := range r.Results {
		if x.Interval.EndTime > x.Interval.StartTime {
			out = append(out, skipRange{x.Interval.StartTime, x.Interval.EndTime})
		}
	}
	return out, nil
}

// watchMPV follows one mpv over its IPC socket until it exits (done closes).
func (s *Service) watchMPV(sock string, req PlayRequest, done <-chan struct{}) {
	ratio := req.FinishedRatio
	if ratio <= 0 || ratio > 1 {
		ratio = 0.9
	}
	skips := make(chan []skipRange, 1)
	if req.SkipIntro && req.Show != "" {
		go func() {
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			defer cancel()
			s.mu.Lock()
			a := s.anime
			s.mu.Unlock()
			if a == nil {
				return
			}
			m, err := a.meta(ctx, req.Show)
			if err == nil {
				var r []skipRange
				if r, err = aniskip(ctx, m.MalID, req.Episode); err == nil {
					skips <- r
					return
				}
			}
			s.logf("aniskip %s ep %s: %v", req.Show, req.Episode, err)
		}()
	}

	var conn net.Conn
	for i := 0; i < 100 && conn == nil; i++ { // mpv makes the socket shortly after start
		select {
		case <-done:
			return
		case <-time.After(100 * time.Millisecond):
		}
		conn, _ = net.Dial("unix", sock)
	}
	if conn == nil {
		s.logf("mpv IPC socket never appeared; progress not saved")
		return
	}
	defer conn.Close()
	defer os.Remove(sock)
	fmt.Fprintln(conn, `{"command":["observe_property",1,"time-pos"]}`)
	fmt.Fprintln(conn, `{"command":["observe_property",2,"duration"]}`)

	var pos, dur float64
	var ranges []skipRange
	skipped := map[int]bool{}
	lastSave := time.Now()
	save := func() {
		if pos > 0 {
			s.saveProgress(req.Show, req.Episode, epProgress{Pos: pos, Dur: dur, Watched: dur > 0 && pos/dur >= ratio})
		}
	}
	sc := bufio.NewScanner(conn)
	for sc.Scan() {
		var ev struct {
			Event string   `json:"event"`
			ID    int      `json:"id"`
			Data  *float64 `json:"data"`
		}
		if json.Unmarshal(sc.Bytes(), &ev) != nil || ev.Event != "property-change" || ev.Data == nil {
			continue
		}
		switch ev.ID {
		case 1:
			pos = *ev.Data
		case 2:
			dur = *ev.Data
		}
		select {
		case r := <-skips:
			ranges = r
		default:
		}
		for i, r := range ranges {
			if !skipped[i] && pos >= r.start && pos < r.end-1 {
				skipped[i] = true // once: seeking back into it is the user's choice
				fmt.Fprintf(conn, `{"command":["set_property","time-pos",%.3f]}`+"\n", r.end)
			}
		}
		if time.Since(lastSave) > 15*time.Second {
			save()
			lastSave = time.Now()
		}
	}
	save() // mpv quit or the episode ended
}
