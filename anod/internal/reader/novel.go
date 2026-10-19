package reader

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"math/rand/v2"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Novels: freewebnovel.com, scraped. Ported from novelmangareader's
// novel_server (providers/freewebnovel.py). IDs crossing the HTTP boundary
// carry the provider prefix ("freewebnovel:novel/slug") as there.

const (
	fwnName = "freewebnovel"
	fwnBase = "https://freewebnovel.com"
	// The site rate-limits page requests: measured 2026-09-28 by the Python
	// port, one every ~0.9 s ran 40 in a row cleanly; ~0.6 s tripped 429.
	fwnInterval = 800 * time.Millisecond
)

var (
	fwnSlugRE     = regexp.MustCompile(`href="/novel/([^"/?]+)"`)
	fwnTitRE      = regexp.MustCompile(`<h3 class="tit">\s*<a[^>]*>([^<]+)</a>`)
	fwnImgRE      = regexp.MustCompile(`<img\s+src="(/files/article/image/[^"]+)"`)
	fwnGenreRE    = regexp.MustCompile(`href="/genre/[^"]*"[^>]*>([^<]+)</a>`)
	fwnLastChapRE = regexp.MustCompile(`<a[^>]+class="chapter"[^>]*title="([^"]*)"`)
	fwnNextRE     = regexp.MustCompile(`<a[^>]+class="[^"]*next[^"]*"|rel="next"`)
	fwnChAnchorRE = regexp.MustCompile(`<a\s+href="/novel/[^/]+/([^"]+)"\s+title="([^"]*)"[^>]*class="con"`)
	fwnChNumRE    = regexp.MustCompile(`[Cc]hapter[\s-]*([\d.]+)`)
	fwnAidRE      = regexp.MustCompile(`data-article-id="(\d+)"|data-novel-id="(\d+)"|articleId:\s*(\d+)`)
	fwnTotalRE    = regexp.MustCompile(`data-total-chapters="(\d+)"`)
	fwnOptionRE   = regexp.MustCompile(`<option[^>]+value="/?novel/[^/"]+/([^"]+)"[^>]*>([\s\S]*?)</option>`)
	fwnSlugNumRE  = regexp.MustCompile(`chapter-([\d.]+)`)
	fwnCHPrefixRE = regexp.MustCompile(`^CH\.\s*`)
	fwnSortKeyRE  = regexp.MustCompile(`(?i)chapter[\s-]*([\d.]+)`)
	fwnCoverRE    = regexp.MustCompile(`<meta name="image" content="([^"]+)"`)
	fwnOgImageRE  = regexp.MustCompile(`<meta property="og:image" content="([^"]+)"`)
	fwnOgTitleRE  = regexp.MustCompile(`<meta property="og:title" content="([^"]+)"`)
	fwnAuthorRE   = regexp.MustCompile(`<a href="/author/[^"]*"[^>]*title="([^"]*)"`)
	fwnStatusRE   = regexp.MustCompile(`<span class="s1 s2">\s*<a[^>]*>([^<]+)</a>\s*</span>`)
	fwnGenreBlkRE = regexp.MustCompile(`title="Genre"></span>\s*<div class="right">([\s\S]*?)</div>`)
	fwnGenreTitRE = regexp.MustCompile(`<a href="/genre/[^"]*"[^>]*title="[^"]*">([^<]+)</a>`)
	fwnDescRE     = regexp.MustCompile(`<div class="inner">([\s\S]*?)</div>\s*</div>\s*<div class="showheight"`)
	fwnPRE        = regexp.MustCompile(`<p[^>]*>([\s\S]*?)</p>`)
	fwnIDDataRE   = regexp.MustCompile(`<ul[^>]+id="idData"[^>]*>([\s\S]*?)</ul>`)
	fwnChTitleRE  = regexp.MustCompile(`<span class="chapter">([^<]+)</span>`)
	fwnArticleRE  = regexp.MustCompile(`<div[^>]+id="article"[^>]*>([\s\S]*?)<!--bg-->`)
	fwnArticle2RE = regexp.MustCompile(`<div[^>]+id="article"[^>]*>`)
	fwnNavTagRE   = regexp.MustCompile(`<a[^>]*\bid="(prev_url|next_url)"[^>]*>`)
	fwnHrefRE     = regexp.MustCompile(`href="([^"]+)"`)
)

type novel struct {
	f        *fetcher
	cache    *lru
	proxy    func(string) string
	listDir  string // chapter lists kept between runs (a 3000-chapter list is ~15 paced requests)
	listLock sync.Map
}

