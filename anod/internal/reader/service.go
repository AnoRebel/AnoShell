// Package reader is the backend of the shell's novel, manga and anime panels:
// a local HTTP server (QML Image needs an HTTP URL, so not the Unix socket)
// that starts when the first panel opens and stops once all are closed for
// the idle timeout. It listens on 127.0.0.1:0 and serves only under a random
// per-session path token. See ano/docs/reader.md.
package reader

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Kinds are the reader panels.
var Kinds = []string{"anime", "manga", "novel"}

func validKind(k string) bool {
	for _, x := range Kinds {
		if x == k {
			return true
		}
	}
	return false
}

// MaxStartAttempts bounds how often one Open tries to start the backend.
const MaxStartAttempts = 3

// Settings are read from the config on every Open, so edits apply next start.
type Settings struct {
	IdleTimeout time.Duration
	CacheMB     int
	MetaEntries int               // metadata (lists, details, chapters) kept; 0: 512
	Backends    map[string]string // kind → "go" | "python"
	Python      string            // interpreter for the python fallback
	ScriptsDir  string            // ano/scripts/reader
}

type Service struct {
	Settings func() Settings
	DataDir  string // library files ($XDG_DATA_HOME/anoshell/reader)
	CacheDir string // novel chapter lists ($XDG_CACHE_HOME/anoshell/reader)
	Logf     func(string, ...any)
	// LegacyDir holds novelmangareader's library files (~/.local/share/quickshell),
	// copied over the first time a kind's library is read (migration).
	LegacyDir string

	mu       sync.Mutex
	srv      *http.Server
	token    string
	base     string // http://127.0.0.1:<port>/<token>/
	open     map[string]bool
	idle     *time.Timer
	lastErr  string
	py       map[string]*pyBackend
	mpv      *exec.Cmd
	images   *lru
	meta     *lru
	manga    *manga
	novel    *novel
	anime    *anime
	libMu    sync.Mutex
	settings Settings
	// listen is swapped in tests to simulate a backend that can't start.
	listen func() (net.Listener, error)
}

// Status is what reader.open/status answer.
type Status struct {
	Running  bool              `json:"running"`
	URL      string            `json:"url,omitempty"` // base for every request, token included
	Open     []string          `json:"open"`
	Playing  bool              `json:"playing"`
	Backends map[string]string `json:"backends,omitempty"`
	Error    string            `json:"error,omitempty"`
	Images   map[string]int64  `json:"imageCache,omitempty"`
}

func (s *Service) logf(f string, a ...any) {
	if s.Logf != nil {
		s.Logf("reader: "+f, a...)
	}
}

func (s *Service) init() {
	if s.open == nil {
		s.open = map[string]bool{}
		s.py = map[string]*pyBackend{}
		s.images = newLRU(64 << 20)
		s.meta = newLRU(512)
	}
}

// Open marks a panel open, starting the backend if needed (up to
// MaxStartAttempts tries, then an error; nothing retries in the background).
func (s *Service) Open(kind string) (Status, error) {
	if !validKind(kind) {
		return Status{}, fmt.Errorf("unknown reader %q (want anime, manga or novel)", kind)
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.init()
	var err error
	for attempt := 1; attempt <= MaxStartAttempts; attempt++ {
		if err = s.ensureRunning(kind); err == nil {
			break
		}
		s.logf("start attempt %d/%d failed: %v", attempt, MaxStartAttempts, err)
		if attempt < MaxStartAttempts {
			s.mu.Unlock()
			time.Sleep(500 * time.Millisecond)
			s.mu.Lock()
		}
	}
	if err != nil {
		s.lastErr = fmt.Sprintf("the reader backend failed to start %d times: %v. Run `ano doctor`.", MaxStartAttempts, err)
		s.armIdle() // the server may be up for other panels, or for none
		return s.status(), errors.New(s.lastErr)
	}
	s.lastErr = ""
	s.open[kind] = true
	if s.idle != nil {
		s.idle.Stop()
	}
	return s.status(), nil
}

// Close marks a panel closed; with none open and nothing playing, the idle timer starts.
func (s *Service) Close(kind string) Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.init()
	delete(s.open, kind)
	s.armIdle()
	return s.status()
}

func (s *Service) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.init()
	return s.status()
}

