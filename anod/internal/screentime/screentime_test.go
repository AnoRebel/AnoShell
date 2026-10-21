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
	if sum.Hours[14] != 360+maxAddSeconds || sum.Hours[15] != 240 {
		t.Errorf("hours 14=%d 15=%d", sum.Hours[14], sum.Hours[15])
	}
	if sum.TopApps[0].Titles[0].Name != "nvim main.go" || sum.TopApps[0].Titles[0].Seconds != 360 {
		t.Errorf("titles %+v", sum.TopApps[0].Titles)
	}
	// A fresh store reads the same from disk.
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
	at := time.Date(2026, 10, 21, 9, 0, 0, 0, time.Local)
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
