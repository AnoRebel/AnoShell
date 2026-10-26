package reader

import (
	"context"
	"errors"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The sources answer plain Go TLS (checked 2026-10-19 against weebcentral,
// freewebnovel, allanime, hianime and zokoanime), so there is no browser
// TLS impersonation here.
// ponytail: plain net/http; if Cloudflare starts fingerprinting, switch that
// provider to backend "python" (curl_cffi) or add bogdanfinn/tls-client.
const userAgent = "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"

var browserHeaders = map[string]string{
	"User-Agent":      userAgent,
	"Accept":          "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
	"Accept-Language": "en-US,en;q=0.5",
}

// maxBody bounds any one response (a chapter page is ~200 KB, an image a few MB).
const maxBody = 32 << 20

// fetcher does a provider's HTTP: browser-like headers, one retry on
// connection errors, and optional pacing (a minimum interval between page
// requests, with HTTP 429 waited out) for sites that rate-limit.
type fetcher struct {
	client   *http.Client
	interval time.Duration // 0: no pacing
	mu       sync.Mutex
	next     time.Time
}

func newFetcher(interval time.Duration) *fetcher {
	return &fetcher{client: &http.Client{Timeout: 30 * time.Second}, interval: interval}
}

// statusError is a non-2xx reply.
type statusError struct {
	Code int
	URL  string
}

func (e *statusError) Error() string { return fmt.Sprintf("HTTP %d from %s", e.Code, hostOf(e.URL)) }

func hostOf(u string) string {
	if p, err := url.Parse(u); err == nil {
		return p.Host
	}
	return u
}

// pace waits for this fetcher's next request slot.
func (f *fetcher) pace(ctx context.Context) error {
	if f.interval == 0 {
		return nil
	}
	f.mu.Lock()
	now := time.Now()
	slot := f.next
	if slot.Before(now) {
		slot = now
	}
	f.next = slot.Add(f.interval)
	f.mu.Unlock()
	select {
	case <-time.After(time.Until(slot)):
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (f *fetcher) backoff(d time.Duration) {
	f.mu.Lock()
	if t := time.Now().Add(d); t.After(f.next) {
		f.next = t
	}
	f.mu.Unlock()
}

type reqOpts struct {
	method  string
	headers map[string]string
	body    string // sent as-is; set Content-Type in headers
	paced   bool
}

// do returns the body and content type of a 2xx reply.
func (f *fetcher) do(ctx context.Context, u string, o reqOpts) ([]byte, string, error) {
	tries := 1
	if o.paced {
		tries = 4
	}
	for attempt := 0; ; attempt++ {
		if o.paced {
			if err := f.pace(ctx); err != nil {
				return nil, "", err
			}
		}
		b, ct, err := f.once(ctx, u, o)
		var se *statusError
		if o.paced && errors.As(err, &se) && se.Code == http.StatusTooManyRequests && attempt < tries-1 {
			f.backoff(time.Duration(6*(attempt+1)) * time.Second)
			continue
		}
		return b, ct, err
	}
}

func (f *fetcher) once(ctx context.Context, u string, o reqOpts) ([]byte, string, error) {
	var lastErr error
	for attempt := 0; attempt < 2; attempt++ { // one retry on connection-level errors
		method := o.method
		if method == "" {
			method = http.MethodGet
		}
		var body io.Reader
		if o.body != "" {
			body = strings.NewReader(o.body)
		}
		req, err := http.NewRequestWithContext(ctx, method, u, body)
		if err != nil {
			return nil, "", err
		}
		for k, v := range browserHeaders {
			req.Header.Set(k, v)
		}
		for k, v := range o.headers {
			req.Header.Set(k, v)
		}
		resp, err := f.client.Do(req)
		if err != nil {
			lastErr = err
			if ctx.Err() != nil {
				return nil, "", err
			}
			time.Sleep(300 * time.Millisecond)
			continue
		}
		b, err := io.ReadAll(io.LimitReader(resp.Body, maxBody+1))
		resp.Body.Close()
		if resp.StatusCode/100 != 2 {
			return nil, "", &statusError{Code: resp.StatusCode, URL: u}
		}
		if err != nil {
			return nil, "", err
		}
		if len(b) > maxBody { // never hand on (or cache) a cut-off body
			return nil, "", fmt.Errorf("response from %s is over %d MB", hostOf(u), maxBody>>20)
		}
		return b, resp.Header.Get("Content-Type"), nil
	}
	return nil, "", lastErr
}

func (f *fetcher) text(ctx context.Context, u string, o reqOpts) (string, error) {
	b, _, err := f.do(ctx, u, o)
	return string(b), err
}

// ── Text helpers shared by the HTML providers ──────────────────────────

var (
	tagRE   = regexp.MustCompile(`<[^>]+>`)
	spaceRE = regexp.MustCompile(`\s+`)
)

// cleanText strips tags, decodes entities and collapses whitespace. Some
// sites double-encode ("&amp;amp;", "&amp;#39;"), so decoding repeats until
// nothing changes (at most 3 times).
func cleanText(s string) string {
	s = tagRE.ReplaceAllString(s, " ")
	for i := 0; i < 3; i++ {
		d := html.UnescapeString(s)
		if d == s {
			break
		}
		s = d
	}
	s = strings.ReplaceAll(s, " ", " ")
	return strings.TrimSpace(spaceRE.ReplaceAllString(s, " "))
}

// group returns submatch n of the first match of re in s, or "".
func group(re *regexp.Regexp, s string, n int) string {
	m := re.FindStringSubmatch(s)
	if len(m) <= n {
		return ""
	}
	return m[n]
}

func atoiDef(s string, def int) int {
	if n, err := strconv.Atoi(s); err == nil {
		return n
	}
	return def
}
