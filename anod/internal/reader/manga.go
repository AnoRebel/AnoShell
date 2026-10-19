package reader

import (
	"context"
	"fmt"
	"net/url"
	"regexp"
	"strings"
	"time"
)

// Manga: weebcentral.com, scraped. Ported from novelmangareader's
// manga_server.py; the JSON shapes are the same so the Python backend stays
// a drop-in fallback.

const (
	wcBase      = "https://weebcentral.com"
	wcCoverSm   = "https://temp.compsci88.com/cover/small"
	wcCoverBase = "https://temp.compsci88.com/cover/fallback"
	wcPageLimit = 32
	// Links are root-relative now ("/series/…"); older markup was absolute.
	wcHref = `href="(?:https://weebcentral\.com)?`
)

var (
	wcArticleRE  = regexp.MustCompile(`(?s)<article([^>]*)>(.*?)</article>`)
	wcSeriesRE   = regexp.MustCompile(wcHref + `/series/([^"]+)"`)
	wcSeries2RE  = regexp.MustCompile(wcHref + `/series/([A-Z0-9]+)/([^"]+)"`)
	wcChapterRE  = regexp.MustCompile(wcHref + `/chapters/([A-Z0-9]+)"`)
	wcH2RE       = regexp.MustCompile(`<h2[^>]*>([^<]+)</h2>`)
	wcDivRE      = regexp.MustCompile(`<div>([^<]+)</div>`)
	wcSpanTagRE  = regexp.MustCompile(`<span>([^<,]+),?</span>`)
	wcDataTipRE  = regexp.MustCompile(`data-tip="([^"]+)"`)
	wcCoverImgRE = regexp.MustCompile(`<img src="(https://temp\.compsci88\.com/[^"]+)"`)
	wcChNumRE    = regexp.MustCompile(`(?:Chapter|Episode) ([0-9][^<]*)<`)
	wcChNumHotRE = regexp.MustCompile(`(?:Chapter|Episode) ([0-9][^<]*)</`)
	wcDatetimeRE = regexp.MustCompile(`datetime="([^"]+)"`)
	wcAltCoverRE = regexp.MustCompile(`alt="([^"]+) cover"`)
	wcTitleRE    = regexp.MustCompile(`<title>([^|<]+)`)
	wcStatusRE   = regexp.MustCompile(`(?s)Status: </strong>.*?<a[^>]+>([^<]+)</a>`)
	wcOgImageRE  = regexp.MustCompile(`og:image" content="([^"]+)"`)
	wcAuthorRE   = regexp.MustCompile(`(?s)(?:Author|Artist)(?:s|\(s\))?: </strong>(.*?)(?:</li>|</ul>)`)
	wcAnchorRE   = regexp.MustCompile(`<a[^>]+>([^<]+)</a>`)
	wcParaRE     = regexp.MustCompile(`<p[^>]*>([\s\S]{80,600}?)</p>`)
	wcChAnchorRE = regexp.MustCompile(`(?s)<a\s+` + wcHref + `/chapters/([^"]+)"[^>]*>(.*?)</a>`)
	wcSpanRE     = regexp.MustCompile(`(?s)<span[^>]*>(.*?)</span>`)
	wcChWordRE   = regexp.MustCompile(`(?i)(?:chapter|episode)\s*`)
	wcPageImgRE  = regexp.MustCompile(`(?i)<img\s[^>]*src="(https://[^"]+\.(?:jpg|jpeg|png|webp|gif|avif)[^"]*)"`)
	wcHasNextFmt = `hx-get="(?:https://weebcentral\.com)?/latest-updates/%d"`
)

type manga struct {
	f     *fetcher
	cache *lru
	proxy func(string) string // raw image URL → the reader's image proxy URL
}

type mangaCard struct {
	ID        string   `json:"id"`
	Title     string   `json:"title"`
	Image     string   `json:"image"`
	Status    string   `json:"status"`
	Year      string   `json:"year,omitempty"`
	Type      string   `json:"type"`
	Tags      []string `json:"tags,omitempty"`
	Chapter   string   `json:"chapter,omitempty"`
	UpdatedAt string   `json:"updatedAt,omitempty"`
}

func wcSeriesID(full string) string { return strings.SplitN(full, "/", 2)[0] }

func (m *manga) cover(sid string) string { return m.proxy(wcCoverSm + "/" + sid + ".webp") }

