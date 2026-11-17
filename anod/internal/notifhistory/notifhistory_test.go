package notifhistory

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type clock struct{ t time.Time }

func (c *clock) now() time.Time { return c.t }

func newStore(t *testing.T, st Settings) (*Store, *clock, *Settings) {
	t.Helper()
	if st.Dir == "" {
		st.Dir = t.TempDir()
	}
	st.Enable = true
	c := &clock{t: time.Date(2026, 11, 17, 12, 0, 0, 0, time.UTC)}
	s := &Store{Now: c.now}
	s.Settings = func() Settings { return st }
	return s, c, &st
}

func add(t *testing.T, s *Store, c *clock, app, summary string) {
	t.Helper()
	c.t = c.t.Add(time.Second)
	if _, err := s.Add(Entry{App: app, Summary: summary, Urgency: "normal"}); err != nil {
		t.Fatal(err)
	}
}

func TestAddQueryNewestFirstAndPaging(t *testing.T) {
	s, c, _ := newStore(t, Settings{})
	for i := range 7 {
		add(t, s, c, "Mail", "msg "+string(rune('a'+i)))
	}
	p := s.Query(Query{Limit: 3})
	if p.Total != 7 || len(p.Entries) != 3 || p.Entries[0].Summary != "msg g" || p.Next == "" {
		t.Fatalf("first page: %+v", p)
	}
	p2 := s.Query(Query{Limit: 3, Cursor: p.Next})
	if len(p2.Entries) != 3 || p2.Entries[0].Summary != "msg d" {
		t.Fatalf("second page: %+v", p2)
	}
	p3 := s.Query(Query{Limit: 3, Cursor: p2.Next})
	if len(p3.Entries) != 1 || p3.Entries[0].Summary != "msg a" || p3.Next != "" {
		t.Fatalf("last page: %+v", p3)
	}
}

func TestSearchAndFilters(t *testing.T) {
	s, c, _ := newStore(t, Settings{})
	add(t, s, c, "Thunderbird", "Your Invoice is ready")
	add(t, s, c, "Thunderbird", "Lunch?")
	add(t, s, c, "Slack", "invoice question")
	c.t = c.t.Add(time.Second)
	s.Add(Entry{App: "Battery", Summary: "Low", Urgency: "critical"})

	if p := s.Query(Query{Text: "INVOICE", App: "thunderbird"}); p.Total != 1 || p.Entries[0].Summary != "Your Invoice is ready" {
		t.Fatalf("text+app: %+v", p)
	}
	if p := s.Query(Query{Text: "invoice"}); p.Total != 2 {
		t.Fatalf("text: %+v", p)
	}
	if p := s.Query(Query{Urgency: []string{"critical"}}); p.Total != 1 || p.Entries[0].App != "Battery" {
		t.Fatalf("urgency: %+v", p)
	}
	since := c.t.Add(-1500 * time.Millisecond).UnixMilli()
	if p := s.Query(Query{Since: since}); p.Total != 2 {
		t.Fatalf("since: %+v", p)
	}
	if p := s.Query(Query{Text: "nothing like this"}); p.Total != 0 || len(p.Entries) != 0 {
		t.Fatalf("no match: %+v", p)
	}
}

func TestExcludeAndDisabled(t *testing.T) {
	s, c, st := newStore(t, Settings{Exclude: []string{"spotify"}})
	c.t = c.t.Add(time.Second)
	if ok, err := s.Add(Entry{App: "Spotify", Summary: "Now playing"}); ok || err != nil {
		t.Fatalf("excluded by name: ok=%v err=%v", ok, err)
	}
	if ok, _ := s.Add(Entry{App: "Music", Desktop: "Spotify", Summary: "x"}); ok {
		t.Fatal("excluded by desktop entry")
	}
	st.Enable = false
	if _, err := s.Add(Entry{App: "Mail", Summary: "x"}); err != ErrDisabled {
		t.Fatalf("disabled: %v", err)
	}
	if p := s.Query(Query{}); p.Total != 0 {
		t.Fatalf("nothing recorded: %+v", p)
	}
}