type novelCard struct {
	ID            string   `json:"id"`
	Title         string   `json:"title"`
	Image         string   `json:"image"`
	Author        string   `json:"author"`
	LatestChapter string   `json:"latestChapter"`
	Genres        []string `json:"genres"`
}

type novelChapter struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	Chapter string `json:"chapter"`
}

func fwnPrefix(id string) string {
	if id == "" || strings.HasPrefix(id, fwnName+":") {
		return id
	}
	return fwnName + ":" + id
}

// fwnStrip turns "freewebnovel:novel/x" into "novel/x"; unknown prefixes are refused.
func fwnStrip(id string) (string, error) {
	p, raw, ok := strings.Cut(id, ":")
	if !ok || p != fwnName {
		return "", badInput(fmt.Sprintf("id %q has no known provider prefix (want %s:…)", id, fwnName))
	}
	if strings.Contains(raw, "..") || strings.HasPrefix(raw, "/") {
		return "", badInput(fmt.Sprintf("bad id %q", id))
	}
	return raw, nil
}

func (n *novel) image(src string) string {
	if src == "" {
		return ""
	}
	if !strings.HasPrefix(src, "http") {
		src = fwnBase + src
	}
	return n.proxy(src)
}

func (n *novel) get(ctx context.Context, u string, h map[string]string) (string, error) {
	return n.f.text(ctx, u, reqOpts{headers: h, paced: true})
}

func (n *novel) parseRows(html string) []novelCard {
	results := []novelCard{}
	seen := map[string]bool{}
	blocks := strings.Split(html, `<div class="li-row">`)
	for _, b := range blocks[1:] {
		slug := group(fwnSlugRE, b, 1)
		if slug == "" || seen[slug] {
			continue
		}
		seen[slug] = true
		title := cleanText(group(fwnTitRE, b, 1))
		if title == "" {
			title = slug
		}
		genres := []string{}
		for _, g := range fwnGenreRE.FindAllStringSubmatch(b, -1) {
			genres = append(genres, g[1])
		}
		results = append(results, novelCard{ID: fwnPrefix("novel/" + slug), Title: title,
			Image: n.image(group(fwnImgRE, b, 1)), LatestChapter: cleanText(group(fwnLastChapRE, b, 1)), Genres: genres})
	}
	return results
}

func (n *novel) hot(ctx context.Context) ([]novelCard, error) {
	return cached(n.cache, "novel:hot", 5*time.Minute, func() ([]novelCard, error) {
		html, err := n.get(ctx, fwnBase+"/sort/most-popular", nil)
		if err != nil {
			return nil, err
		}
		return n.parseRows(html), nil
	})
}

func (n *novel) latest(ctx context.Context, page int) (map[string]any, error) {
	return cached(n.cache, fmt.Sprint("novel:latest:", page), 2*time.Minute, func() (map[string]any, error) {
		u := fwnBase + "/sort/latest-novel"
		if page > 1 {
			u += fmt.Sprint("/", page)
		}
		html, err := n.get(ctx, u, nil)
		if err != nil {
			return nil, err
		}
		more := fwnNextRE.MatchString(html) || strings.Contains(html, fmt.Sprintf(`latest-novel/%d"`, page+1))
		return map[string]any{"results": n.parseRows(html), "hasMore": more, "nextPage": page + 1}, nil
	})
}

func (n *novel) search(ctx context.Context, q string) (map[string]any, error) {
	return cached(n.cache, "novel:search:"+q, 10*time.Minute, func() (map[string]any, error) {
		html, err := n.get(ctx, fwnBase+"/search?keyword="+url.QueryEscape(q), map[string]string{"Referer": fwnBase + "/"})
		if err != nil {
			return nil, err
		}
		// The site's search is single-page.
		return map[string]any{"results": n.parseRows(html), "hasMore": false, "nextPage": 1}, nil
	})
}

// parseAnchors reads the chapter anchors of the novel page's inline list.
// The href slug is the routable id; the title only labels it.
func parseFwnAnchors(novelID, html string) []novelChapter {
	out := []novelChapter{}
	for _, m := range fwnChAnchorRE.FindAllStringSubmatch(html, -1) {
		label := cleanText(m[2])
		num := group(fwnChNumRE, label, 1)
		if num == "" {
			num = label
		}
		out = append(out, novelChapter{ID: novelID + "/" + m[1], Title: label, Chapter: num})
	}
	return out
}