func (m *manga) get(ctx context.Context, u string, hx bool) (string, error) {
	h := map[string]string{}
	if hx {
		h = map[string]string{"HX-Request": "true", "HX-Target": "search-results", "X-Requested-With": "XMLHttpRequest"}
	}
	return m.f.text(ctx, u, reqOpts{headers: h})
}

func (m *manga) search(ctx context.Context, q, typ string, offset int, sort string) (map[string]any, error) {
	key := fmt.Sprintf("search:%s:%s:%d:%s", q, typ, offset, sort)
	return cached(m.cache, key, 10*time.Minute, func() (map[string]any, error) {
		v := url.Values{"text": {q}, "limit": {fmt.Sprint(wcPageLimit)}, "offset": {fmt.Sprint(offset)},
			"official": {"Any"}, "anime_only": {"any"}, "display_mode": {"Minimal Display"}, "sort": {sort}}
		if typ != "" {
			v.Set("included_type", typ)
		}
		html, err := m.get(ctx, wcBase+"/search/data?"+v.Encode(), true)
		if err != nil {
			return nil, err
		}
		results := m.parseSearch(html)
		return map[string]any{"results": results, "hasMore": len(results) >= wcPageLimit, "nextOffset": offset + len(results)}, nil
	})
}

func (m *manga) parseSearch(html string) []mangaCard {
	results := []mangaCard{}
	for _, a := range wcArticleRE.FindAllStringSubmatch(html, -1) {
		body := a[2]
		sid, title := group(wcSeriesRE, body, 1), group(wcH2RE, body, 1)
		if sid == "" || title == "" {
			continue
		}
		var divs []string
		for _, d := range wcDivRE.FindAllStringSubmatch(body, -1) {
			divs = append(divs, strings.TrimSpace(d[1]))
		}
		at := func(i int) string {
			if i < len(divs) {
				return divs[i]
			}
			return ""
		}
		var tags []string
		for _, t := range wcSpanTagRE.FindAllStringSubmatch(body, -1) {
			if s := strings.TrimSpace(t[1]); s != "" {
				tags = append(tags, s)
			}
		}
		results = append(results, mangaCard{ID: sid, Title: cleanText(title), Image: m.cover(wcSeriesID(sid)),
			Type: at(0), Year: at(1), Status: at(2), Tags: tags})
	}
	return results
}

func (m *manga) hot(ctx context.Context) ([]mangaCard, error) {
	return cached(m.cache, "hot", 5*time.Minute, func() ([]mangaCard, error) {
		html, err := m.get(ctx, wcBase+"/hot-updates", false)
		if err != nil {
			return nil, err
		}
		return m.parseHot(html), nil
	})
}

func (m *manga) parseHot(html string) []mangaCard {
	results := []mangaCard{}
	seen := map[string]bool{}
	for _, a := range wcArticleRE.FindAllStringSubmatch(html, -1) {
		body := a[2]
		s := wcSeries2RE.FindStringSubmatch(body)
		title := group(wcAltCoverRE, body, 1)
		if s == nil || !wcChapterRE.MatchString(body) || title == "" || seen[s[1]] {
			continue
		}
		seen[s[1]] = true
		img := m.cover(s[1])
		if c := group(wcCoverImgRE, body, 1); c != "" {
			img = m.proxy(c)
		}
		results = append(results, mangaCard{ID: s[1] + "/" + s[2], Title: cleanText(title), Image: img,
			Chapter:   strings.TrimSpace(group(wcChNumHotRE, body, 1)),
			UpdatedAt: group(wcDatetimeRE, body, 1)})
	}
	return results
}

func (m *manga) latest(ctx context.Context, page int) (map[string]any, error) {
	return cached(m.cache, fmt.Sprint("latest:", page), 2*time.Minute, func() (map[string]any, error) {
		html, err := m.get(ctx, fmt.Sprintf("%s/latest-updates/%d", wcBase, page), false)
		if err != nil {
			return nil, err
		}
		return m.parseLatest(html, page), nil
	})
}

func (m *manga) parseLatest(html string, page int) map[string]any {
	results := []mangaCard{}
	for _, a := range wcArticleRE.FindAllStringSubmatch(html, -1) {
		attrs, body := a[1], a[2]
		title := group(wcDataTipRE, attrs, 1)
		s := wcSeries2RE.FindStringSubmatch(body)
		if s == nil || title == "" {
			continue
		}
		img := m.cover(s[1])
		if c := group(wcCoverImgRE, body, 1); c != "" {
			img = m.proxy(c)
		}
		results = append(results, mangaCard{ID: s[1] + "/" + s[2], Title: cleanText(title), Image: img,
			Chapter: strings.TrimSpace(group(wcChNumRE, body, 1)), UpdatedAt: group(wcDatetimeRE, body, 1)})
	}
	hasMore := regexp.MustCompile(fmt.Sprintf(wcHasNextFmt, page+1)).MatchString(html)
	return map[string]any{"results": results, "hasMore": hasMore, "nextPage": page + 1}
}