func (s *Service) status() Status {
	st := Status{Running: s.srv != nil, URL: s.base, Open: []string{}, Playing: s.mpv != nil, Error: s.lastErr}
	for _, k := range Kinds {
		if s.open[k] {
			st.Open = append(st.Open, k)
		}
	}
	if s.srv != nil {
		st.Backends = map[string]string{}
		for _, k := range Kinds {
			st.Backends[k] = s.backendOf(k)
		}
		n, used := s.images.size()
		st.Images = map[string]int64{"entries": int64(n), "bytes": used}
	}
	return st
}

func (s *Service) backendOf(kind string) string {
	if s.settings.Backends[kind] == "python" {
		return "python"
	}
	return "go"
}

// armIdle (with mu held) schedules the stop once nothing needs the backend.
func (s *Service) armIdle() {
	if s.srv == nil || len(s.open) > 0 || s.mpv != nil {
		return
	}
	d := s.settings.IdleTimeout
	if d <= 0 {
		d = 120 * time.Second
	}
	if s.idle != nil {
		s.idle.Stop()
	}
	s.idle = time.AfterFunc(d, func() {
		s.mu.Lock()
		var finish func()
		if len(s.open) == 0 && s.mpv == nil {
			s.logf("idle for %s, stopping", d)
			finish = s.stop()
		}
		s.mu.Unlock()
		if finish != nil {
			finish()
		}
	})
}

// ensureRunning (mu held) starts the HTTP server and this kind's python
// backend when it uses one.
func (s *Service) ensureRunning(kind string) error {
	if s.srv == nil {
		if s.Settings != nil {
			s.settings = s.Settings()
		}
		if err := s.start(); err != nil {
			return err
		}
	}
	if s.backendOf(kind) == "python" {
		return s.ensurePython(kind)
	}
	return nil
}

func (s *Service) start() error {
	listen := s.listen
	if listen == nil {
		listen = func() (net.Listener, error) { return net.Listen("tcp", "127.0.0.1:0") }
	}
	ln, err := listen()
	if err != nil {
		return err
	}
	tok := make([]byte, 16)
	if _, err := rand.Read(tok); err != nil {
		ln.Close()
		return err
	}
	s.token = hex.EncodeToString(tok)
	s.base = fmt.Sprintf("http://%s/%s/", ln.Addr().String(), s.token)
	mb := s.settings.CacheMB
	if mb <= 0 {
		mb = 64
	}
	s.images.setMax(int64(mb) << 20)
	if n := s.settings.MetaEntries; n > 0 {
		s.meta.setMax(int64(n))
	}
	proxy := func(raw string) string { return s.base + "image?url=" + url.QueryEscape(raw) }
	s.manga = &manga{f: newFetcher(0), cache: s.meta, proxy: proxy}
	s.novel = &novel{f: newFetcher(fwnInterval), cache: s.meta, proxy: proxy, listDir: filepath.Join(s.CacheDir, "novel-chapters")}
	s.anime = &anime{f: newFetcher(0), cache: s.meta}
	s.srv = &http.Server{Handler: s, ReadHeaderTimeout: 10 * time.Second}
	go func(srv *http.Server) {
		if err := srv.Serve(ln); err != nil && !errors.Is(err, http.ErrServerClosed) {
			s.logf("serve: %v", err)
		}
	}(s.srv)
	s.logf("listening on %s", ln.Addr())
	return nil
}

// stop (mu held) detaches the listener, the python backends and the caches,
// and returns what finishes the job; call that after unlocking, since
// in-flight requests take mu while the server waits for them.
func (s *Service) stop() func() {
	srv := s.srv
	py := s.py
	s.srv, s.py = nil, map[string]*pyBackend{}
	s.token, s.base = "", ""
	s.images.setMax(0) // drop the image bytes, then allow them again
	s.images.setMax(64 << 20)
	s.meta.setMax(0)
	s.meta.setMax(512)
	return func() {
		if srv != nil {
			ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
			srv.Shutdown(ctx)
			cancel()
		}
		for _, p := range py {
			p.stop()
		}
	}
}

// Shutdown stops everything except a playing mpv (it outlives anod too).
func (s *Service) Shutdown() {
	s.mu.Lock()
	s.init()
	if s.idle != nil {
		s.idle.Stop()
	}
	finish := s.stop()
	s.mu.Unlock()
	finish()
}

