package screentime

import (
	"encoding/json"
	"fmt"
	"sort"
	"time"
)

// Export is FocusTime's database as scripts/focustime/export.py prints it.
type Export struct {
	Log     [][]any `json:"log"`     // date, app, seconds, name
	Hourly  [][]any `json:"hourly"`  // date, hour, app, seconds
	Minutes [][]any `json:"minutes"` // date, minute, app, seconds
}

// ImportReport says what an import brought and whether each day's total
// matches FocusTime's own.
type ImportReport struct {
	Days       int      `json:"days"`
	Seconds    int      `json:"seconds"`
	Mismatches []string `json:"mismatches,omitempty"` // "date: want X, got Y"
}

type importDay struct {
	hours   map[int]map[string]int
	minutes map[string]map[int]int
	log     map[string]int
	names   map[string]string
}

func str(v any) string {
	s, _ := v.(string)
	return s
}

func num(v any) int {
	f, _ := v.(float64)
	return int(f)
}

// Import merges FocusTime's history into the store (added to what a day
// already has). Hours come from its hourly table, minutes from its minute
// table; when a day's hourly rows add up to less than its daily total, the
// gap goes to the apps short of theirs (busiest hour, else noon), so every
// day's total matches FocusTime's.
func (s *Store) Import(raw []byte) (ImportReport, error) {
	var e Export
	var rep ImportReport
	if err := json.Unmarshal(raw, &e); err != nil {
		return rep, err
	}
	days := map[string]*importDay{}
	get := func(date string) *importDay {
		if _, err := time.Parse(dateLayout, date); err != nil {
			return nil
		}
		d := days[date]
		if d == nil {
			d = &importDay{hours: map[int]map[string]int{}, minutes: map[string]map[int]int{}, log: map[string]int{}, names: map[string]string{}}
			days[date] = d
		}
		return d
	}
	for _, r := range e.Log {
		if len(r) < 4 {
			continue
		}
		if d := get(str(r[0])); d != nil {
			app := clean(str(r[1]), 120)
			d.log[app] += num(r[2])
			if n := clean(str(r[3]), 120); n != "" && n != app {
				d.names[app] = n
			}
		}
	}
	for _, r := range e.Hourly {
		if len(r) < 4 || num(r[1]) < 0 || num(r[1]) > 23 {
			continue
		}
		if d := get(str(r[0])); d != nil {
			if d.hours[num(r[1])] == nil {
				d.hours[num(r[1])] = map[string]int{}
			}
			d.hours[num(r[1])][clean(str(r[2]), 120)] += num(r[3])
		}
	}
	for _, r := range e.Minutes {
		if len(r) < 4 || num(r[1]) < 0 || num(r[1]) >= 1440 {
			continue
		}
		if d := get(str(r[0])); d != nil {
			app := clean(str(r[2]), 120)
			if d.minutes[app] == nil {
				d.minutes[app] = map[int]int{}
			}
			d.minutes[app][num(r[1])] += num(r[3])
		}
	}

	dates := make([]string, 0, len(days))
	for k := range days {
		dates = append(dates, k)
	}
	sort.Strings(dates)
	s.mu.Lock()
	defer s.mu.Unlock()
	s.past = nil // days are about to change on disk
	for _, date := range dates {
		in := days[date]
		var d *Day
		if s.cur != nil && s.curDate == date {
			d = s.cur
		} else {
			var err error
			if d, err = s.load(date); err != nil {
				return rep, err
			}
		}
		before := d.figures("").total
		for h, apps := range in.hours {
			for app, secs := range apps {
				d.hour(h, app).Seconds += secs
			}
		}
		for app, mins := range in.minutes {
			for m, secs := range mins {
				d.minute(m, app, secs)
			}
		}
		// Hourly rows short of the day's total (an older FocusTime logged some
		// time without its hour): the gap goes to the apps short of their own
		// total, in their busiest hour. FocusTime's tables can differ by a second
		// per app while the day's totals agree; then nothing is added.
		gap := 0
		for _, v := range in.log {
			gap += v
		}
		for _, apps := range in.hours {
			for _, v := range apps {
				gap -= v
			}
		}
		short := make([]string, 0, len(in.log))
		for app := range in.log {
			short = append(short, app)
		}
		sort.Strings(short)
		for _, app := range short {
			if gap <= 0 {
				break
			}
			got, best, bestSecs := 0, 12, 0
			for h, apps := range in.hours {
				got += apps[app]
				if apps[app] > bestSecs {
					best, bestSecs = h, apps[app]
				}
			}
			if add := min(in.log[app]-got, gap); add > 0 {
				d.hour(best, app).Seconds += add
				gap -= add
			}
		}
		for app, n := range in.names {
			if d.Names == nil {
				d.Names = map[string]string{}
			}
			d.Names[app] = n
		}
		if d != s.cur {
			if err := s.save(date, d); err != nil {
				return rep, err
			}
		} else {
			s.dirty = true
		}
		wantTotal := 0
		for _, v := range in.log {
			wantTotal += v
		}
		got := d.figures("").total - before
		if len(in.log) > 0 && got != wantTotal {
			rep.Mismatches = append(rep.Mismatches, fmt.Sprintf("%s: want %d, got %d", date, wantTotal, got))
		}
		rep.Days++
		rep.Seconds += got
	}
	return rep, s.flushLocked()
}
