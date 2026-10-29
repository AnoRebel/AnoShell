package atelier

// Wallhaven (https://wallhaven.cc/help/api, API v1) for the Atelier's
// Wallpapers tab: search, and install into <wallpaper folder>/atelier/ with a
// receipt (catalog "wallhaven"). The API key, when the user saved one, is
// read from the secrets store (wallhaven) and sent only as X-API-Key; it is
// never logged or put in a URL. Wallhaven allows 45 calls a minute.

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"ano/anod/internal/config"
	"ano/anod/internal/secrets"
)

const (
	WallhavenAPI      = "https://wallhaven.cc/api/v1"
	wallhavenCacheTTL = 10 * time.Minute
	wallhavenPerMin   = 40 // under Wallhaven's 45, for the shell's own picker
)

var whIDRe = regexp.MustCompile(`^[a-z0-9]+$`)

// whTypes maps the API's file_type to the extension it is saved with.
var whTypes = map[string]string{"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}

// WallhavenItem is one search result.
type WallhavenItem struct {
	ID         string `json:"id"`
	URL        string `json:"url"`   // the full image (https)
	Thumb      string `json:"thumb"` // a small thumbnail (https)
	Resolution string `json:"resolution"`
	FileSize   int64  `json:"fileSize"`
	FileType   string `json:"fileType"`
	Source     string `json:"source"`
	Purity     string `json:"purity"`
	Page       string `json:"page"` // the wallpaper's page on wallhaven.cc
	Installed  bool   `json:"installed"`
}

// WallhavenResult is atelier.wallhaven's reply; Error is set instead of failing.
type WallhavenResult struct {
	Items    []WallhavenItem `json:"items"`
	Page     int             `json:"page"`
	LastPage int             `json:"lastPage"`
	HasKey   bool            `json:"hasKey"`
	Error    string          `json:"error,omitempty"`
}

// WallhavenQuery is atelier.wallhaven's request.
type WallhavenQuery struct {
	Query   string `json:"query"`
	Page    int    `json:"page"`
	Purity  string `json:"purity"`  // sfw (default), sketchy, nsfw or Wallhaven's 3-digit code
	Sorting string `json:"sorting"` // date_added, relevance, random, views, favorites, toplist
}

type whWallpaper struct {
	ID         string `json:"id"`
	URL        string `json:"url"`
	Path       string `json:"path"`
	Resolution string `json:"resolution"`
	FileSize   int64  `json:"file_size"`
	FileType   string `json:"file_type"`
	Source     string `json:"source"`
	Purity     string `json:"purity"`
	Thumbs     struct {
		Small string `json:"small"`
	} `json:"thumbs"`
}

type whCached struct {
	at  time.Time
	res WallhavenResult
}

func (h *Store) whAPI() string {
	if h.WallhavenAPI != "" {
		return h.WallhavenAPI
	}
	return WallhavenAPI
}

// whImageHost: full images come from here only.
func (h *Store) whImageHost(host string) bool {
	if len(h.WallhavenHosts) > 0 {
		for _, x := range h.WallhavenHosts {
			if x == host {
				return true
			}
		}
		return false
	}
	return host == "w.wallhaven.cc"
}

// whClient is the https, 5-hop client with Wallhaven's rules on every hop:
// the key never follows a redirect to another host, and an image download
// stays on the image host.
func (h *Store) whClient(image bool) *http.Client {
	c := h.client()
	c.CheckRedirect = func(req *http.Request, via []*http.Request) error {
		if err := httpsRedirect(req, via); err != nil {
			return err
		}
		if image && !h.whImageHost(req.URL.Host) {
			return fmt.Errorf("refusing a redirect to %s: not Wallhaven's image host", req.URL.Host)
		}
		if req.URL.Host != via[0].URL.Host {
			req.Header.Del("X-API-Key")
		}
		return nil
	}
	return c
}

func wallhavenKey() string {
	p, err := secrets.Path("wallhaven")
	if err != nil {
		return ""
	}
	b, _ := os.ReadFile(p)
	return strings.TrimSpace(string(b))
}

// whRate allows wallhavenPerMin calls in any minute.
func (h *Store) whRate() error {
	h.mu.Lock()
	defer h.mu.Unlock()
	now := time.Now()
	keep := h.whCalls[:0]
	for _, t := range h.whCalls {
		if now.Sub(t) < time.Minute {
			keep = append(keep, t)
		}
	}
	h.whCalls = keep
	if len(keep) >= wallhavenPerMin {
		return errors.New("Wallhaven allows 45 requests a minute; try again shortly")
	}
	h.whCalls = append(h.whCalls, now)
	return nil
}

// whGet fetches an API URL with the key (if any) as a header.
func (h *Store) whGet(u, key string, v any) error {
	if err := h.whRate(); err != nil {
		return err
	}
	req, err := http.NewRequest("GET", u, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "AnoShell-Atelier")
	if key != "" {
		req.Header.Set("X-API-Key", key)
	}
	resp, err := h.whClient(false).Do(req)
	if err != nil {
		var ue *url.Error
		if errors.As(err, &ue) {
			err = ue.Err // the URL is safe to show, but keep the message short
		}
		return fmt.Errorf("Wallhaven: %v", err)
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusUnauthorized:
		return errors.New("Wallhaven refused the request (401): check your API key")
	case http.StatusTooManyRequests:
		return errors.New("Wallhaven rate limit reached (45 a minute); try again shortly")
	case http.StatusNotFound:
		return errors.New("not found on Wallhaven")
	default:
		return fmt.Errorf("Wallhaven: HTTP %s", resp.Status)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 4<<20)).Decode(v)
}

