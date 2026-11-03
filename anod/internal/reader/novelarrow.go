package reader

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Novels from NovelArrow, served today by novelping.com (novelarrow.com sits
// behind a browser-only Cloudflare challenge and redirects there). Ported from
// novelmangareader's providers/novelarrow.py (itself after LNReader's plugin):
// lists are scraped from /sort/… and /search, details from /book/<slug>, the
// chapter list and chapters from the JSON /api-web.
//
// IDs: "novelarrow:<slug>" and "novelarrow:<slug>/<chapter-id>".

var novelProviders = []map[string]string{{"name": fwnName, "label": "FreeWebNovel"}, {"name": narName, "label": "NovelArrow"}}

const (
	narName     = "novelarrow"
	narBase     = "https://novelping.com"
	narInterval = 500 * time.Millisecond
)

var (
	narLinkRE     = regexp.MustCompile(`class="novel-title"><a href="[^"]*/book/([^"/?#]+)"[^>]*>([\s\S]*?)</a>`)
	narImgRE      = regexp.MustCompile(`<img[^>]+src="([^"]+)"`)
	narAuthorRE   = regexp.MustCompile(`class="author">([\s\S]*?)</span>\s*</div>`)
	narChapRE     = regexp.MustCompile(`class="[^"]*chapter-title[^"]*">([\s\S]*?)</span>`)
	narNextRE     = regexp.MustCompile(`<li class="next([^"]*)"`)
	narDescRE     = regexp.MustCompile(`id="novel-description-content"[^>]*>([\s\S]*?)</div>`)
	narPRE        = regexp.MustCompile(`<p[^>]*>([\s\S]*?)</p>`)
	narH4RE       = regexp.MustCompile(`<h4[^>]*>[\s\S]*?</h4>`)
	narBrRE       = regexp.MustCompile(`<br\s*/?>|\n`)
	narTitleNumRE = regexp.MustCompile(`(?i)^(?:chapter|ch\.?)\s*(\d+(?:\.\d+)?)`)
	narSlugNumRE  = regexp.MustCompile(`^chapter-(\d+)`)
	narSlugRE     = regexp.MustCompile(`^[A-Za-z0-9_-][A-Za-z0-9._-]*$`) // no leading dot: never "." or ".."
)

type novelArrow struct {
	f     *fetcher
	cache *lru
	proxy func(string) string
}

func narPrefix(id string) string {
	if id == "" || strings.HasPrefix(id, narName+":") {
		return id
	}
	return narName + ":" + id
}

// narStrip turns "novelarrow:slug[/chapter]" into its slug and chapter id.
func narStrip(id string) (slug, chapter string, err error) {
	p, raw, ok := strings.Cut(id, ":")
	if !ok || p != narName {
		return "", "", badInput(fmt.Sprintf("id %q has no known provider prefix (want %s:…)", id, narName))
	}
	slug, chapter, _ = strings.Cut(raw, "/")
	if !narSlugRE.MatchString(slug) || (chapter != "" && !narSlugRE.MatchString(chapter)) || strings.Contains(raw, "..") {
		return "", "", badInput(fmt.Sprintf("bad id %q", id))
	}
	return slug, chapter, nil
}

func (n *novelArrow) image(src string) string {
	if src == "" {
		return ""
	}
	switch {
	case strings.HasPrefix(src, "//"):
		src = "https:" + src
	case !strings.HasPrefix(src, "http"):
		src = narBase + src
	}
	return n.proxy(src)
}

func narMeta(html, prop string) string {
	re := regexp.MustCompile(`<meta[^>]+(?:property|name)="` + regexp.QuoteMeta(prop) + `"[^>]*content="([^"]*)"`)
	return cleanText(group(re, html, 1))
}

func narStatus(s string) string {
	s = strings.ToLower(s)
	switch {
	case strings.Contains(s, "ongoing"):
		return "Ongoing"
	case strings.Contains(s, "complete"):
		return "Completed"
	}
	return ""
}

// Every list (popular, updates, search) uses the same <div class="row"> card.
func (n *novelArrow) parseRows(html string) []novelCard {
	results := []novelCard{}
	seen := map[string]bool{}
	for _, b := range strings.Split(html, `<div class="row">`)[1:] {
		m := narLinkRE.FindStringSubmatch(b)
		if m == nil || seen[m[1]] {
			continue
		}
		seen[m[1]] = true
		results = append(results, novelCard{ID: narPrefix(m[1]), Title: cleanText(m[2]),
			Image: n.image(group(narImgRE, b, 1)), Author: cleanText(group(narAuthorRE, b, 1)),
			LatestChapter: cleanText(group(narChapRE, b, 1)), Genres: []string{}})
	}
	return results
}

// The "»" item is on every page; on the last one it's disabled.
func narHasNext(html string) bool {
	m := narNextRE.FindStringSubmatch(html)
	return m != nil && !strings.Contains(m[1], "disabled")
}

func (n *novelArrow) page(ctx context.Context, path string, page int) (map[string]any, error) {
	u := narBase + path
	if page > 1 {
		sep := "?"
		if strings.Contains(path, "?") {
			sep = "&"
		}
		u += fmt.Sprintf("%spage=%d", sep, page)
	}
	html, err := n.f.text(ctx, u, reqOpts{paced: true})
	if err != nil {
		return nil, err
	}
	return map[string]any{"results": n.parseRows(html), "hasMore": narHasNext(html), "nextPage": page + 1}, nil
}

func (n *novelArrow) hot(ctx context.Context) ([]novelCard, error) {
	return cached(n.cache, "novelarrow:hot", 5*time.Minute, func() ([]novelCard, error) {
		v, err := n.page(ctx, "/sort/popular", 1)
		if err != nil {
			return nil, err
		}
		return v["results"].([]novelCard), nil
	})
}

func (n *novelArrow) latest(ctx context.Context, page int) (map[string]any, error) {
	return cached(n.cache, fmt.Sprint("novelarrow:latest:", page), 2*time.Minute, func() (map[string]any, error) {
		return n.page(ctx, "/sort/updates", page)
	})
}

// The site's search has no genre or status filter.
func (n *novelArrow) search(ctx context.Context, q string, page int) (map[string]any, error) {
	return cached(n.cache, fmt.Sprint("novelarrow:search:", page, ":", q), 10*time.Minute, func() (map[string]any, error) {
		return n.page(ctx, "/search?keyword="+url.QueryEscape(q), page)
	})
}

func (n *novelArrow) json(ctx context.Context, u string, h map[string]string, v any) error {
	hdr := map[string]string{"Accept": "application/json"}
	for k, x := range h {
		hdr[k] = x
	}
	body, err := n.f.text(ctx, u, reqOpts{headers: hdr, paced: true})
	if err != nil {
		return err
	}
	return json.Unmarshal([]byte(body), v)
}

func (n *novelArrow) info(ctx context.Context, prefixed string) (map[string]any, error) {
	slug, _, err := narStrip(prefixed)
	if err != nil {
		return nil, err
	}
	return cached(n.cache, "novelarrow:info:"+slug, 30*time.Minute, func() (map[string]any, error) {
		html, err := n.f.text(ctx, narBase+"/book/"+url.PathEscape(slug), reqOpts{paced: true})
		if err != nil {
			return nil, err
		}
		var list struct {
			Items []struct {
				ID   string `json:"chapter_id"`
				Name string `json:"chapter_name"`
			} `json:"items"`
		}
		if err := n.json(ctx, narBase+"/api-web/novels/"+url.PathEscape(slug)+"/chapters?sort=asc", nil, &list); err != nil {
			return nil, err
		}
		return n.parseInfo(slug, html, list.Items), nil
	})
}

func (n *novelArrow) parseInfo(slug, html string, items []struct {
	ID   string `json:"chapter_id"`
	Name string `json:"chapter_name"`
}) map[string]any {
	description := narMeta(html, "og:description")
	if d := narDescRE.FindStringSubmatch(html); d != nil {
		var paras []string
		for _, p := range narPRE.FindAllStringSubmatch(d[1], -1) {
			if t := cleanText(p[1]); t != "" {
				paras = append(paras, t)
			}
		}
		if description = strings.Join(paras, "\n\n"); description == "" {
			description = cleanText(d[1])
		}
	}
	genres := []string{}
	for _, g := range strings.Split(narMeta(html, "og:novel:genre"), ",") {
		if g = strings.TrimSpace(g); g != "" {
			r := []rune(strings.ToLower(g))
			genres = append(genres, strings.ToUpper(string(r[:1]))+string(r[1:]))
		}
	}
	// The API's list is already in reading order, while the reader orders
	// chapters by number: the titles' own numbers are kept when they run
	// strictly upwards, else (restarts, gaps, repeats) the list position.
	chs := []novelChapter{}
	nums := []string{}
	ordered := true
	prev := -1.0
	for _, c := range items {
		if c.ID == "" || !narSlugRE.MatchString(c.ID) {
			continue
		}
		title := cleanText(c.Name)
		num := group(narTitleNumRE, title, 1)
		if num == "" {
			num = group(narSlugNumRE, c.ID, 1)
		}
		f, err := strconv.ParseFloat(num, 64)
		if err != nil || f <= prev {
			ordered = false
		}
		prev = f
		if title == "" {
			title = c.ID
		}
		chs = append(chs, novelChapter{ID: narPrefix(slug + "/" + c.ID), Title: title})
		nums = append(nums, num)
	}
	for i := range chs {
		if ordered {
			chs[i].Chapter = nums[i]
		} else {
			chs[i].Chapter = strconv.Itoa(i + 1)
		}
	}
	title := narMeta(html, "og:novel:novel_name")
	if title == "" {
		title = strings.TrimSuffix(narMeta(html, "og:title"), " | NovelPing")
	}
	return map[string]any{
		"id": narPrefix(slug), "title": title, "description": description,
		"status": narStatus(narMeta(html, "og:novel:status")), "author": narMeta(html, "og:novel:author"),
		"image": n.image(narMeta(html, "og:image")), "genres": genres, "chapters": chs, "partial": false,
	}
}

func (n *novelArrow) chapter(ctx context.Context, prefixed string) (map[string]any, error) {
	slug, cid, err := narStrip(prefixed)
	if err != nil {
		return nil, err
	}
	if cid == "" {
		return nil, badInput("missing chapter in id " + prefixed)
	}
	return cached(n.cache, "novelarrow:chapter:"+slug+"/"+cid, 24*time.Hour, func() (map[string]any, error) {
		var d struct {
			Item struct {
				Info narChapterInfo `json:"chapterInfo"`
			} `json:"item"`
		}
		// Reads would otherwise count towards the site's account-less
		// reading progress; the plugin turns it off the same way.
		u := narBase + "/api-web/novels/" + url.PathEscape(slug) + "/chapters/" + url.PathEscape(cid)
		if err := n.json(ctx, u, map[string]string{"x-track-reading-progress": "false"}, &d); err != nil {
			return nil, err
		}
		return parseNarChapter(slug, cid, d.Item.Info), nil
	})
}

type narChapterInfo struct {
	Name    string `json:"chapter_name"`
	Content string `json:"chapter_content"`
	Prev    *struct {
		ID string `json:"chapter_id"`
	} `json:"prevChapter"`
	Next *struct {
		ID string `json:"chapter_id"`
	} `json:"nextChapter"`
}

func parseNarChapter(slug, cid string, info narChapterInfo) map[string]any {
	paras := []string{}
	for _, p := range narPRE.FindAllStringSubmatch(info.Content, -1) {
		if t := cleanText(p[1]); t != "" {
			paras = append(paras, t)
		}
	}
	if len(paras) == 0 && info.Content != "" { // no <p> markup: one paragraph per line
		for _, line := range narBrRE.Split(narH4RE.ReplaceAllString(info.Content, ""), -1) {
			if t := cleanText(line); t != "" {
				paras = append(paras, t)
			}
		}
	}
	if len(paras) == 0 {
		paras = []string{"This chapter is premium or unavailable on NovelArrow."}
	}
	words := 0
	for _, p := range paras {
		words += len(strings.Fields(p))
	}
	nav := func(c *struct {
		ID string `json:"chapter_id"`
	}) string {
		if c == nil || !narSlugRE.MatchString(c.ID) {
			return ""
		}
		return narPrefix(slug + "/" + c.ID)
	}
	return map[string]any{"id": narPrefix(slug + "/" + cid), "title": cleanText(info.Name), "paragraphs": paras,
		"wordCount": words, "prevId": nav(info.Prev), "nextId": nav(info.Next)}
}
