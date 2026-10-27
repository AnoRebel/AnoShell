package hub

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"

	"ano/anod/internal/secrets"
)

func fakeWallhaven(t *testing.T, h *Hub, path func(base string) string, contentType string) (*atomic.Int32, *atomic.Value) {
	var searches atomic.Int32
	var lastKey atomic.Value
	lastKey.Store("")
	var srv *httptest.Server
	srv = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		lastKey.Store(r.Header.Get("X-API-Key"))
		if r.URL.Query().Get("apikey") != "" || r.Header.Get("User-Agent") != "AnoShell-Hub" {
			t.Errorf("key in URL or no user agent: %s", r.URL)
		}
		switch {
		case r.URL.Path == "/api/v1/search":
			searches.Add(1)
			if r.URL.Query().Get("purity") != "100" && r.Header.Get("X-API-Key") == "" {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}
			fmt.Fprintf(w, `{"data":[{"id":"94x38z","url":"https://wallhaven.cc/w/94x38z","path":"%s","resolution":"1920x1080",
				"file_size":5,"file_type":"image/png","source":"","purity":"sfw","thumbs":{"small":"%s/thumb.jpg"}},
				{"id":"BAD/ID","path":"https://x/y.png","thumbs":{"small":"https://x/t.jpg"}}],
				"meta":{"current_page":%s,"last_page":3}}`, path(srv.URL), srv.URL, r.URL.Query().Get("page"))
		case r.URL.Path == "/api/v1/w/94x38z":
			fmt.Fprintf(w, `{"data":{"id":"94x38z","path":"%s","file_type":"image/png","file_size":5}}`, path(srv.URL))
		case strings.HasPrefix(r.URL.Path, "/full/"):
			w.Header().Set("Content-Type", contentType)
			w.Write([]byte("\x89PNG!"))
		default:
			http.NotFound(w, r)
		}
	}))
	t.Cleanup(srv.Close)
	u, _ := url.Parse(srv.URL)
	h.Client, h.WallhavenAPI, h.WallhavenHosts = srv.Client(), srv.URL+"/api/v1", []string{u.Host}
	return &searches, &lastKey
}

func fullPath(base string) string { return base + "/full/94/wallhaven-94x38z.png" }

func TestWallhavenSearch(t *testing.T) {
	h, _, _ := setup(t)
	searches, lastKey := fakeWallhaven(t, h, fullPath, "image/png")
	res := h.WallhavenSearch(WallhavenQuery{Query: "mountains", Page: 2})
	if res.Error != "" || len(res.Items) != 1 || res.Items[0].ID != "94x38z" || res.Page != 2 || res.LastPage != 3 || res.HasKey {
		t.Fatalf("search %+v", res)
	}
	h.WallhavenSearch(WallhavenQuery{Query: "mountains", Page: 2})
	if searches.Load() != 1 {
		t.Fatalf("not cached: %d calls", searches.Load())
	}
	if res := h.WallhavenSearch(WallhavenQuery{Purity: "nsfw"}); res.Error == "" || searches.Load() != 1 {
		t.Fatalf("nsfw without a key: %+v", res)
	}
	if err := secrets.Set("wallhaven", "sekrit"); err != nil {
		t.Fatal(err)
	}
	res = h.WallhavenSearch(WallhavenQuery{Purity: "nsfw"})
	if res.Error != "" || !res.HasKey || lastKey.Load() != "sekrit" {
		t.Fatalf("with key: %+v (key sent %v)", res, lastKey.Load())
	}
	if res := h.WallhavenSearch(WallhavenQuery{Sorting: "rm -rf"}); res.Error == "" {
		t.Fatal("bad sorting accepted")
	}
}

func TestWallhavenInstall(t *testing.T) {
	h, _, tmp := setup(t)
	fakeWallhaven(t, h, fullPath, "image/png")
	if _, err := h.WallhavenInstall("../x"); err == nil {
		t.Fatal("bad id accepted")
	}
	p, err := h.WallhavenInstall("94x38z")
	if err != nil {
		t.Fatal(err)
	}
	if p != filepath.Join(tmp, "Pictures/Wallpapers/hub/wallhaven-94x38z.png") {
		t.Fatalf("path %s", p)
	}
	if b, _ := os.ReadFile(p); string(b) != "\x89PNG!" {
		t.Fatal("content")
	}
	r := h.receipt("wallpapers", "wallhaven-94x38z")
	if r == nil || r.Catalog != "wallhaven" || r.Files["wallhaven-94x38z.png"] != sum([]byte("\x89PNG!")) || h.Revision() != 1 {
		t.Fatalf("receipt %+v rev %d", r, h.Revision())
	}
	res, _ := h.List("wallpapers")
	if len(res.Items) != 1 || res.Items[0].Source != "installed" || res.Items[0].Catalog != "wallhaven" {
		t.Fatalf("list %+v", res.Items)
	}
	if s := h.WallhavenSearch(WallhavenQuery{}); len(s.Items) != 1 || !s.Items[0].Installed {
		t.Fatalf("installed not marked: %+v", s)
	}
	if err := h.Remove("wallpapers", "wallhaven-94x38z"); err != nil {
		t.Fatal(err)
	}
}