func whPurity(p string) (string, error) {
	switch p {
	case "", "sfw":
		return "100", nil
	case "sketchy":
		return "110", nil
	case "nsfw":
		return "111", nil
	}
	if len(p) == 3 && strings.Trim(p, "01") == "" && p != "000" {
		return p, nil
	}
	return "", fmt.Errorf("purity %q: want sfw, sketchy, nsfw or a code like 110", p)
}

// WallhavenSearch searches Wallhaven (cached 10 minutes per query).
func (h *Store) WallhavenSearch(q WallhavenQuery) WallhavenResult {
	key := wallhavenKey()
	res := WallhavenResult{Items: []WallhavenItem{}, Page: max(q.Page, 1), HasKey: key != ""}
	purity, err := whPurity(q.Purity)
	if err != nil {
		res.Error = err.Error()
		return res
	}
	if purity != "100" && key == "" {
		res.Error = "anything beyond SFW needs your Wallhaven API key (Settings → Wallpapers)"
		return res
	}
	m, _ := config.Effective()
	sorting := q.Sorting
	if sorting == "" {
		sorting = config.String(m, "background.wallhaven.sorting", "date_added")
	}
	switch sorting {
	case "date_added", "relevance", "random", "views", "favorites", "toplist":
	default:
		res.Error = fmt.Sprintf("sorting %q is not one Wallhaven knows", sorting)
		return res
	}
	v := url.Values{}
	v.Set("categories", config.String(m, "background.wallhaven.categories", "111"))
	v.Set("purity", purity)
	v.Set("sorting", sorting)
	v.Set("order", config.String(m, "background.wallhaven.order", "desc"))
	if sorting == "toplist" {
		v.Set("topRange", config.String(m, "background.wallhaven.topRange", "1M"))
	}
	if s := strings.TrimSpace(q.Query); s != "" {
		v.Set("q", s)
	}
	v.Set("page", strconv.Itoa(res.Page))
	u := h.whAPI() + "/search?" + v.Encode()
	cacheKey := u + "|" + strconv.FormatBool(key != "")

	h.mu.Lock()
	if c, ok := h.whCache[cacheKey]; ok && time.Since(c.at) < wallhavenCacheTTL && sorting != "random" {
		h.mu.Unlock()
		out := c.res
		out.Items = h.whMarkInstalled(append([]WallhavenItem(nil), out.Items...))
		return out
	}
	h.mu.Unlock()

	var body struct {
		Data []whWallpaper `json:"data"`
		Meta struct {
			CurrentPage int `json:"current_page"`
			LastPage    int `json:"last_page"`
		} `json:"meta"`
	}
	if err := h.whGet(u, key, &body); err != nil {
		res.Error = err.Error()
		return res
	}
	for _, w := range body.Data {
		if !whIDRe.MatchString(w.ID) || !strings.HasPrefix(w.Path, "https://") || !strings.HasPrefix(w.Thumbs.Small, "https://") {
			continue
		}
		res.Items = append(res.Items, WallhavenItem{ID: w.ID, URL: w.Path, Thumb: w.Thumbs.Small, Resolution: w.Resolution,
			FileSize: w.FileSize, FileType: w.FileType, Source: w.Source, Purity: w.Purity, Page: w.URL})
	}
	if body.Meta.CurrentPage > 0 {
		res.Page = body.Meta.CurrentPage
	}
	res.LastPage = body.Meta.LastPage
	h.mu.Lock()
	if h.whCache == nil || len(h.whCache) > 200 {
		h.whCache = map[string]whCached{}
	}
	h.whCache[cacheKey] = whCached{time.Now(), res}
	h.mu.Unlock()
	res.Items = h.whMarkInstalled(append([]WallhavenItem(nil), res.Items...))
	return res
}

