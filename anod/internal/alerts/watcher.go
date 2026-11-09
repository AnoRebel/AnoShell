package alerts

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Settings are read before each poll (live config).
type Settings struct {
	Enable    bool
	Quiet     bool   // quiet hours on
	QuietFrom string // "HH:MM"
	QuietTo   string // "HH:MM"
}

// InQuiet: is now within [from, to) (a range may wrap midnight)?
func InQuiet(now time.Time, from, to string) bool {
	f, ok1 := minutes(from)
	t, ok2 := minutes(to)
	if !ok1 || !ok2 || f == t {
		return false
	}
	m := now.Hour()*60 + now.Minute()
	if f < t {
		return m >= f && m < t
	}
	return m >= f || m < t
}

func minutes(s string) (int, bool) {
	h, m, ok := strings.Cut(strings.TrimSpace(s), ":")
	hh, e1 := strconv.Atoi(h)
	mm, e2 := strconv.Atoi(m)
	if !ok || e1 != nil || e2 != nil || hh < 0 || hh > 23 || mm < 0 || mm > 59 {
		return 0, false
	}
	return hh*60 + mm, true
}

// Watcher polls the feed for the place the shell reports (SetPlace) and
// calls Announce once for each alert it hasn't seen.
type Watcher struct {
	CachePath string // state kept across restarts: place, alerts, ids announced
	Settings  func() Settings
	Announce  func(a Alert, quiet bool)
	Notify    func(name string, data any) // "weather_alerts" with State()
	Logf      func(string, ...any)
	Client    *http.Client
	Every     time.Duration // default 20 min

	mu    sync.Mutex
	st    state
	once  sync.Once
	kick  chan struct{}
	nomAt time.Time
}

type state struct {
	Place   *Place           `json:"place,omitempty"`
	Feed    string           `json:"feed"`
	Alerts  []Alert          `json:"alerts"`
	Seen    map[string]int64 `json:"seen"` // id → unix seconds first announced
	Updated int64            `json:"updated"`
	Error   string           `json:"error,omitempty"`
}

// State is what alerts.list and the event carry.
func (w *Watcher) State() map[string]any {
	w.init()
	w.mu.Lock()
	defer w.mu.Unlock()
	return w.stateLocked()
}

func (w *Watcher) stateLocked() map[string]any {
	country := ""
	if w.st.Place != nil {
		country = w.st.Place.Country
	}
	alerts := append([]Alert{}, current(w.st.Alerts, time.Now())...)
	return map[string]any{"alerts": alerts, "feed": w.st.Feed, "country": country, "updated": w.st.Updated, "error": w.st.Error}
}

// current drops alerts already expired.
func current(as []Alert, now time.Time) []Alert {
	var out []Alert
	for _, a := range as {
		if t, err := time.Parse(time.RFC3339, a.Expires); err == nil && t.Before(now) {
			continue
		}
		out = append(out, a)
	}
	return out
}

// SetPlace takes the shell's location; a move of more than ~1 km looks
// the country up again and polls now.
func (w *Watcher) SetPlace(lat, lon float64) {
	w.init()
	w.mu.Lock()
	p := w.st.Place
	moved := p == nil || math.Abs(p.Lat-lat) > 0.01 || math.Abs(p.Lon-lon) > 0.01
	if moved {
		w.st.Place = &Place{Lat: lat, Lon: lon}
	}
	w.mu.Unlock()
	if moved {
		w.poke()
	}
}

// init loads the cache once, before anything reads or sets the state.
func (w *Watcher) init() {
	w.once.Do(func() {
		w.kick = make(chan struct{}, 1)
		w.mu.Lock()
		w.load()
		w.mu.Unlock()
	})
}

func (w *Watcher) kicks() chan struct{} {
	w.init()
	return w.kick
}

func (w *Watcher) poke() {
	select {
	case w.kicks() <- struct{}{}:
	default:
	}
}

func (w *Watcher) logf(f string, a ...any) {
	if w.Logf != nil {
		w.Logf(f, a...)
	}
}

func (w *Watcher) load() {
	b, err := os.ReadFile(w.CachePath)
	if err == nil {
		json.Unmarshal(b, &w.st)
	}
	if w.st.Seen == nil {
		w.st.Seen = map[string]int64{}
	}
}

