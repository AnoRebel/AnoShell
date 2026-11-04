package reader

import (
	"context"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func fixture(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func proxyStub(raw string) string { return "P:" + raw }

// ── Fixtures (recorded 2026-10-19) ─────────────────────────────────────

func TestMangaFixtures(t *testing.T) {
	m := &manga{proxy: proxyStub}
	s := m.parseSearch(fixture(t, "wc_search.html"))
	if len(s) != 3 || s[0].ID != "01J76XYCPSY3C4BNPBRY8JMCBE/Solo-Leveling" || s[0].Title != "Solo Leveling" ||
		s[0].Type != "Manhwa" || s[0].Year != "2018" || s[0].Status != "Complete" || len(s[0].Tags) != 4 {
		t.Fatalf("search: %+v", s)
	}
	if hot := m.parseHot(fixture(t, "wc_hot.html")); len(hot) < 10 || hot[0].ID == "" || hot[0].Title == "" || !strings.HasPrefix(hot[0].Image, "P:https://") {
		t.Fatalf("hot: %d %+v", len(hot), hot)
	}
	l := m.parseLatest(fixture(t, "wc_latest.html"), 1)
	res := l["results"].([]mangaCard)
	withChapter := 0
	for _, r := range res {
		if r.Chapter != "" {
			withChapter++
		}
	}
	if len(res) < 10 || withChapter < len(res)/2 || l["hasMore"] != true {
		t.Fatalf("latest: %+v", l)
	}
	info := m.parseInfo("01J76XYHERFDX1V9X4A032QT6B/Solo-Leveling-Ragnarok", fixture(t, "wc_series.html"), fixture(t, "wc_chapters.html"))
	chs := info["chapters"].([]mangaChapter)
	if info["title"] != "Solo Leveling: Ragnarok" || len(chs) < 50 || chs[0].Chapter != "1" || chs[0].ID == "" {
		t.Fatalf("info: title=%q chapters=%d first=%+v", info["title"], len(chs), chs[:min(1, len(chs))])
	}
	if info["description"] == "" || len(info["authors"].([]string)) == 0 || info["status"] == "" {
		t.Errorf("info metadata: desc=%q authors=%v status=%q", info["description"], info["authors"], info["status"])
	}
	pages := m.parsePages(fixture(t, "wc_pages.html"))
	if len(pages) < 10 || pages[0].Page != 1 || pages[0].Img != "P:https://official.lowee.us/manga/Solo-Leveling-Ragnarok/0068-001.png" {
		t.Fatalf("pages: %d %+v", len(pages), pages[:min(2, len(pages))])
	}
}

func TestNovelFixtures(t *testing.T) {
	n := &novel{proxy: proxyStub}
	hot := n.parseRows(fixture(t, "fwn_hot.html"))
	if len(hot) < 10 || hot[0].ID != "freewebnovel:novel/shadow-slave" || hot[0].Title != "Shadow Slave" ||
		hot[0].Image != "P:https://freewebnovel.com/files/article/image/1/1991/1991s.jpg" || hot[0].LatestChapter == "" {
		t.Fatalf("hot: %+v", hot[:min(1, len(hot))])
	}
	if s := n.parseRows(fixture(t, "fwn_search.html")); len(s) == 0 || s[0].ID != "freewebnovel:novel/shadow-slave" {
		t.Fatalf("search: %+v", s)
	}
	page := fixture(t, "fwn_novel.html")
	info := n.parseInfo("novel/shadow-slave", page)
	if info["title"] != "Shadow Slave" || info["author"] == "" || info["description"] == "" || len(info["genres"].([]string)) == 0 {
		t.Fatalf("info: %+v", info)
	}
	if inline := parseFwnAnchors("novel/shadow-slave", group(fwnIDDataRE, page, 1)); len(inline) == 0 {
		t.Error("no inline chapters on the novel page")
	}
	full := dedupeSortChapters(parseFwnOptions("novel/shadow-slave", fixture(t, "fwn_chapterlist.json")))
	if len(full) < 3000 || full[0].ID != "novel/shadow-slave/chapter-1" || full[0].Title != "Chapter 1: Nightmare Begins" || full[0].Chapter != "1" {
		t.Fatalf("chapter list: %d %+v", len(full), full[:min(1, len(full))])
	}
	ch := parseFwnChapter("novel/shadow-slave/chapter-1", fixture(t, "fwn_chapter.html"))
	paras := ch["paragraphs"].([]string)
	if ch["title"] != "Chapter 1: Nightmare Begins" || len(paras) < 20 || ch["wordCount"].(int) < 1000 {
		t.Fatalf("chapter: title=%q paras=%d words=%v", ch["title"], len(paras), ch["wordCount"])
	}
	if ch["nextId"] != "freewebnovel:novel/shadow-slave/chapter-2" || ch["prevId"] != "" {
		t.Errorf("chapter nav: prev=%q next=%q", ch["prevId"], ch["nextId"])
	}
}

func TestNovelIDs(t *testing.T) {
	if _, err := fwnStrip("novel/x"); err == nil {
		t.Error("unprefixed id accepted")
	}
	if _, err := fwnStrip("freewebnovel:../etc"); err == nil {
		t.Error("traversal accepted")
	}
	if id, err := fwnStrip("freewebnovel:novel/x/chapter-2"); err != nil || id != "novel/x/chapter-2" {
		t.Errorf("strip: %q %v", id, err)
	}
}

func TestAnimeFixtures(t *testing.T) {
	cfg, err := zokoConfig(fixture(t, "zoko_embed.html"))
	if err != nil || !strings.Contains(cfg["src"].(string), ".m3u8") {
		t.Fatalf("zoko: %v %v", cfg, err)
	}
	if cfg, err := zokoConfig("<html>no blob</html>"); cfg != nil || err != nil {
		t.Error("a page without a blob is 'no stream', not an error")
	}
	eps := []string{"10", "9", "1", "2.5", "2"}
	sortNumeric(eps)
	if strings.Join(eps, ",") != "1,2,2.5,9,10" {
		t.Errorf("episode order: %v", eps)
	}
}

// ── Lifecycle ──────────────────────────────────────────────────────────

func newService(t *testing.T) *Service {
	t.Helper()
	d := t.TempDir()
	return &Service{
		DataDir: filepath.Join(d, "data"), CacheDir: filepath.Join(d, "cache"), LegacyDir: filepath.Join(d, "legacy"),
		Settings: func() Settings { return Settings{IdleTimeout: 150 * time.Millisecond, CacheMB: 1} },
	}
}

func get(t *testing.T, u string) (int, string) {
	t.Helper()
	resp, err := http.Get(u)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

func TestTokenRejection(t *testing.T) {
	s := newService(t)
	st, err := s.Open("manga")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Shutdown()
	if code, _ := get(t, st.URL+"health"); code != 200 {
		t.Fatalf("health with token: %d", code)
	}
	root := st.URL[:strings.LastIndex(strings.TrimSuffix(st.URL, "/"), "/")+1] // http://127.0.0.1:port/
	for _, p := range []string{"health", "deadbeef/health", "manga/hot", strings.Repeat("0", 32) + "/health"} {
		if code, _ := get(t, root+p); code != http.StatusForbidden {
			t.Errorf("%s: %d, want 403", p, code)
		}
	}
	if !strings.HasPrefix(st.URL, "http://127.0.0.1:") || strings.Contains(st.URL, ":5050/") {
		t.Errorf("listens on %s; want a random 127.0.0.1 port", st.URL)
	}
}

func TestIdleStop(t *testing.T) {
	s := newService(t)
	st, err := s.Open("novel")
	if err != nil {
		t.Fatal(err)
	}
	s.Open("anime")
	addr := strings.SplitN(st.URL, "/", 4)[2]
	s.Close("novel")
	time.Sleep(300 * time.Millisecond)
	if !s.Status().Running {
		t.Fatal("stopped while the anime panel was still open")
	}
	s.Close("anime")
	time.Sleep(400 * time.Millisecond)
	if s.Status().Running {
		t.Fatal("still running after the idle timeout")
	}
	if c, err := net.DialTimeout("tcp", addr, 200*time.Millisecond); err == nil {
		c.Close()
		t.Fatalf("listener %s still accepts connections", addr)
	}
	// Reopening starts it again, on a new token.
	st2, err := s.Open("manga")
	if err != nil || st2.URL == st.URL {
		t.Fatalf("reopen: %v %q", err, st2.URL)
	}
	s.Shutdown()
}

func TestRetryLimit(t *testing.T) {
	s := newService(t)
	calls := 0
	s.listen = func() (net.Listener, error) { calls++; return nil, errors.New("no sockets for you") }
	_, err := s.Open("manga")
	if err == nil || calls != MaxStartAttempts || !strings.Contains(err.Error(), "ano doctor") {
		t.Fatalf("calls=%d err=%v", calls, err)
	}
	time.Sleep(700 * time.Millisecond) // nothing retries in the background
	if calls != MaxStartAttempts || s.Status().Running {
		t.Fatalf("retried on its own: calls=%d", calls)
	}
	if s.Status().Error == "" {
		t.Error("status does not report the failure")
	}
}

func TestBadRequests(t *testing.T) {
	s := newService(t)
	st, _ := s.Open("manga")
	defer s.Shutdown()
	for p, want := range map[string]int{
		"manga/search": 400, "manga/info": 400, "novel/chapter": 400, "anime/links?id=x": 400,
		"manga/nope": 404, "image?url=file:///etc/passwd": 400, "image": 400, "library/other": 404,
	} {
		if code, body := get(t, st.URL+p); code != want {
			t.Errorf("%s: %d %s, want %d", p, code, body, want)
		}
	}
}

// ── Library store ──────────────────────────────────────────────────────

func TestLibraryStoreAndMigration(t *testing.T) {
	s := newService(t)
	os.MkdirAll(s.LegacyDir, 0o700)
	legacy := `[{"id":"01J76XYCPSY3C4BNPBRY8JMCBE/Solo-Leveling","title":"Solo Leveling","lastReadChapterNum":"12"}]`
	os.WriteFile(filepath.Join(s.LegacyDir, "manga_library.json"), []byte(legacy), 0o644)

	b, err := s.Library("manga")
	if err != nil || string(b) != legacy {
		t.Fatalf("migration: %s %v", b, err)
	}
	if fi, err := os.Stat(s.libraryPath("manga")); err != nil || fi.Mode().Perm() != 0o600 {
		t.Fatalf("store file: %v %v", fi, err)
	}
	if b, _ := s.Library("anime"); string(b) != "[]" {
		t.Errorf("empty library: %s", b)
	}

	st, _ := s.Open("manga")
	defer s.Shutdown()
	req, _ := http.NewRequest(http.MethodPut, st.URL+"library/manga", strings.NewReader(`[{"id":"a"}]`))
	resp, err := http.DefaultClient.Do(req)
	if err != nil || resp.StatusCode != 200 {
		t.Fatalf("put: %v %v", resp, err)
	}
	if code, body := get(t, st.URL+"library/manga"); code != 200 || body != `[{"id":"a"}]` {
		t.Fatalf("get after put: %d %s", code, body)
	}
	// The legacy file is never touched, and a migrated store is not re-migrated.
	if b, _ := os.ReadFile(filepath.Join(s.LegacyDir, "manga_library.json")); string(b) != legacy {
		t.Error("legacy file changed")
	}
	req, _ = http.NewRequest(http.MethodPut, st.URL+"library/manga", strings.NewReader(`{"not":"an array"}`))
	if resp, _ := http.DefaultClient.Do(req); resp.StatusCode != 400 {
		t.Errorf("non-array accepted: %d", resp.StatusCode)
	}
	// No temp files left behind.
	ents, _ := os.ReadDir(s.DataDir)
	for _, e := range ents {
		if strings.Contains(e.Name(), ".tmp-") {
			t.Errorf("leftover %s", e.Name())
		}
	}
}

func TestPlayValidation(t *testing.T) {
	s := newService(t)
	for _, r := range []PlayRequest{{URL: "file:///etc/passwd"}, {URL: "--input-ipc-server=/tmp/x"}, {URL: "https://a/b.m3u8", Subtitle: "/etc/x"}} {
		if err := s.Play(r); err == nil {
			t.Errorf("accepted %+v", r)
		}
	}
}

func TestLRU(t *testing.T) {
	c := newLRU(10)
	c.put("a", 1, 4, 0)
	c.put("b", 2, 4, 0)
	c.get("a") // a is now the most recent
	c.put("c", 3, 4, 0)
	if _, ok := c.get("b"); ok {
		t.Error("b should have been evicted")
	}
	if _, ok := c.get("a"); !ok {
		t.Error("a evicted despite recent use")
	}
	if n, used := c.size(); n != 2 || used != 8 {
		t.Errorf("size %d/%d", n, used)
	}
	c.put("big", 0, 11, 0)
	if _, ok := c.get("big"); ok {
		t.Error("an entry over the cap was stored")
	}
	c.put("t", 0, 1, time.Millisecond)
	time.Sleep(5 * time.Millisecond)
	if _, ok := c.get("t"); ok {
		t.Error("expired entry returned")
	}
}

// A source set to "python" is served by its (here: fake) Python server through
// anod's token-checked proxy, while the others stay on Go.
func TestPythonFallback(t *testing.T) {
	if !haveBin("python3") {
		t.Skip("no python3")
	}
	s := newService(t)
	scripts := t.TempDir()
	fake := `import os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        body = b'{"ok": true}' if self.path == "/health" else ('{"from": "python", "path": "%s", "img": "%s"}' % (self.path, os.environ["ANO_READER_IMAGE_BASE"])).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(body)
HTTPServer(("127.0.0.1", int(os.environ["ANO_READER_PORT"])), H).serve_forever()
`
	os.WriteFile(filepath.Join(scripts, "manga_server.py"), []byte(fake), 0o644)
	s.Settings = func() Settings {
		return Settings{IdleTimeout: time.Minute, Python: "python3", ScriptsDir: scripts, Backends: map[string]string{"manga": "python"}}
	}
	st, err := s.Open("manga")
	if err != nil {
		t.Fatal(err)
	}
	defer s.Shutdown()
	if st.Backends["manga"] != "python" || st.Backends["novel"] != "go" {
		t.Fatalf("backends: %v", st.Backends)
	}
	code, body := get(t, st.URL+"manga/hot?x=1")
	if code != 200 || !strings.Contains(body, `"from": "python"`) || !strings.Contains(body, `"path": "/hot?x=1"`) || !strings.Contains(body, st.URL+"manga") {
		t.Fatalf("manga via python: %d %s", code, body)
	}
	if code, body := get(t, st.URL+"novel/search"); code != 400 || !strings.Contains(body, "missing q") { // Go's answer
		t.Fatalf("novel via go: %d %s", code, body)
	}
	pid := s.py["manga"].cmd.Process.Pid
	s.Shutdown()
	if err := syscall.Kill(pid, 0); err == nil {
		t.Errorf("python backend %d still running after shutdown", pid)
	}
}

func haveBin(b string) bool { _, err := exec.LookPath(b); return err == nil }

func TestFriendlyErr(t *testing.T) {
	u := "https://weebcentral.com/search/data?text=x"
	cases := map[string]error{
		"the connection to weebcentral.com dropped": &url.Error{Op: "Get", URL: u, Err: io.ErrUnexpectedEOF},
		"couldn't find weebcentral.com (offline?)":  &url.Error{Op: "Get", URL: u, Err: &net.DNSError{Err: "no such host", Name: "weebcentral.com"}},
		"couldn't reach weebcentral.com (offline?)": &url.Error{Op: "Get", URL: u, Err: &net.OpError{Op: "dial", Err: errors.New("connection refused")}},
		"weebcentral.com didn't answer in time":     &url.Error{Op: "Get", URL: u, Err: context.DeadlineExceeded},
		"HTTP 503 from weebcentral.com":             &statusError{Code: 503, URL: u},
		"plain":                                     errors.New("plain"),
	}
	for want, err := range cases {
		if got := friendlyErr(err); got != want {
			t.Errorf("friendlyErr(%v) = %q, want %q", err, got, want)
		}
	}
}