func (h *Store) whMarkInstalled(items []WallhavenItem) []WallhavenItem {
	for i := range items {
		items[i].Installed = h.receipt("wallpapers", "wallhaven-"+items[i].ID) != nil
	}
	return items
}

// WallhavenInstall downloads wallpaper id (looked up again, never from a
// client-supplied URL) into <wallpaper folder>/atelier/wallhaven-<id>.<ext>.
func (h *Store) WallhavenInstall(id string) (string, error) {
	if !whIDRe.MatchString(id) || len(id) > 32 {
		return "", fmt.Errorf("invalid Wallhaven id %q", id)
	}
	itemID := "wallhaven-" + id
	if h.receipt("wallpapers", itemID) == nil {
		if p := h.userItemPath("wallpapers", itemID); p != "" {
			return "", fmt.Errorf("you already have %s", p)
		}
	}
	var info struct {
		Data whWallpaper `json:"data"`
	}
	if err := h.whGet(h.whAPI()+"/w/"+id, wallhavenKey(), &info); err != nil {
		return "", err
	}
	w := info.Data
	ext, ok := whTypes[w.FileType]
	if !ok {
		return "", fmt.Errorf("Wallhaven says %q, not a JPEG, PNG or WebP", w.FileType)
	}
	pu, err := url.Parse(w.Path)
	if err != nil || pu.Scheme != "https" || !h.whImageHost(pu.Host) || w.ID != id {
		return "", fmt.Errorf("unexpected image location %q", w.Path)
	}
	if e := strings.TrimPrefix(strings.ToLower(filepath.Ext(pu.Path)), "."); e != ext && !(ext == "jpg" && e == "jpeg") {
		return "", fmt.Errorf("the image is %s but its file ends in .%s", w.FileType, e)
	}
	if w.FileSize > MaxWallpaperDownload {
		return "", fmt.Errorf("the image is larger than %d MiB", MaxWallpaperDownload>>20)
	}

	req, _ := http.NewRequest("GET", pu.String(), nil)
	req.Header.Set("User-Agent", "AnoShell-Atelier")
	c := h.whClient(true)
	c.Timeout = 2 * time.Minute
	resp, err := c.Do(req)
	if err != nil {
		return "", fmt.Errorf("download: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("download: HTTP %s", resp.Status)
	}
	if ct := strings.TrimSpace(strings.SplitN(resp.Header.Get("Content-Type"), ";", 2)[0]); whTypes[ct] == "" {
		return "", fmt.Errorf("download: the server sent %q, not an image", ct)
	}
	dir := h.userDir("wallpapers")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	tok, err := token()
	if err != nil {
		return "", err
	}
	stage := filepath.Join(dir, stagePrefix+tok)
	defer os.Remove(stage)
	f, err := os.OpenFile(stage, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return "", err
	}
	sum := sha256.New()
	n, err := io.Copy(io.MultiWriter(f, sum), io.LimitReader(resp.Body, MaxWallpaperDownload+1))
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return "", fmt.Errorf("download: %v", err)
	}
	if n > MaxWallpaperDownload {
		return "", fmt.Errorf("the image is larger than %d MiB", MaxWallpaperDownload>>20)
	}
	dst := filepath.Join(dir, itemID+"."+ext)
	if fi, err := os.Lstat(dst); err == nil && fi.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("refusing to replace symlink %s", dst)
	}
	if err := os.Rename(stage, dst); err != nil {
		return "", err
	}
	if old := h.receipt("wallpapers", itemID); old != nil && old.Path != dst && strings.HasPrefix(old.Path, dir+string(filepath.Separator)) {
		os.Remove(old.Path)
	}
	r := Receipt{Catalog: "wallhaven", Version: "", InstalledAt: time.Now().UTC(), Path: dst,
		Files: map[string]string{filepath.Base(dst): hex.EncodeToString(sum.Sum(nil))}, Hosts: []string{}, Commands: []string{}}
	if err := h.writeReceipt("wallpapers", itemID, r); err != nil {
		return "", err
	}
	h.bump()
	return dst, nil
}
