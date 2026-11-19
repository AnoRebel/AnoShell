package screentime

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestAddSummaryWeekPrune(t *testing.T) {
	dir := t.TempDir()
	s := &Store{Dir: dir}
	day := time.Date(2026, 10, 21, 14, 5, 0, 0, time.Local)
	// 10 minutes across two apps, reported in 15 s ticks like the shell does.
	for i := 0; i < 24; i++ { // 6 min
		if err := s.Add(day.Add(time.Duration(i)*15*time.Second), "kitty", "nvim main.go", 15); err != nil {
			t.Fatal(err)
		}
	}
	for i := 0; i < 16; i++ { // 4 min
		s.Add(day.Add(time.Hour+time.Duration(i)*15*time.Second), "firefox", "Docs", 15)
	}
	s.Add(day, "kitty", "", 999) // capped at maxAddSeconds
	sum, err := s.DaySummary("2026-10-21")
	if err != nil {
		t.Fatal(err)
	}
	if sum.Total != 600+maxAddSeconds {
		t.Errorf("total %d, want %d", sum.Total, 600+maxAddSeconds)
	}
	if len(sum.TopApps) != 2 || sum.TopApps[0].Name != "kitty" || sum.TopApps[0].Seconds != 360+maxAddSeconds || sum.TopApps[1].Seconds != 240 {
		t.Errorf("apps %+v", sum.TopApps)
	}
	if sum.PerApp["kitty"] != 360+maxAddSeconds || sum.PerApp["firefox"] != 240 {
		t.Errorf("perApp %v", sum.PerApp)
	}
	if sum.Hours[14] != 360+maxAddSeconds || sum.Hours[15] != 240 {
		t.Errorf("hours 14=%d 15=%d", sum.Hours[14], sum.Hours[15])
	}
	if sum.TopApps[0].Titles[0].Name != "nvim main.go" || sum.TopApps[0].Titles[0].Seconds != 360 {
		t.Errorf("titles %+v", sum.TopApps[0].Titles)
	}
	// A fresh store reads the same from disk (after the flush: saves are batched).
	s.Flush()
	s2 := &Store{Dir: dir}
	if sum2, _ := s2.DaySummary("2026-10-21"); sum2.Total != sum.Total {
		t.Errorf("reloaded total %d", sum2.Total)
	}
	wk, err := s.Week(day)
	if err != nil || len(wk) != 7 || wk[6].Seconds != sum.Total || wk[0].Name != "2026-10-15" {
		t.Errorf("week %+v %v", wk, err)
	}
	// Prune: a file 40 days old goes, today's stays.
	old := filepath.Join(dir, "2026-09-10.json")
	os.WriteFile(old, []byte(`{"hours":{}}`), 0o600)
	os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("x"), 0o600)
	n, err := s.Prune(day, 30)
	if err != nil || n != 1 {
		t.Errorf("pruned %d %v", n, err)
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Error("old day kept")
	}
	if _, err := os.Stat(filepath.Join(dir, "2026-10-21.json")); err != nil {
		t.Error("today pruned")
	}
	if fi, _ := os.Stat(filepath.Join(dir, "2026-10-21.json")); fi.Mode().Perm() != 0o600 {
		t.Errorf("mode %v", fi.Mode().Perm())
	}
}

func TestTitlesCappedAndCleaned(t *testing.T) {
	s := &Store{Dir: t.TempDir()}
	at := time.Date(2026, 10, 21, 9, 30, 0, 0, time.Local)
	for i := 0; i < maxTitlesKept+10; i++ {
		s.Add(at, "app", "t"+strings.Repeat("x", i), 1+i)
	}
	s.Add(at, "app", strings.Repeat("y", 500)+"\nz", 5)
	if got := len(s.cur.Hours["9"]["app"].Titles); got > maxTitlesKept {
		t.Errorf("%d titles kept", got)
	}
	for title := range s.cur.Hours["9"]["app"].Titles {
		if len([]rune(title)) > maxTitleLen || strings.Contains(title, "\n") {
			t.Errorf("title not cleaned: %q", title[:20])
		}
	}
	if err := s.Add(at, "", "x", 5); err != nil || s.cur.Hours["9"]["unknown"] == nil {
		t.Error("empty app not recorded as unknown")
	}
}

func TestCorruptDaySetAside(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "2026-10-21.json"), []byte("{not json"), 0o600)
	s := &Store{Dir: dir}
	at := time.Date(2026, 10, 21, 10, 0, 0, 0, time.Local)
	if err := s.Add(at, "kitty", "x", 30); err != nil {
		t.Fatalf("add after a corrupt file: %v", err)
	}
	if _, err := os.Stat(filepath.Join(dir, "2026-10-21.json.bad")); err != nil {
		t.Error("corrupt file not kept aside")
	}
	if sum, _ := s.DaySummary("2026-10-21"); sum.Total != 30 {
		t.Errorf("total %d", sum.Total)
	}
}

func TestMinutesSplitAndBatchedSaves(t *testing.T) {
	dir := t.TempDir()
	s := &Store{Dir: dir}
	// 90 s ending at 10:00:30: 60 s in 9:59 (hour 9), 30 s in 10:00 (hour 10).
	at := time.Date(2026, 10, 21, 10, 0, 30, 0, time.Local)
	if err := s.Add(at, "kitty", "x", 90); err != nil {
		t.Fatal(err)
	}
	m := s.cur.Minutes["kitty"]
	if m["599"] != 60 || m["600"] != 30 || s.cur.Hours["9"]["kitty"].Seconds != 60 || s.cur.Hours["10"]["kitty"].Seconds != 30 {
		t.Fatalf("split: minutes %v hours %+v %+v", m, s.cur.Hours["9"]["kitty"], s.cur.Hours["10"]["kitty"])
	}
	// The first add wrote the file; the next within a minute only marks it dirty.
	s.Add(at.Add(15*time.Second), "kitty", "x", 15)
	fresh := &Store{Dir: dir}
	if sum, _ := fresh.DaySummary("2026-10-21"); sum.Total != 90 {
		t.Fatalf("batched: on disk %d, want 90 until the next save", sum.Total)
	}
	s.Flush()
	if sum, _ := (&Store{Dir: dir}).DaySummary("2026-10-21"); sum.Total != 105 {
		t.Fatalf("after flush: %d", sum.Total)
	}
	// A report crossing midnight saves the old day and starts the new one.
	mid := time.Date(2026, 10, 22, 0, 0, 20, 0, time.Local)
	s.Add(mid, "kitty", "x", 40)
	if sum, _ := (&Store{Dir: dir}).DaySummary("2026-10-21"); sum.Total != 125 {
		t.Fatalf("old day on the new day: %d, want 125", sum.Total)
	}
	if s.curDate != "2026-10-22" || s.cur.Minutes["kitty"]["0"] != 20 {
		t.Fatalf("new day: %s %v", s.curDate, s.cur.Minutes)
	}
}