// parseFwnOptions reads chapterlist.php's <option> list ("CH.12: Title").
func parseFwnOptions(novelID, body string) []novelChapter {
	var env struct {
		HTML string `json:"html"`
	}
	if json.Unmarshal([]byte(body), &env) == nil && env.HTML != "" {
		body = env.HTML
	}
	out := []novelChapter{}
	for _, m := range fwnOptionRE.FindAllStringSubmatch(body, -1) {
		label := fwnCHPrefixRE.ReplaceAllString(cleanText(m[2]), "Chapter ")
		num := group(fwnSlugNumRE, m[1], 1)
		if num == "" {
			num = group(fwnChNumRE, label, 1)
		}
		if num == "" {
			num = label
		}
		out = append(out, novelChapter{ID: novelID + "/" + m[1], Title: label, Chapter: num})
	}
	return out
}

func dedupeSortChapters(chs []novelChapter) []novelChapter {
	seen := map[string]bool{}
	out := []novelChapter{}
	for _, c := range chs {
		if !seen[c.ID] {
			seen[c.ID] = true
			out = append(out, c)
		}
	}
	key := func(c novelChapter) float64 {
		if f, err := strconv.ParseFloat(group(fwnSortKeyRE, c.ID, 1), 64); err == nil {
			return f
		}
		return math.Inf(1)
	}
	sort.SliceStable(out, func(i, j int) bool { return key(out[i]) < key(out[j]) })
	return out
}

func (n *novel) listPath(novelID string) string {
	return filepath.Join(n.listDir, strings.ReplaceAll(novelID, "/", "_")+".json")
}

func (n *novel) loadList(novelID string) []novelChapter {
	var out []novelChapter
	if b, err := os.ReadFile(n.listPath(novelID)); err == nil {
		json.Unmarshal(b, &out)
	}
	return out
}

func (n *novel) saveList(novelID string, chs []novelChapter) {
	b, _ := json.Marshal(chs)
	if err := os.MkdirAll(n.listDir, 0o700); err == nil {
		writeFileAtomic(n.listPath(novelID), b, 0o600)
	}
}

// chapterList returns the whole list, oldest first, and whether the site cut it short.
// chapterlist.php first (one request); else the paged ajax listing, resuming from disk.
func (n *novel) chapterList(ctx context.Context, novelID, page string, inline []novelChapter) ([]novelChapter, bool, error) {
	l, _ := n.listLock.LoadOrStore(novelID, &sync.Mutex{})
	mu := l.(*sync.Mutex)
	mu.Lock()
	defer mu.Unlock()

	slug := novelID[strings.LastIndex(novelID, "/")+1:]
	if aid := fwnAidRE.FindStringSubmatch(page); aid != nil {
		id := aid[1] + aid[2] + aid[3]
		total := atoiDef(group(fwnTotalRE, page, 1), 0)
		form := url.Values{"aid": {id}, "acode": {slug}, "cid": {fmt.Sprint(rand.IntN(max(total, 1)))}}
		body, err := n.f.text(ctx, fwnBase+"/api/chapterlist.php", reqOpts{method: "POST", paced: true, body: form.Encode(),
			headers: map[string]string{"Content-Type": "application/x-www-form-urlencoded", "X-Requested-With": "XMLHttpRequest", "Referer": fwnBase + "/" + novelID}})
		if err == nil {
			if full := parseFwnOptions(novelID, body); len(full) > 0 && (total == 0 || float64(len(full)) >= float64(total)*0.9) {
				chs := dedupeSortChapters(append(full, inline...))
				n.saveList(novelID, chs)
				return chs, false, nil
			}
		}
	}

	known := n.loadList(novelID)
	first, meta, err := n.ajaxPage(ctx, novelID, 1)
	if err != nil {
		return dedupeSortChapters(append(known, inline...)), true, nil
	}
	pageSize, totalPage, total := max(meta.PageSize, 1), max(meta.TotalPage, 1), meta.TotalChapters
	chs := dedupeSortChapters(append(append(known, inline...), first...))
	if total > 0 && len(chs) >= total {
		if len(known) < len(chs) {
			n.saveList(novelID, chs)
		}
		return chs, false, nil
	}
	partial := false
	for p := max(2, len(chs)/pageSize+1); p <= min(totalPage, 200); p++ {
		more, _, err := n.ajaxPage(ctx, novelID, p)
		if err != nil {
			partial = true
			break
		}
		chs = append(chs, more...)
	}
	chs = dedupeSortChapters(chs)
	n.saveList(novelID, chs)
	return chs, partial, nil
}

type fwnPageMeta struct {
	Code          int    `json:"code"`
	HTML          string `json:"html"`
	PageSize      int    `json:"pageSize"`
	TotalPage     int    `json:"totalPage"`
	TotalChapters int    `json:"totalChapters"`
}

