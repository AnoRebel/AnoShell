package reader

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestNovelArrowParse(t *testing.T) {
	n := &novelArrow{proxy: func(s string) string { return "P:" + s }}
	html := `<ul><div class="row"><img src="/cover/a.jpg"><h3 class="novel-title"><a href="https://novelping.com/book/shadow-slave">Shadow &amp; Slave</a></h3>
<span class="author">Guiltythree</span> </div><span class="x chapter-title">Chapter 9</span>
<div class="row"><h3 class="novel-title"><a href="/book/shadow-slave">dup</a></h3></div>
<li class="next"><a>»</a></li></ul>`
	rows := n.parseRows(html)
	if len(rows) != 1 || rows[0].ID != "novelarrow:shadow-slave" || rows[0].Title != "Shadow & Slave" ||
		rows[0].Image != "P:https://novelping.com/cover/a.jpg" || rows[0].Author != "Guiltythree" || rows[0].LatestChapter != "Chapter 9" {
		t.Fatalf("rows: %+v", rows)
	}
	if !narHasNext(html) || narHasNext(`<li class="next disabled">`) || narHasNext("") {
		t.Fatal("hasNext")
	}
	for _, bad := range []string{"freewebnovel:x", "novelarrow:../x", "novelarrow:a/b/c", "novelarrow:a b", "novelarrow:", "novelarrow:.", "novelarrow:s/.."} {
		if _, _, err := narStrip(bad); err == nil {
			t.Fatalf("narStrip accepted %q", bad)
		}
	}
	if s, c, err := narStrip("novelarrow:shadow-slave/chapter-1-x"); err != nil || s != "shadow-slave" || c != "chapter-1-x" {
		t.Fatalf("narStrip: %q %q %v", s, c, err)
	}

	ch := parseNarChapter("s", "c-2", narChapterInfo{Name: "Ch 2", Content: "<h4>Ch 2</h4>one<br/>two  words",
		Prev: &struct {
			ID string `json:"chapter_id"`
		}{"c-1"}})
	if p := ch["paragraphs"].([]string); len(p) != 2 || p[1] != "two words" || ch["wordCount"] != 3 ||
		ch["prevId"] != "novelarrow:s/c-1" || ch["nextId"] != "" {
		t.Fatalf("chapter: %+v", ch)
	}

	items := []struct {
		ID   string `json:"chapter_id"`
		Name string `json:"chapter_name"`
	}{{"chapter-1-a", "Chapter 1 A"}, {"027-b", "B"}, {"chapter-3", "Chapter 3"}}
	info := n.parseInfo("s", `<meta property="og:novel:novel_name" content="S"><meta property="og:novel:status" content="OnGoing">`, items)
	chs := info["chapters"].([]novelChapter)
	if info["title"] != "S" || info["status"] != "Ongoing" || len(chs) != 3 || chs[1].Chapter != "2" || chs[1].Title != "B" {
		t.Fatalf("info: %+v", info) // "B" has no number: the list falls back to positions
	}
}

// Hits novelping.com for real: ANO_LIVE=1 go test -run NovelArrowLive ./internal/reader/
func TestNovelArrowLive(t *testing.T) {
	if os.Getenv("ANO_LIVE") == "" {
		t.Skip("set ANO_LIVE=1 to query NovelArrow")
	}
	n := &novelArrow{f: newFetcher(narInterval), cache: newLRU(100), proxy: func(s string) string { return s }}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	hot, err := n.hot(ctx)
	if err != nil || len(hot) == 0 {
		t.Fatalf("hot: %d %v", len(hot), err)
	}
	s, err := n.search(ctx, "shadow slave", 1)
	if err != nil || len(s["results"].([]novelCard)) == 0 {
		t.Fatalf("search: %v %v", s, err)
	}
	info, err := n.info(ctx, hot[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	chs := info["chapters"].([]novelChapter)
	if len(chs) == 0 {
		t.Fatalf("no chapters: %+v", info)
	}
	ch, err := n.chapter(ctx, chs[0].ID)
	if err != nil || len(ch["paragraphs"].([]string)) < 3 || ch["nextId"] == "" {
		t.Fatalf("chapter: %v %v", ch, err)
	}
	t.Logf("%s: %d chapters; %q has %d paragraphs, next %v", info["title"], len(chs), ch["title"], len(ch["paragraphs"].([]string)), ch["nextId"])
}