func TestRotationKeepsSearchableAndDropsOldest(t *testing.T) {
	s, c, st := newStore(t, Settings{RotateBytes: 400, RotateKeep: 2})
	for i := range 12 {
		add(t, s, c, "App", strings.Repeat("x", 60)+string(rune('a'+i)))
	}
	if _, err := os.Stat(filepath.Join(st.Dir, "history.1.jsonl")); err != nil {
		t.Fatal("expected a rotated file")
	}
	if _, err := os.Stat(filepath.Join(st.Dir, "history.3.jsonl")); err == nil {
		t.Fatal("rotateKeep 2 must not leave history.3.jsonl")
	}
	p := s.Query(Query{Limit: 500})
	if p.Total == 0 || p.Total >= 12 || !strings.HasSuffix(p.Entries[0].Summary, "l") {
		t.Fatalf("newest kept, oldest rotated away: total %d first %q", p.Total, p.Entries[0].Summary)
	}
	// The rotated file's entries are still found.
	got := map[string]bool{}
	for _, e := range p.Entries {
		got[e.ID] = true
	}
	if len(got) != p.Total {
		t.Fatal("duplicate entries across files")
	}
	if st := s.Stats(); st.Files != 3 || st.Count != p.Total {
		t.Fatalf("stats: %+v", st)
	}
}

func TestKeepDaysAndMaxEntries(t *testing.T) {
	s, c, st := newStore(t, Settings{KeepDays: 7})
	add(t, s, c, "Old", "ten days ago")
	c.t = c.t.Add(10 * 24 * time.Hour)
	add(t, s, c, "New", "today")
	if p := s.Query(Query{}); p.Total != 1 || p.Entries[0].App != "New" {
		t.Fatalf("age limit on read: %+v", p)
	}
	if n, err := s.Prune(); n != 1 || err != nil {
		t.Fatalf("prune: %d %v", n, err)
	}
	data, _ := os.ReadFile(filepath.Join(st.Dir, current))
	if strings.Contains(string(data), "ten days ago") {
		t.Fatal("old entry still in the file")
	}

	st.KeepDays, st.MaxEntries = 0, 3
	for i := range 3 {
		add(t, s, c, "N", string(rune('a'+i)))
	}
	// 4 stored, cap 3: the oldest is hidden at once...
	if p := s.Query(Query{}); p.Total != 3 || p.Entries[2].Summary != "a" {
		t.Fatalf("count limit on read: %+v", p)
	}
	// ...and trimmed from the files once past the 10% slack.
	add(t, s, c, "N", "d")
	if n := len(readAll(*st)); n != 3 {
		t.Fatalf("files trimmed to the cap: %d", n)
	}
}

func TestDelete(t *testing.T) {
	s, c, _ := newStore(t, Settings{})
	add(t, s, c, "Mail", "one")
	add(t, s, c, "Mail", "two")
	add(t, s, c, "Chat", "hello")
	add(t, s, c, "Chat", "bye")

	if n, _ := s.Delete(Query{}, false); n != 0 {
		t.Fatal("an empty filter without all must delete nothing")
	}
	id := s.Query(Query{Text: "two"}).Entries[0].ID
	if n, _ := s.Delete(Query{IDs: []string{id}}, false); n != 1 {
		t.Fatal("delete one")
	}
	if n, _ := s.Delete(Query{App: "chat"}, false); n != 2 {
		t.Fatal("delete app")
	}
	if p := s.Query(Query{}); p.Total != 1 || p.Entries[0].Summary != "one" {
		t.Fatalf("after deletes: %+v", p)
	}
	if n, _ := s.Delete(Query{}, true); n != 1 {
		t.Fatal("delete all")
	}
	if s.Stats().Count != 0 {
		t.Fatal("empty after clear")
	}
	add(t, s, c, "Mail", "after clear")
	if s.Query(Query{}).Total != 1 {
		t.Fatal("recording continues after clear")
	}
}

func TestUnwritableDirReportsError(t *testing.T) {
	dir := t.TempDir()
	blocker := filepath.Join(dir, "file")
	os.WriteFile(blocker, nil, 0o600)
	s, c, _ := newStore(t, Settings{Dir: filepath.Join(blocker, "sub")})
	c.t = c.t.Add(time.Second)
	if _, err := s.Add(Entry{App: "A", Summary: "x"}); err == nil {
		t.Fatal("expected an error")
	}
	if s.Stats().Error == "" {
		t.Fatal("stats must report the write problem")
	}
}

func TestAppsAndExpandDir(t *testing.T) {
	s, c, _ := newStore(t, Settings{})
	add(t, s, c, "Mail", "1")
	add(t, s, c, "Chat", "1")
	add(t, s, c, "chat", "2")
	if a := s.Apps(); len(a) != 2 || a[0].Count != 2 {
		t.Fatalf("apps: %+v", a)
	}
	for in, want := range map[string]string{
		"":            "/d/anoshell/notifications",
		"~/logs":      "/h/logs",
		"notes":       "/h/notes",
		"/var/x/../y": "/var/y",
	} {
		if got := ExpandDir(in, "/d", "/h"); got != want {
			t.Errorf("ExpandDir(%q) = %q, want %q", in, got, want)
		}
	}
}
