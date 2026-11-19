package screentime

import (
	"sort"
	"strconv"
	"time"
)

// FocusApp is one app in the FocusTime panel (its name and icon come from the
// shell's desktop entries; Name is only an imported display name).
type FocusApp struct {
	Class   string  `json:"class"`
	Name    string  `json:"name,omitempty"`
	Seconds int     `json:"seconds"`
	Percent float64 `json:"percent"`
}

type FocusDay struct {
	Date     string `json:"date"`
	Day      string `json:"day,omitempty"`
	Total    int    `json:"total"` // -1: a blank before the month's first day
	IsTarget bool   `json:"is_target"`
}

// Focus is the FocusTime panel's payload for a day (same keys as the old
// get_stats.py, so the panel reads it unchanged).
type Focus struct {
	SelectedDate string     `json:"selected_date"`
	Total        int        `json:"total"`
	Average      int        `json:"average"` // the week's days with time
	WeekRange    string     `json:"week_range"`
	Yesterday    int        `json:"yesterday"`
	Apps         []FocusApp `json:"apps"`
	WeekApps     []FocusApp `json:"week_apps"`
	Week         []FocusDay `json:"week"`
	Month        []FocusDay `json:"month"`
	Hourly       [48]int    `json:"hourly"` // half hours
	WeekHeatmap  [7][24]int `json:"week_heatmap"`
	Peak         string     `json:"peak_usage_str"` // "HH:MM - HH:MM" or "N/A"
}

// figures is one day, for all apps or one.
type figures struct {
	total   int
	perApp  map[string]int
	hours   [24]int
	minutes [1440]int
	hasMins bool
}

func (d *Day) figures(app string) figures {
	f := figures{perApp: map[string]int{}}
	for h, apps := range d.Hours {
		hi, _ := strconv.Atoi(h)
		for name, a := range apps {
			if app != "" && name != app {
				continue
			}
			f.total += a.Seconds
			f.perApp[name] += a.Seconds
			if hi >= 0 && hi < 24 {
				f.hours[hi] += a.Seconds
			}
		}
	}
	for name, mins := range d.Minutes {
		if app != "" && name != app {
			continue
		}
		for m, v := range mins {
			if mi, err := strconv.Atoi(m); err == nil && mi >= 0 && mi < 1440 {
				f.minutes[mi] += v
				f.hasMins = true
			}
		}
	}
	return f
}

func apps(per map[string]int, names map[string]string, limit int) []FocusApp {
	total := 0
	for _, v := range per {
		total += v
	}
	out := make([]FocusApp, 0, len(per))
	for k, v := range per {
		if v <= 0 {
			continue
		}
		p := 0.0
		if total > 0 {
			p = float64(int(float64(v)*1000/float64(total))) / 10
		}
		out = append(out, FocusApp{Class: k, Name: names[k], Seconds: v, Percent: p})
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Seconds != out[j].Seconds {
			return out[i].Seconds > out[j].Seconds
		}
		return out[i].Class < out[j].Class
	})
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out
}

// Focus answers the FocusTime panel for date (one app's figures when app is set).
func (s *Store) Focus(date time.Time, app string) (Focus, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	load := func(t time.Time) (figures, map[string]string, error) {
		d, err := s.day(t.Format(dateLayout))
		if err != nil {
			return figures{}, nil, err
		}
		return d.figures(app), d.Names, nil
	}
	day := time.Date(date.Year(), date.Month(), date.Day(), 12, 0, 0, 0, date.Location()) // noon: no DST edge
	out := Focus{SelectedDate: day.Format(dateLayout), Peak: "N/A"}
	today, names, err := load(day)
	if err != nil {
		return out, err
	}
	out.Total = today.total
	out.Apps = apps(today.perApp, names, 0)
	if y, _, err := load(day.AddDate(0, 0, -1)); err == nil {
		out.Yesterday = y.total
	}
	// Half hours: from the minutes; days without them (older imports) split each hour in two.
	if today.hasMins {
		for m, v := range today.minutes {
			out.Hourly[m/30] += v
		}
	} else {
		for h, v := range today.hours {
			out.Hourly[h*2] += v / 2
			out.Hourly[h*2+1] += v - v/2
		}
	}

	// The week (Monday to Sunday) holding the day.
	monday := day.AddDate(0, 0, -((int(day.Weekday()) + 6) % 7))
	sunday := monday.AddDate(0, 0, 6)
	out.WeekRange = monday.Format("Jan 2") + " - " + sunday.Format("Jan 2")
	weekPer := map[string]int{}
	weekNames := map[string]string{}
	var minutes [1440]int
	days, weekTotal := 0, 0
	for i := range 7 {
		d := monday.AddDate(0, 0, i)
		f, n, err := load(d)
		if err != nil {
			return out, err
		}
		out.Week = append(out.Week, FocusDay{Date: d.Format(dateLayout), Day: d.Format("Mon"), Total: f.total, IsTarget: i == (int(day.Weekday())+6)%7})
		if f.total > 0 {
			days++
			weekTotal += f.total
		}
		for k, v := range f.perApp {
			weekPer[k] += v
		}
		for k, v := range n {
			weekNames[k] = v
		}
		out.WeekHeatmap[i] = f.hours
		for m, v := range f.minutes {
			minutes[m] += v
		}
	}
	if days > 0 {
		out.Average = weekTotal / days
	}
	for k, v := range names {
		weekNames[k] = v
	}
	out.WeekApps = apps(weekPer, weekNames, 50)
	out.Peak = peak(minutes)

	// The month, with blanks before the 1st so it starts on a Monday.
	first := time.Date(day.Year(), day.Month(), 1, 12, 0, 0, 0, day.Location())
	for range (int(first.Weekday()) + 6) % 7 {
		out.Month = append(out.Month, FocusDay{Total: -1})
	}
	for d := first; d.Month() == first.Month(); d = d.AddDate(0, 0, 1) {
		f, _, err := load(d)
		if err != nil {
			return out, err
		}
		out.Month = append(out.Month, FocusDay{Date: d.Format(dateLayout), Total: f.total, IsTarget: d.Day() == day.Day()})
	}
	return out, nil
}

// peak is the busiest hour of the day (a sliding 60-minute window), trimmed
// to the minutes that had time, as "HH:MM - HH:MM"; "N/A" without any.
func peak(m [1440]int) string {
	best, start := 0, -1
	sum := 0
	for i := range 60 {
		sum += m[i]
	}
	for i := 0; i+60 <= 1440; i++ {
		if i > 0 {
			sum += m[i+59] - m[i-1]
		}
		if sum > best {
			best, start = sum, i
		}
	}
	if start < 0 {
		return "N/A"
	}
	end := start + 59
	for start < end && m[start] == 0 {
		start++
	}
	for end > start && m[end] == 0 {
		end--
	}
	hm := func(x int) string { return pad(x/60) + ":" + pad(x%60) }
	return hm(start) + " - " + hm(end)
}

func pad(n int) string {
	if n < 10 {
		return "0" + strconv.Itoa(n)
	}
	return strconv.Itoa(n)
}