func (w *Watcher) save() {
	b, _ := json.Marshal(w.st)
	os.MkdirAll(filepath.Dir(w.CachePath), 0o700)
	tmp := w.CachePath + ".tmp"
	if os.WriteFile(tmp, b, 0o600) == nil {
		os.Rename(tmp, w.CachePath)
	}
}

// Run polls every Every (and right after SetPlace), backing off to 2 h
// while the feed fails.
func (w *Watcher) Run(ctx context.Context) {
	if w.Every == 0 {
		w.Every = 20 * time.Minute
	}
	w.init()
	wait := w.Every
	for {
		if w.Settings().Enable {
			if err := w.poll(ctx); err != nil {
				w.logf("weather alerts: %v", err)
				wait = min(2*time.Hour, max(w.Every, wait*2))
			} else {
				wait = w.Every
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-w.kicks():
		case <-time.After(wait):
		}
	}
}

func (w *Watcher) get(ctx context.Context, url string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", UserAgent)
	c := w.Client
	if c == nil {
		c = &http.Client{Timeout: 30 * time.Second}
	}
	resp, err := c.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("%s: HTTP %d", req.URL.Host, resp.StatusCode)
	}
	return io.ReadAll(io.LimitReader(resp.Body, 8<<20))
}

func (w *Watcher) poll(ctx context.Context) error {
	w.mu.Lock()
	var p Place
	if w.st.Place != nil {
		p = *w.st.Place
	}
	w.mu.Unlock()
	if p.Lat == 0 && p.Lon == 0 {
		return nil // the shell hasn't said where yet
	}
	if p.Country == "" {
		// Nominatim allows one request a second; one per place is far below that.
		if time.Since(w.nomAt) < 10*time.Second {
			return fmt.Errorf("waiting before the next reverse geocode")
		}
		w.nomAt = time.Now()
		b, err := w.get(ctx, fmt.Sprintf("https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=10&lat=%.4f&lon=%.4f", p.Lat, p.Lon))
		if err == nil {
			p.Country, p.Names, err = parseNominatim(b)
		}
		if err != nil {
			return w.fail(fmt.Errorf("country lookup: %w", err))
		}
		w.mu.Lock()
		if w.st.Place != nil && w.st.Place.Lat == p.Lat && w.st.Place.Lon == p.Lon {
			w.st.Place = &p
		}
		w.mu.Unlock()
	}
	feed, ok := FeedFor(p)
	if !ok {
		w.update("", nil, "")
		return nil
	}
	b, err := w.get(ctx, feed.URL)
	if err != nil {
		return w.fail(err)
	}
	as, err := feed.Parse(b)
	if err != nil {
		return w.fail(fmt.Errorf("%s: %w", feed.Name, err))
	}
	w.update(feed.Name, current(as, time.Now()), "")
	return nil
}

func (w *Watcher) fail(err error) error {
	w.mu.Lock()
	w.st.Error = err.Error()
	w.save()
	data := w.stateLocked()
	w.mu.Unlock()
	if w.Notify != nil {
		w.Notify("weather_alerts", data)
	}
	return err
}

// update stores the alerts, announces the new ones and forgets ids that
// left the feed more than two days ago.
func (w *Watcher) update(feed string, as []Alert, errText string) {
	w.init()
	now := time.Now()
	quiet := false
	if s := w.Settings(); s.Quiet {
		quiet = InQuiet(now, s.QuietFrom, s.QuietTo)
	}
	w.mu.Lock()
	var fresh []Alert
	active := map[string]bool{}
	for _, a := range as {
		active[a.ID] = true
		if _, ok := w.st.Seen[a.ID]; !ok {
			w.st.Seen[a.ID] = now.Unix()
			fresh = append(fresh, a)
		}
	}
	for id, at := range w.st.Seen {
		if !active[id] && now.Unix()-at > 2*86400 {
			delete(w.st.Seen, id)
		}
	}
	w.st.Feed, w.st.Alerts, w.st.Error, w.st.Updated = feed, as, errText, now.Unix()
	w.save()
	data := w.stateLocked()
	w.mu.Unlock()
	for _, a := range fresh {
		if w.Announce != nil {
			w.Announce(a, quiet)
		}
	}
	if w.Notify != nil {
		w.Notify("weather_alerts", data)
	}
}

// Refresh polls now (alerts.refresh).
func (w *Watcher) Refresh() { w.poke() }