func TestWallhavenInstallRefusals(t *testing.T) {
	for name, c := range map[string]struct {
		path func(string) string
		ct   string
	}{
		"not an image": {fullPath, "text/html"},
		"other host":   {func(string) string { return "https://evil.example/full/94/wallhaven-94x38z.png" }, "image/png"},
		"plain http":   {func(b string) string { return strings.Replace(fullPath(b), "https://", "http://", 1) }, "image/png"},
		"ext mismatch": {func(b string) string { return b + "/full/94/wallhaven-94x38z.sh" }, "image/png"},
	} {
		h, _, tmp := setup(t)
		fakeWallhaven(t, h, c.path, c.ct)
		if _, err := h.WallhavenInstall("94x38z"); err == nil {
			t.Errorf("%s: installed", name)
		}
		if ents, _ := os.ReadDir(filepath.Join(tmp, "Pictures/Wallpapers/hub")); len(ents) != 0 {
			t.Errorf("%s: left %v", name, ents)
		}
	}
}

// Hits Wallhaven for real: ANO_LIVE=1 go test -run WallhavenLive ./internal/hub/
func TestWallhavenLive(t *testing.T) {
	if os.Getenv("ANO_LIVE") == "" {
		t.Skip("set ANO_LIVE=1 to query Wallhaven")
	}
	h, _, _ := setup(t)
	h.Client = nil
	res := h.WallhavenSearch(WallhavenQuery{Query: "mountains"})
	if res.Error != "" || len(res.Items) == 0 {
		t.Fatalf("search: %+v", res)
	}
	p, err := h.WallhavenInstall(res.Items[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("%d results, page %d/%d, installed %s", len(res.Items), res.Page, res.LastPage, p)
}

func TestWallhavenRedirects(t *testing.T) {
	h, _, _ := setup(t)
	if err := secrets.Set("wallhaven", "sekrit"); err != nil {
		t.Fatal(err)
	}
	var leaked atomic.Value
	leaked.Store("")
	other := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		leaked.Store(r.Header.Get("X-API-Key"))
		if strings.HasPrefix(r.URL.Path, "/full/") {
			w.Header().Set("Content-Type", "image/png")
			w.Write([]byte("png"))
			return
		}
		w.Write([]byte(`{"data":[],"meta":{"current_page":1,"last_page":1}}`))
	}))
	defer other.Close()
	var api *httptest.Server
	api = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/api/v1/search":
			http.Redirect(w, r, other.URL+"/search", http.StatusFound)
		case r.URL.Path == "/api/v1/w/abc":
			fmt.Fprintf(w, `{"data":{"id":"abc","path":"%s/full/ab/wallhaven-abc.png","file_type":"image/png","file_size":3}}`, api.URL)
		case strings.HasPrefix(r.URL.Path, "/full/"):
			http.Redirect(w, r, other.URL+r.URL.Path, http.StatusFound)
		}
	}))
	defer api.Close()
	// one client trusting both test certificates
	pool := api.Client().Transport.(*http.Transport).TLSClientConfig.RootCAs
	pool.AddCert(other.Certificate())
	u, _ := url.Parse(api.URL)
	h.Client, h.WallhavenAPI, h.WallhavenHosts = api.Client(), api.URL+"/api/v1", []string{u.Host}

	if res := h.WallhavenSearch(WallhavenQuery{Query: "x"}); res.Error != "" {
		t.Fatalf("search via redirect: %v", res.Error)
	}
	if leaked.Load() != "" {
		t.Fatal("API key forwarded to another host")
	}
	if _, err := h.WallhavenInstall("abc"); err == nil || !strings.Contains(err.Error(), "image host") {
		t.Fatalf("image redirect off the image host: %v", err)
	}
}