func (n *novel) ajaxPage(ctx context.Context, novelID string, page int) ([]novelChapter, fwnPageMeta, error) {
	var meta fwnPageMeta
	body, err := n.f.text(ctx, fmt.Sprintf("%s/%s?ajax=chapters&page=%d&pageSize=200", fwnBase, novelID, page),
		reqOpts{paced: true, headers: map[string]string{"X-Requested-With": "XMLHttpRequest"}})
	if err != nil {
		return nil, meta, err
	}
	if err := json.Unmarshal([]byte(body), &meta); err != nil || (meta.Code != 0 && meta.Code != 200) {
		return nil, meta, fmt.Errorf("unexpected chapter-list reply for page %d", page)
	}
	return parseFwnAnchors(novelID, meta.HTML), meta, nil
}

func (n *novel) info(ctx context.Context, prefixed string) (map[string]any, error) {
	id, err := fwnStrip(prefixed)
	if err != nil {
		return nil, err
	}
	key := "novel:info:" + id
	if v, ok := n.cache.get(key); ok {
		return v.(map[string]any), nil
	}
	page, err := n.get(ctx, fwnBase+"/"+id, nil)
	if err != nil {
		return nil, err
	}
	data := n.parseInfo(id, page)
	inline := parseFwnAnchors(id, group(fwnIDDataRE, page, 1))
	chs, partial, _ := n.chapterList(ctx, id, page, inline)
	for i := range chs {
		chs[i].ID = fwnPrefix(chs[i].ID)
	}
	data["chapters"], data["partial"] = chs, partial
	if !partial { // a list cut short is not kept, so the next open resumes it
		n.cache.put(key, data, 1, 30*time.Minute)
	}
	return data, nil
}

func (n *novel) parseInfo(id, page string) map[string]any {
	cover := group(fwnCoverRE, page, 1)
	if cover == "" {
		cover = group(fwnOgImageRE, page, 1)
	}
	genres := []string{}
	for _, g := range fwnGenreTitRE.FindAllStringSubmatch(group(fwnGenreBlkRE, page, 1), -1) {
		genres = append(genres, g[1])
	}
	var paras []string
	for _, p := range fwnPRE.FindAllStringSubmatch(group(fwnDescRE, page, 1), -1) {
		if t := cleanText(p[1]); t != "" {
			paras = append(paras, t)
		}
	}
	return map[string]any{
		"id": fwnPrefix(id), "title": cleanText(group(fwnOgTitleRE, page, 1)), "description": strings.Join(paras, "\n\n"),
		"status": cleanText(group(fwnStatusRE, page, 1)), "author": cleanText(group(fwnAuthorRE, page, 1)),
		"image": n.image(cover), "genres": genres,
	}
}

func (n *novel) chapter(ctx context.Context, prefixed string) (map[string]any, error) {
	id, err := fwnStrip(prefixed)
	if err != nil {
		return nil, err
	}
	return cached(n.cache, "novel:chapter:"+id, 24*time.Hour, func() (map[string]any, error) {
		page, err := n.get(ctx, fwnBase+"/"+id, nil)
		if err != nil {
			return nil, err
		}
		return parseFwnChapter(id, page), nil
	})
}

func parseFwnChapter(id, page string) map[string]any {
	title := group(fwnChTitleRE, page, 1)
	if title == "" {
		title = group(fwnOgTitleRE, page, 1)
	}
	content := group(fwnArticleRE, page, 1)
	if content == "" {
		if loc := fwnArticle2RE.FindStringIndex(page); loc != nil {
			content = page[loc[1]:min(len(page), loc[1]+100000)]
		}
	}
	paras := []string{}
	words := 0
	for _, p := range fwnPRE.FindAllStringSubmatch(content, -1) {
		if strings.Contains(p[1], "<script") || strings.Contains(p[1], "<div") { // inline ads
			continue
		}
		if t := cleanText(p[1]); t != "" {
			paras = append(paras, t)
			words += len(strings.Fields(t))
		}
	}
	nav := map[string]string{}
	for _, m := range fwnNavTagRE.FindAllStringSubmatch(page, -1) { // id and href come in either order
		if href := group(fwnHrefRE, m[0], 1); href != "" {
			if u, err := url.Parse(href); err == nil {
				if p := strings.Trim(u.Path, "/"); len(strings.Split(p, "/")) >= 3 { // novel/slug/chapter-N, not the novel page
					nav[m[1]] = fwnPrefix(p)
				}
			}
		}
	}
	return map[string]any{"id": fwnPrefix(id), "title": strings.TrimSpace(cleanText(title)), "paragraphs": paras,
		"wordCount": words, "prevId": nav["prev_url"], "nextId": nav["next_url"]}
}