// ── HTTP ───────────────────────────────────────────────────────────────

func (s *Service) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	tok := s.token
	s.mu.Unlock()
	rest, ok := strings.CutPrefix(r.URL.Path, "/"+tok+"/")
	if tok == "" || !ok {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}
	kind, endpoint, _ := strings.Cut(rest, "/")
	switch {
	case rest == "health":
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	case rest == "image":
		s.serveImage(w, r)
	case kind == "library":
		s.serveLibrary(w, r, endpoint)
	case kind == "anime" && endpoint == "play":
		s.servePlay(w, r)
	case kind == "anime" && endpoint == "stop":
		s.StopPlayback()
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	case validKind(kind):
		s.mu.Lock()
		py := s.py[kind]
		usePy := s.backendOf(kind) == "python"
		s.mu.Unlock()
		if usePy {
			dead := py == nil
			if py != nil {
				select {
				case <-py.done:
					dead = true
				default:
				}
			}
			if dead { // it exited; reopening the panel starts it again
				writeJSON(w, http.StatusServiceUnavailable, map[string]any{"error": "the python backend is not running (reopen the panel; see anod.log)", "unavailable": true})
				return
			}
			py.proxy.ServeHTTP(w, r)
			return
		}
		s.serveProvider(w, r, kind, endpoint)
	default:
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "not found"})
	}
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	b, err := json.Marshal(v)
	if err != nil {
		code, b = http.StatusInternalServerError, []byte(`{"error":"encode"}`)
	}
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Content-Length", strconv.Itoa(len(b)))
	w.WriteHeader(code)
	w.Write(b)
}

// badInput is a client mistake (400), not a broken source.
type badInput string

func (e badInput) Error() string { return string(e) }

func (s *Service) serveProvider(w http.ResponseWriter, r *http.Request, kind, endpoint string) {
	q := r.URL.Query()
	p := func(k, def string) string {
		if v := q.Get(k); v != "" {
			return v
		}
		return def
	}
	n := func(k string, def int) int { return atoiDef(q.Get(k), def) }
	need := func(k string) (string, error) {
		if v := q.Get(k); v != "" {
			return v, nil
		}
		return "", badInput("missing " + k)
	}
	ctx := r.Context()
	var (
		v   any
		err error
	)
	s.mu.Lock()
	m, nv, an := s.manga, s.novel, s.anime
	s.mu.Unlock()
	switch kind + "/" + endpoint {
	case "manga/hot":
		v, err = m.hot(ctx)
	case "manga/latest":
		v, err = m.latest(ctx, max(1, n("page", 1)))
	case "manga/search":
		var qs string
		if qs, err = need("q"); err == nil {
			v, err = m.search(ctx, qs, q.Get("type"), max(0, n("offset", 0)), p("sort", "Latest Updates"))
		}
	case "manga/info":
		var id string
		if id, err = need("id"); err == nil {
			v, err = m.info(ctx, id)
		}
	case "manga/pages":
		var id string
		if id, err = need("chapterId"); err == nil {
			v, err = m.pages(ctx, id)
		}
	case "novel/hot":
		v, err = nv.hot(ctx)
	case "novel/latest":
		v, err = nv.latest(ctx, max(1, n("page", 1)))
	case "novel/search":
		var qs string
		if qs, err = need("q"); err == nil {
			v, err = nv.search(ctx, qs)
		}
	case "novel/info":
		var id string
		if id, err = need("id"); err == nil {
			v, err = nv.info(ctx, id)
		}
	case "novel/chapter":
		var id string
		if id, err = need("id"); err == nil {
			v, err = nv.chapter(ctx, id)
		}
	case "anime/search":
		var qs string
		if qs, err = need("q"); err == nil {
			v, err = an.search(ctx, qs, mode(p("mode", "sub")))
		}
	case "anime/episodes":
		var id string
		if id, err = need("id"); err == nil {
			v, err = an.episodes(ctx, id, mode(p("mode", "sub")))
		}
	case "anime/links":
		var id, ep string
		if id, err = need("id"); err == nil {
			if ep, err = need("ep"); err == nil {
				v, err = an.links(ctx, id, ep, mode(p("mode", "sub")), p("quality", "best"))
			}
		}
	case "anime/popular":
		v, err = an.popular(ctx, min(max(1, n("size", 20)), 100), max(1, n("page", 1)), max(1, n("date_range", 1)))
	case "anime/latest":
		v, err = an.latest(ctx, min(max(1, n("limit", 26)), 100), max(1, n("page", 1)), mode(p("mode", "sub")), p("country", "ALL"), q.Get("q"))
	default:
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "not found"})
		return
	}
	var bi badInput
	switch {
	case errors.As(err, &bi):
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
	case errors.Is(err, errNoStream):
		writeJSON(w, http.StatusNotFound, map[string]any{"error": err.Error()})
	case err != nil:
		if ctx.Err() == nil {
			s.logf("%s/%s: %v", kind, endpoint, err)
		}
		// One source failing never takes the others down: the panel shows
		// "source unavailable" for this request only.
		writeJSON(w, http.StatusBadGateway, map[string]any{"error": err.Error(), "unavailable": true})
	default:
		writeJSON(w, http.StatusOK, v)
	}
}

