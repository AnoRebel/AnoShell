package screentime

import (
	"testing"
	"time"
)

func TestFocusPayload(t *testing.T) {
	s := &Store{Dir: t.TempDir()}
	at := func(d, h, m int) time.Time { return time.Date(2026, 11, d, h, m, 0, 0, time.Local) }
	// Thu 19 Nov: kitty 10:00–10:30, firefox 14:00–14:10. Wed 18: kitty 10 min at 9:00. Mon 16: nothing.
	for i := 1; i <= 30; i++ {
		s.Add(at(19, 10, i), "kitty", "", 60)
	}
	for i := 1; i <= 10; i++ {
		s.Add(at(19, 14, i), "firefox", "", 60)
	}
	for i := 1; i <= 10; i++ {
		s.Add(at(18, 9, i), "kitty", "", 60)
	}
	f, err := s.Focus(at(19, 23, 0), "")
	if err != nil {
		t.Fatal(err)
	}
	if f.SelectedDate != "2026-11-19" || f.Total != 2400 || f.Yesterday != 600 {
		t.Fatalf("totals: %+v", f)
	}
	if len(f.Apps) != 2 || f.Apps[0].Class != "kitty" || f.Apps[0].Seconds != 1800 || f.Apps[0].Percent != 75 {
		t.Fatalf("apps: %+v", f.Apps)
	}
	if f.Hourly[20] != 1800 || f.Hourly[28] != 600 {
		t.Fatalf("half hours 20=%d 28=%d", f.Hourly[20], f.Hourly[28])
	}
	if f.WeekRange != "Nov 16 - Nov 22" || len(f.Week) != 7 || f.Week[0].Day != "Mon" || !f.Week[3].IsTarget || f.Week[2].Total != 600 {
		t.Fatalf("week: %s %+v", f.WeekRange, f.Week)
	}
	if f.Average != (2400+600)/2 {
		t.Fatalf("average over the days with time: %d", f.Average)
	}
	if f.WeekHeatmap[3][10] != 1800 || f.WeekHeatmap[2][9] != 600 {
		t.Fatalf("heatmap: %v", f.WeekHeatmap)
	}
	if len(f.WeekApps) != 2 || f.WeekApps[0].Seconds != 2400 {
		t.Fatalf("week apps: %+v", f.WeekApps)
	}
	// 1 Nov 2026 is a Sunday: six blanks before it.
	if f.Month[5].Total != -1 || f.Month[6].Date != "2026-11-01" || !f.Month[6+18].IsTarget || len(f.Month) != 6+30 {
		t.Fatalf("month: %+v", f.Month[:8])
	}
	if f.Peak != "10:00 - 10:29" {
		t.Fatalf("peak %q", f.Peak)
	}
	// One app's view.
	g, _ := s.Focus(at(19, 23, 0), "firefox")
	if g.Total != 600 || len(g.Apps) != 1 || g.Yesterday != 0 || g.Peak != "14:00 - 14:09" {
		t.Fatalf("firefox only: total %d apps %+v y %d peak %s", g.Total, g.Apps, g.Yesterday, g.Peak)
	}
	// A day with hours only (an import without minutes): each hour split over its halves.
	d := &Day{Hours: map[string]map[string]*AppHour{"8": {"x": {Seconds: 601}}}}
	s.mu.Lock()
	s.past = map[string]*Day{"2026-11-10": d}
	s.mu.Unlock()
	h, _ := s.Focus(at(10, 12, 0), "")
	if h.Hourly[16] != 300 || h.Hourly[17] != 301 || h.Peak != "N/A" {
		t.Fatalf("hours only: %d %d %s", h.Hourly[16], h.Hourly[17], h.Peak)
	}
}

func TestImport(t *testing.T) {
	dir := t.TempDir()
	s := &Store{Dir: dir}
	raw := []byte(`{"log":[["2026-10-14","vlc",7697,"VLC media player"],["2026-10-14","kitty",100,"kitty"],["bad-date","x",5,"x"]],
	"hourly":[["2026-10-14",20,"vlc",7000],["2026-10-14",21,"vlc",600],["2026-10-14",9,"kitty",100]],
	"minutes":[["2026-10-14",1200,"vlc",60],["2026-10-14",540,"kitty",100]]}`)
	rep, err := s.Import(raw)
	if err != nil || rep.Days != 1 || rep.Seconds != 7797 || len(rep.Mismatches) != 0 {
		t.Fatalf("report %+v %v", rep, err)
	}
	d, _ := (&Store{Dir: dir}).load("2026-10-14")
	if d.Hours["20"]["vlc"].Seconds != 7097 || d.Hours["21"]["vlc"].Seconds != 600 {
		t.Fatalf("the 97 s missing from vlc's hours go in its busiest hour: %+v %+v", d.Hours["20"]["vlc"], d.Hours["21"]["vlc"])
	}
	if d.Names["vlc"] != "VLC media player" || d.Names["kitty"] != "" || d.Minutes["kitty"]["540"] != 100 {
		t.Fatalf("names/minutes: %v %v", d.Names, d.Minutes)
	}
	f, _ := s.Focus(time.Date(2026, 10, 14, 12, 0, 0, 0, time.Local), "")
	if f.Total != 7797 || f.Apps[0].Name != "VLC media player" {
		t.Fatalf("focus after import: %d %+v", f.Total, f.Apps)
	}
}