type mangaChapter struct {
	ID        string `json:"id"`
	Title     string `json:"title"`
	Chapter   string `json:"chapter"`
	PublishAt string `json:"publishAt"`
}

func (m *manga) info(ctx context.Context, full string) (map[string]any, error) {
	return cached(m.cache, "info:"+full, 30*time.Minute, func() (map[string]any, error) {
		sid := wcSeriesID(full)
		type res struct {
			html string
			err  error
		}
		chc := make(chan res, 1)
		go func() {
			h, err := m.get(ctx, wcBase+"/series/"+sid+"/full-chapter-list", false)
			chc <- res{h, err}
		}()
		detail, err := m.get(ctx, wcBase+"/series/"+full, false)
		ch := <-chc
		if err != nil {
			return nil, err
		}
		if ch.err != nil {
			return nil, ch.err
		}
		return m.parseInfo(full, detail, ch.html), nil
	})
}

func (m *manga) parseInfo(full, detail, chHTML string) map[string]any {
	sid := wcSeriesID(full)
	authors := []string{}
	seen := map[string]bool{}
	for _, blk := range wcAuthorRE.FindAllStringSubmatch(detail, -1) {
		for _, n := range wcAnchorRE.FindAllStringSubmatch(blk[1], -1) {
			if s := strings.TrimSpace(n[1]); s != "" && !seen[s] {
				seen[s] = true
				authors = append(authors, s)
			}
		}
	}
	desc := ""
	for _, p := range wcParaRE.FindAllStringSubmatch(detail, -1) {
		c := cleanText(p[1])
		if c != "" && !strings.Contains(c, "{") && !strings.Contains(c, "function") && !strings.Contains(c, "Login") {
			desc = c
			break
		}
	}
	chapters := []mangaChapter{}
	for _, a := range wcChAnchorRE.FindAllStringSubmatch(chHTML, -1) {
		label := ""
		for _, sp := range wcSpanRE.FindAllStringSubmatch(a[2], -1) {
			if t := cleanText(sp[1]); len(t) > 1 && !strings.Contains(sp[1], "{") {
				label = t
				break
			}
		}
		chapters = append(chapters, mangaChapter{ID: a[1], Title: label,
			Chapter: strings.TrimSpace(wcChWordRE.ReplaceAllString(label, "")), PublishAt: group(wcDatetimeRE, a[2], 1)})
	}
	for i, j := 0, len(chapters)-1; i < j; i, j = i+1, j-1 { // oldest first
		chapters[i], chapters[j] = chapters[j], chapters[i]
	}
	cover := group(wcOgImageRE, detail, 1)
	if cover == "" {
		cover = wcCoverBase + "/" + sid + ".jpg"
	}
	return map[string]any{
		"id": full, "title": strings.TrimSpace(cleanText(group(wcTitleRE, detail, 1))), "description": desc,
		"status": strings.TrimSpace(group(wcStatusRE, detail, 1)), "image": m.proxy(cover),
		"authors": authors, "chapters": chapters,
	}
}

type mangaPage struct {
	Page int    `json:"page"`
	Img  string `json:"img"`
}

func (m *manga) pages(ctx context.Context, chapterID string) ([]mangaPage, error) {
	return cached(m.cache, "pages:"+chapterID, time.Hour, func() ([]mangaPage, error) {
		html, err := m.get(ctx, wcBase+"/chapters/"+url.PathEscape(chapterID)+"/images?is_prev=False&current_page=1&reading_style=long_strip", false)
		if err != nil {
			return nil, err
		}
		return m.parsePages(html), nil
	})
}

func (m *manga) parsePages(html string) []mangaPage {
	out := []mangaPage{}
	for _, s := range wcPageImgRE.FindAllStringSubmatch(html, -1) {
		if strings.Contains(s[1], "weebcentral.com") || strings.Contains(strings.ToLower(s[1]), "logo") {
			continue
		}
		out = append(out, mangaPage{Page: len(out) + 1, Img: m.proxy(s[1])})
	}
	return out
}