func mode(m string) string {
	if m == "dub" || m == "raw" {
		return m
	}
	return "sub"
}

type imageEntry struct {
	body  []byte
	ctype string
}

var imgSem = make(chan struct{}, 8)

func (s *Service) serveImage(w http.ResponseWriter, r *http.Request) {
	raw := r.URL.Query().Get("url")
	u, err := url.Parse(raw)
	if raw == "" || err != nil || (u.Scheme != "http" && u.Scheme != "https") {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "want url=http(s)://…"})
		return
	}
	var e imageEntry
	if v, ok := s.images.get(raw); ok {
		e = v.(imageEntry)
	} else {
		select {
		case imgSem <- struct{}{}:
		case <-r.Context().Done():
			return
		}
		s.mu.Lock()
		f := s.manga.f
		s.mu.Unlock()
		body, ct, err := f.do(r.Context(), raw, reqOpts{headers: map[string]string{"Accept": "image/avif,image/webp,image/*,*/*;q=0.8"}})
		<-imgSem
		if err != nil {
			writeJSON(w, http.StatusBadGateway, map[string]any{"error": err.Error()})
			return
		}
		if ct == "" || !strings.HasPrefix(ct, "image/") {
			ct = http.DetectContentType(body)
		}
		e = imageEntry{body, ct}
		s.images.put(raw, e, int64(len(body)), 0)
	}
	w.Header().Set("Content-Type", e.ctype)
	w.Header().Set("Content-Length", strconv.Itoa(len(e.body)))
	w.Header().Set("Cache-Control", "private, max-age=86400")
	w.Write(e.body)
}

// ── Library ────────────────────────────────────────────────────────────

const maxLibrary = 8 << 20

// legacyLibrary names novelmangareader's per-kind library files.
var legacyLibrary = map[string]string{
	"anime": "anime_library.json",
	"manga": "manga_library.json",
	"novel": "new_novel_library.json",
}

func (s *Service) libraryPath(kind string) string {
	return filepath.Join(s.DataDir, kind+"-library.json")
}

// Library returns a kind's library (a JSON array), migrating the legacy file once.
func (s *Service) Library(kind string) ([]byte, error) {
	s.libMu.Lock()
	defer s.libMu.Unlock()
	p := s.libraryPath(kind)
	b, err := os.ReadFile(p)
	if os.IsNotExist(err) {
		if b, err = s.migrate(kind); err != nil || b == nil {
			return []byte("[]"), err
		}
	}
	if err != nil {
		return nil, err
	}
	return b, nil
}

// migrate copies the legacy library (if any) into the store; nil when there is none.
func (s *Service) migrate(kind string) ([]byte, error) {
	if s.LegacyDir == "" {
		return nil, nil
	}
	old := filepath.Join(s.LegacyDir, legacyLibrary[kind])
	b, err := os.ReadFile(old)
	if err != nil {
		return nil, nil
	}
	var arr []any
	if json.Unmarshal(b, &arr) != nil {
		s.logf("legacy %s library %s is not a JSON array; not migrated", kind, old)
		return nil, nil
	}
	if err := s.writeLibrary(kind, b); err != nil {
		return nil, err
	}
	s.logf("migrated %d %s library entries from %s", len(arr), kind, old)
	return b, nil
}

