// Package screentime keeps per-app focused time (spec system-tools: Screen
// time): the shell reports what was focused while the session was active, and
// this stores it per day, per hour, per app (with the app's top window
// titles), in local files that never leave the machine and are pruned after a
// number of days.
package screentime

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	maxTitleLen    = 200
	maxTitlesKept  = 40  // per app per hour
	maxAddSeconds  = 120 // one report covers at most this much
	dateLayout     = "2006-01-02"
	defaultKeepDay = 30
)

// AppHour is one app's time within one hour.
type AppHour struct {
	Seconds int            `json:"secs"`
	Titles  map[string]int `json:"titles,omitempty"`
}

// Day is one day's file: hour ("0"…"23") → app → time.
type Day struct {
	Hours map[string]map[string]*AppHour `json:"hours"`
}

// Store is the day files in Dir ($XDG_STATE_HOME/anoshell/screentime).
type Store struct {
	Dir string
	mu  sync.Mutex
	// the day being written, kept in memory
	cur     *Day
	curDate string
}

func (s *Store) path(date string) string { return filepath.Join(s.Dir, date+".json") }

func (s *Store) load(date string) (*Day, error) {
	d := &Day{Hours: map[string]map[string]*AppHour{}}
	b, err := os.ReadFile(s.path(date))
	if errors.Is(err, os.ErrNotExist) {
		return d, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(b, d); err != nil {
		return nil, err
	}
	if d.Hours == nil {
		d.Hours = map[string]map[string]*AppHour{}
	}
	return d, nil
}

func (s *Store) save(date string, d *Day) error {
	if err := os.MkdirAll(s.Dir, 0o700); err != nil {
		return err
	}
	b, err := json.Marshal(d)
	if err != nil {
		return err
	}
	tmp := s.path(date) + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.path(date))
}

func clean(s string, n int) string {
	s = strings.TrimSpace(strings.ReplaceAll(s, "\n", " "))
	if len([]rune(s)) > n {
		s = string([]rune(s)[:n])
	}
	return s
}

// Add credits seconds of focused time to app (and its window title) at `at`.
func (s *Store) Add(at time.Time, app, title string, seconds int) error {
	if seconds <= 0 {
		return nil
	}
	if seconds > maxAddSeconds {
		seconds = maxAddSeconds
	}
	app = clean(app, 120)
	if app == "" {
		app = "unknown"
	}
	title = clean(title, maxTitleLen)
	date := at.Format(dateLayout)
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.cur == nil || s.curDate != date {
		d, err := s.load(date)
		if err != nil {
			return err
		}
		s.cur, s.curDate = d, date
	}
	hour := strconv.Itoa(at.Hour())
	apps := s.cur.Hours[hour]
	if apps == nil {
		apps = map[string]*AppHour{}
		s.cur.Hours[hour] = apps
	}
	a := apps[app]
	if a == nil {
		a = &AppHour{Titles: map[string]int{}}
		apps[app] = a
	}
	a.Seconds += seconds
	if title != "" {
		if a.Titles == nil {
			a.Titles = map[string]int{}
		}
		a.Titles[title] += seconds
		if len(a.Titles) > maxTitlesKept { // drop the smallest
			min, minT := -1, ""
			for t, v := range a.Titles {
				if min < 0 || v < min {
					min, minT = v, t
				}
			}
			delete(a.Titles, minT)
		}
	}
	return s.save(date, s.cur)
}

// Named is a name with seconds (an app or a title).
type Named struct {
	Name    string  `json:"name"`
	Seconds int     `json:"secs"`
	Titles  []Named `json:"titles,omitempty"`
}

// Summary is what the card shows for a day.
type Summary struct {
	Date    string  `json:"date"`
	Total   int     `json:"total"`
	Hours   [24]int `json:"hours"`
	TopApps []Named `json:"apps"`
}

func top(m map[string]int, n int) []Named {
	out := make([]Named, 0, len(m))
	for k, v := range m {
		out = append(out, Named{Name: k, Seconds: v})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Seconds != out[j].Seconds {
			return out[i].Seconds > out[j].Seconds
		}
		return out[i].Name < out[j].Name
	})
	if n > 0 && len(out) > n {
		out = out[:n]
	}
	return out
}

// DaySummary totals one day: hours, the top apps and each app's top titles.
func (s *Store) DaySummary(date string) (Summary, error) {
	s.mu.Lock()
	var d *Day
	var err error
	if s.cur != nil && s.curDate == date {
		d = s.cur
	} else {
		d, err = s.load(date)
	}
	sum := Summary{Date: date}
	if err != nil {
		s.mu.Unlock()
		return sum, err
	}
	appSecs := map[string]int{}
	appTitles := map[string]map[string]int{}
	for h, apps := range d.Hours {
		hi, _ := strconv.Atoi(h)
		for name, a := range apps {
			sum.Total += a.Seconds
			if hi >= 0 && hi < 24 {
				sum.Hours[hi] += a.Seconds
			}
			appSecs[name] += a.Seconds
			if appTitles[name] == nil {
				appTitles[name] = map[string]int{}
			}
			for t, v := range a.Titles {
				appTitles[name][t] += v
			}
		}
	}
	s.mu.Unlock()
	sum.TopApps = top(appSecs, 8)
	for i := range sum.TopApps {
		sum.TopApps[i].Titles = top(appTitles[sum.TopApps[i].Name], 5)
	}
	return sum, nil
}

// Week is the totals of the 7 days ending on `end`, oldest first.
func (s *Store) Week(end time.Time) ([]Named, error) {
	out := make([]Named, 0, 7)
	for i := 6; i >= 0; i-- {
		date := end.AddDate(0, 0, -i).Format(dateLayout)
		sum, err := s.DaySummary(date)
		if err != nil {
			return nil, err
		}
		out = append(out, Named{Name: date, Seconds: sum.Total})
	}
	return out, nil
}

// Prune deletes day files older than keepDays (default 30) before `now`.
func (s *Store) Prune(now time.Time, keepDays int) (int, error) {
	if keepDays <= 0 {
		keepDays = defaultKeepDay
	}
	cutoff := now.AddDate(0, 0, -keepDays).Format(dateLayout)
	ents, err := os.ReadDir(s.Dir)
	if errors.Is(err, os.ErrNotExist) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	n := 0
	for _, e := range ents {
		name := e.Name()
		date, ok := strings.CutSuffix(name, ".json")
		if !ok {
			continue
		}
		if _, err := time.Parse(dateLayout, date); err != nil {
			continue
		}
		if date < cutoff {
			if os.Remove(filepath.Join(s.Dir, name)) == nil {
				n++
			}
		}
	}
	return n, nil
}
