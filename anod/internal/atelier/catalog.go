package atelier

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"ano/anod/internal/config"
)

// Entry is one item in a catalog index.
type Entry struct {
	ID          string   `json:"id"`
	Type        string   `json:"type"`
	Name        string   `json:"name"`
	Version     string   `json:"version"`
	Author      string   `json:"author"`
	Licence     string   `json:"licence"`
	Description string   `json:"description"`
	Preview     string   `json:"preview"`
	URL         string   `json:"url"`
	SHA256      string   `json:"sha256"`
	Compositor  string   `json:"compositor,omitempty"`
	Revoked     bool     `json:"revoked,omitempty"`
	Hosts       []string `json:"hosts,omitempty"`
	Commands    []string `json:"commands,omitempty"`
}

// Index is a catalog's JSON.
type Index struct {
	Name  string  `json:"name"`
	Items []Entry `json:"items"`
}

// CatalogItem is an index entry as atelier.list reports it.
type CatalogItem struct {
	Entry
	Catalog     string `json:"catalog"`
	CatalogName string `json:"catalogName"`
	Installed   bool   `json:"installed"`
	Unavailable string `json:"unavailable,omitempty"`
}

// CatalogStatus is one catalog's state: ok once a cached index exists;
// offline when the last refresh failed and the cache is shown instead.
type CatalogStatus struct {
	URL       string `json:"url"`
	Name      string `json:"name"`
	OK        bool   `json:"ok"`
	Error     string `json:"error"`
	FetchedAt int64  `json:"fetchedAt"` // unix seconds, 0 = never
	Offline   bool   `json:"offline"`
}

type cachedIndex struct {
	URL string
	Index
}

const maxIndex = 4 << 20

func (h *Store) cachePath(url string) string {
	s := sha256.Sum256([]byte(url))
	return filepath.Join(h.CacheDir, "catalogs", hex.EncodeToString(s[:])[:16]+".json")
}

// cachedCatalogs reads every configured catalog from the cache.
func (h *Store) cachedCatalogs() ([]cachedIndex, []CatalogStatus) {
	var out []cachedIndex
	status := []CatalogStatus{}
	h.mu.Lock()
	errs := map[string]string{}
	for k, v := range h.fetchErr {
		errs[k] = v
	}
	h.mu.Unlock()
	for _, url := range h.Catalogs() {
		st := CatalogStatus{URL: url, Error: errs[url]}
		p := h.cachePath(url)
		b, err := os.ReadFile(p)
		var idx Index
		if err == nil {
			err = json.Unmarshal(b, &idx)
		}
		if err == nil {
			fi, _ := os.Stat(p)
			st.OK, st.Name, st.FetchedAt = true, idx.Name, fi.ModTime().Unix()
			st.Offline = st.Error != ""
			idx.Items = validEntries(idx.Items)
			out = append(out, cachedIndex{url, idx})
		} else if st.Error == "" {
			st.Error = "not fetched yet"
		}
		if st.Name == "" {
			st.Name = url
		}
		status = append(status, st)
	}
	return out, status
}

// validEntries drops entries no install could ever use.
func validEntries(in []Entry) []Entry {
	out := []Entry{}
	for _, e := range in {
		if ValidID(e.ID) && e.Type != "" {
			out = append(out, e)
		}
	}
	return out
}

func findEntry(cats []cachedIndex, url, typ, id string) (Entry, bool) {
	for _, c := range cats {
		if c.URL != url {
			continue
		}
		for _, e := range c.Items {
			if e.Type == typ && e.ID == id {
				return e, true
			}
		}
	}
	return Entry{}, false
}

// Refresh fetches every catalog (ETag-conditional); a failure keeps the cache.
func (h *Store) Refresh(typ string) (ListResult, error) {
	for _, url := range h.Catalogs() {
		err := h.fetchCatalog(url)
		h.mu.Lock()
		if h.fetchErr == nil {
			h.fetchErr = map[string]string{}
		}
		if err != nil {
			h.fetchErr[url] = err.Error()
		} else {
			delete(h.fetchErr, url)
		}
		h.mu.Unlock()
	}
	return h.List(typ)
}

func (h *Store) fetchCatalog(url string) error {
	if !strings.HasPrefix(url, "https://") {
		return errors.New("only https catalogs are fetched")
	}
	p := h.cachePath(url)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "AnoShell-Atelier")
	if et, err := os.ReadFile(p + ".etag"); err == nil {
		if _, serr := os.Stat(p); serr == nil {
			req.Header.Set("If-None-Match", strings.TrimSpace(string(et)))
		}
	}
	resp, err := h.client().Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusNotModified {
		now := time.Now()
		return os.Chtimes(p, now, now)
	}
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("HTTP %s", resp.Status)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, maxIndex+1))
	if err != nil {
		return err
	}
	if len(b) > maxIndex {
		return errors.New("catalog index is larger than 4 MiB")
	}
	var idx Index
	if err := json.Unmarshal(b, &idx); err != nil {
		return fmt.Errorf("catalog index: %v", err)
	}
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		return err
	}
	if err := config.WriteAtomic(p, b, 0o644); err != nil {
		return err
	}
	if et := resp.Header.Get("ETag"); et != "" {
		config.WriteAtomic(p+".etag", []byte(et), 0o644)
	} else {
		os.Remove(p + ".etag")
	}
	return nil
}

// client is h.Client (or a default) that follows at most 5 redirects, all https.
func (h *Store) client() *http.Client {
	c := http.Client{Timeout: 15 * time.Second}
	if h.Client != nil {
		c = *h.Client
	}
	c.CheckRedirect = httpsRedirect
	return &c
}

func httpsRedirect(req *http.Request, via []*http.Request) error {
	if len(via) >= 5 {
		return errors.New("too many redirects")
	}
	if req.URL.Scheme != "https" {
		return fmt.Errorf("refusing a redirect to %s: only https", req.URL.Redacted())
	}
	return nil
}