func (s *Service) writeLibrary(kind string, b []byte) error {
	if err := os.MkdirAll(s.DataDir, 0o700); err != nil {
		return err
	}
	return writeFileAtomic(s.libraryPath(kind), b, 0o600)
}

// SetLibrary replaces a kind's library atomically (old or new file, never torn).
func (s *Service) SetLibrary(kind string, b []byte) error {
	var arr []json.RawMessage
	if err := json.Unmarshal(b, &arr); err != nil {
		return badInput("library must be a JSON array")
	}
	s.libMu.Lock()
	defer s.libMu.Unlock()
	return s.writeLibrary(kind, b)
}

func (s *Service) serveLibrary(w http.ResponseWriter, r *http.Request, kind string) {
	if !validKind(kind) {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "unknown library"})
		return
	}
	switch r.Method {
	case http.MethodGet:
		b, err := s.Library(kind)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write(b)
	case http.MethodPut, http.MethodPost:
		b, err := io.ReadAll(io.LimitReader(r.Body, maxLibrary+1))
		if err == nil && len(b) > maxLibrary {
			err = badInput("library over 8 MB")
		}
		if err == nil {
			err = s.SetLibrary(kind, b)
		}
		var bi badInput
		switch {
		case errors.As(err, &bi):
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
		case err != nil:
			writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
		default:
			writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		}
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "GET or PUT"})
	}
}

// writeFileAtomic replaces path through a synced temp file and a rename.
func writeFileAtomic(path string, data []byte, perm os.FileMode) error {
	f, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp) // no-op after the rename
	if _, err := f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err := f.Chmod(perm); err != nil {
		f.Close()
		return err
	}
	if err := f.Sync(); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// ── Playback ───────────────────────────────────────────────────────────

// PlayRequest starts mpv on a stream. Values go to mpv as argv, never a shell.
type PlayRequest struct {
	URL      string `json:"url"`
	Referer  string `json:"referer"`
	Subtitle string `json:"subtitle"`
	Title    string `json:"title"`
}

func httpURL(s string) bool {
	u, err := url.Parse(s)
	return err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != ""
}

// Play replaces any running player. mpv is the reader's child, not a view's,
// so it keeps playing when the panel closes (and the backend waits for it
// before its idle stop).
func (s *Service) Play(req PlayRequest) error {
	if !httpURL(req.URL) || (req.Referer != "" && !httpURL(req.Referer)) || (req.Subtitle != "" && !httpURL(req.Subtitle)) {
		return badInput("url, referer and subtitle must be http(s) URLs")
	}
	title := req.Title
	if title == "" {
		title = "Anime"
	}
	args := []string{"--fs", "--force-window=yes", "--no-terminal", "--title=" + title}
	if req.Referer != "" {
		args = append(args, "--referrer="+req.Referer)
	}
	if req.Subtitle != "" {
		args = append(args, "--sub-file="+req.Subtitle)
	}
	args = append(args, "--", req.URL)

	s.mu.Lock()
	defer s.mu.Unlock()
	s.init()
	s.stopPlayback()
	cmd := exec.Command("mpv", args...)
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("mpv: %w", err)
	}
	s.mpv = cmd
	if s.idle != nil {
		s.idle.Stop()
	}
	go func() {
		cmd.Wait()
		s.mu.Lock()
		defer s.mu.Unlock()
		if s.mpv == cmd {
			s.mpv = nil
			s.armIdle()
		}
	}()
	return nil
}

func (s *Service) StopPlayback() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.stopPlayback()
	s.armIdle()
}

func (s *Service) stopPlayback() {
	if s.mpv != nil && s.mpv.Process != nil {
		s.mpv.Process.Kill()
	}
	s.mpv = nil
}

func (s *Service) servePlay(w http.ResponseWriter, r *http.Request) {
	var req PlayRequest
	if err := json.NewDecoder(io.LimitReader(r.Body, 64<<10)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "want {url, referer?, subtitle?, title?}"})
		return
	}
	err := s.Play(req)
	var bi badInput
	switch {
	case errors.As(err, &bi):
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": err.Error()})
	case err != nil:
		writeJSON(w, http.StatusInternalServerError, map[string]any{"error": err.Error()})
	default:
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}
