package reader

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"net/url"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// Anime: browse/search/episodes from allanime's GraphQL API; streams resolved
// the way ani-cli 5.1 does (the ZokoAnime embed keyed by MAL id, else the
// hianime.at lookup). Ported from novelmangareader's anime_server.py with the
// same JSON shapes.

const (
	aaAPI         = "https://api.allanime.day/api"
	aaReferer     = "https://allmanga.to"
	aaAgent       = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/121.0"
	hiBase        = "https://hianime.at"
	zokoBase      = "https://zokoanime.video"
	hiAgent       = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
	aaLatestHash  = "a24c500a1b765c68ae1d8dd85174931f661c71369c89b92b88b75a725afc471c"
	aaPopularHash = "60f50b84bb545fa25ee7f7c8c0adbf8f5cea40f7b1ef8501cbbff70e38589489"

	aaSearchGQL = "query( $search: SearchInput $limit: Int $page: Int " +
		"$translationType: VaildTranslationTypeEnumType " +
		"$countryOrigin: VaildCountryOriginEnumType ) { " +
		"shows( search: $search limit: $limit page: $page " +
		"translationType: $translationType countryOrigin: $countryOrigin ) " +
		"{ edges { _id name englishName nativeName thumbnail score " +
		"availableEpisodes episodeCount __typename } }}"
	aaEpisodesGQL = "query ($showId: String!) { show( _id: $showId ) { _id availableEpisodesDetail }}"
	aaMetaGQL     = "query ($showId: String!) { show( _id: $showId ) { _id name englishName malId }}"
)

// The embed ships its config as base64(json XOR "otaku-embed-v1").
var zokoKey = []byte("otaku-embed-v1")

var (
	zokoBlobRE  = regexp.MustCompile(`window\.__P="([^"]*)"`)
	m3u8InfRE   = regexp.MustCompile(`#EXT-X-STREAM-INF[^\n]*RESOLUTION=\d+x(\d+)[^\n]*\n([^\n]+)`)
	hiCardRE    = regexp.MustCompile(`<h3 class="film-name">\s*<a href="[^"]*/([^"/]*)"\s*title="([^"]*)"[^>]*?data-jname="([^"]*)"`)
	hiEpRE      = regexp.MustCompile(`data-number="([^"]*)"\s*data-id="(\d+)"`)
	normTitleRE = regexp.MustCompile(`[^a-z0-9]`)
	qualityRE   = regexp.MustCompile(`^(\d+)`)
)

type anime struct {
	f     *fetcher
	cache *lru
}

func (a *anime) gql(ctx context.Context, vars map[string]any, query string, out any) error {
	body, _ := json.Marshal(map[string]any{"variables": vars, "query": query})
	b, _, err := a.f.do(ctx, aaAPI, reqOpts{method: "POST", body: string(body),
		headers: map[string]string{"User-Agent": aaAgent, "Referer": aaReferer, "Content-Type": "application/json"}})
	if err != nil {
		return err
	}
	return json.Unmarshal(b, out)
}

// persisted runs a hash-only (persisted) query, which still goes over GET.
func (a *anime) persisted(ctx context.Context, vars map[string]any, hash string, out any) error {
	v, _ := json.Marshal(vars)
	ext, _ := json.Marshal(map[string]any{"persistedQuery": map[string]any{"version": 1, "sha256Hash": hash}})
	q := url.Values{"variables": {string(v)}, "extensions": {string(ext)}}
	b, _, err := a.f.do(ctx, aaAPI+"?"+q.Encode(), reqOpts{headers: map[string]string{"User-Agent": aaAgent, "Referer": aaReferer}})
	if err != nil {
		return err
	}
	return json.Unmarshal(b, out)
}

type aaEps struct {
	Sub any `json:"sub"`
	Dub any `json:"dub"`
	Raw any `json:"raw"`
}

func epsMap(e aaEps) map[string]any {
	z := func(v any) any {
		if v == nil {
			return 0
		}
		return v
	}
	return map[string]any{"sub": z(e.Sub), "dub": z(e.Dub), "raw": z(e.Raw)}
}

func (a *anime) search(ctx context.Context, q, mode string) (map[string]any, error) {
	return cached(a.cache, "anime:search:"+mode+":"+q, 10*time.Minute, func() (map[string]any, error) {
		var r struct {
			Data struct {
				Shows struct {
					Edges []struct {
						ID           string `json:"_id"`
						Name         string `json:"name"`
						EnglishName  any    `json:"englishName"`
						NativeName   any    `json:"nativeName"`
						Thumbnail    string `json:"thumbnail"`
						Score        any    `json:"score"`
						EpisodeCount any    `json:"episodeCount"`
						Available    aaEps  `json:"availableEpisodes"`
					} `json:"edges"`
				} `json:"shows"`
			} `json:"data"`
		}
		vars := map[string]any{"search": map[string]any{"allowAdult": false, "allowUnknown": false, "query": q},
			"limit": 40, "page": 1, "translationType": mode, "countryOrigin": "ALL"}
		if err := a.gql(ctx, vars, aaSearchGQL, &r); err != nil {
			return nil, err
		}
		results := []map[string]any{}
		seen := map[string]bool{}
		for _, e := range r.Data.Shows.Edges {
			if e.ID == "" || seen[e.ID] {
				continue
			}
			seen[e.ID] = true
			results = append(results, map[string]any{"id": e.ID, "name": e.Name, "english_name": e.EnglishName,
				"native_name": e.NativeName, "thumbnail": e.Thumbnail, "score": e.Score,
				"episode_count": e.EpisodeCount, "available_episodes": epsMap(e.Available)})
		}
		return map[string]any{"query": q, "mode": mode, "count": len(results), "results": results}, nil
	})
}

func (a *anime) episodes(ctx context.Context, id, mode string) (map[string]any, error) {
	return cached(a.cache, "anime:eps:"+mode+":"+id, 10*time.Minute, func() (map[string]any, error) {
		var r struct {
			Data struct {
				Show struct {
					Detail map[string][]string `json:"availableEpisodesDetail"`
				} `json:"show"`
			} `json:"data"`
		}
		if err := a.gql(ctx, map[string]any{"showId": id}, aaEpisodesGQL, &r); err != nil {
			return nil, err
		}
		eps := append([]string{}, r.Data.Show.Detail[mode]...)
		sortNumeric(eps)
		return map[string]any{"id": id, "mode": mode, "count": len(eps), "episodes": eps}, nil
	})
}

// sortNumeric orders episode strings ("1", "12.5", …) numerically, else as text.
func sortNumeric(s []string) {
	sort.SliceStable(s, func(i, j int) bool {
		a, ea := strconv.ParseFloat(s[i], 64)
		b, eb := strconv.ParseFloat(s[j], 64)
		if ea == nil && eb == nil {
			return a < b
		}
		return s[i] < s[j]
	})
}

func (a *anime) popular(ctx context.Context, size, page, dateRange int) (map[string]any, error) {
	return cached(a.cache, fmt.Sprintf("anime:popular:%d:%d:%d", size, page, dateRange), 10*time.Minute, func() (map[string]any, error) {
		var r struct {
			Data struct {
				Popular struct {
					Total int `json:"total"`
					Recs  []struct {
						Card   map[string]any `json:"anyCard"`
						Status map[string]any `json:"pageStatus"`
					} `json:"recommendations"`
				} `json:"queryPopular"`
			} `json:"data"`
		}
		vars := map[string]any{"type": "anime", "size": size, "dateRange": dateRange, "page": page, "allowAdult": false, "allowUnknown": false}
		if err := a.persisted(ctx, vars, aaPopularHash, &r); err != nil {
			return nil, err
		}
		shows := []map[string]any{}
		for _, rec := range r.Data.Popular.Recs {
			c := rec.Card
			if c == nil {
				continue
			}
			shows = append(shows, map[string]any{"id": c["_id"], "name": c["name"], "english_name": c["englishName"],
				"native_name": c["nativeName"], "thumbnail": c["thumbnail"], "score": c["score"],
				"available_episodes": availMap(c["availableEpisodes"]),
				"views":              map[string]any{"total": rec.Status["views"], "range": rec.Status["rangeViews"]}})
		}
		return map[string]any{"page": page, "size": size, "date_range": dateRange, "total": r.Data.Popular.Total,
			"count": len(shows), "shows": shows}, nil
	})
}

func availMap(v any) map[string]any {
	m, _ := v.(map[string]any)
	get := func(k string) any {
		if x, ok := m[k]; ok && x != nil {
			return x
		}
		return 0
	}
	return map[string]any{"sub": get("sub"), "dub": get("dub"), "raw": get("raw")}
}

func (a *anime) latest(ctx context.Context, limit, page int, mode, country, q string) (map[string]any, error) {
	key := fmt.Sprintf("anime:latest:%d:%d:%s:%s:%s", limit, page, mode, country, q)
	return cached(a.cache, key, 2*time.Minute, func() (map[string]any, error) {
		var r struct {
			Data struct {
				Shows struct {
					PageInfo struct {
						Total int `json:"total"`
					} `json:"pageInfo"`
					Edges []map[string]any `json:"edges"`
				} `json:"shows"`
			} `json:"data"`
		}
		search := map[string]any{}
		if q != "" {
			search["query"] = q
		}
		vars := map[string]any{"search": search, "limit": limit, "page": page, "translationType": mode, "countryOrigin": country}
		if err := a.persisted(ctx, vars, aaLatestHash, &r); err != nil {
			return nil, err
		}
		shows := []map[string]any{}
		for _, e := range r.Data.Shows.Edges {
			last, _ := e["lastEpisodeInfo"].(map[string]any)
			epStr := func(m string) any {
				if i, ok := last[m].(map[string]any); ok {
					return i["episodeString"]
				}
				return nil
			}
			shows = append(shows, map[string]any{"id": e["_id"], "name": e["name"], "english_name": e["englishName"],
				"native_name": e["nativeName"], "type": e["type"], "thumbnail": e["thumbnail"], "score": e["score"],
				"episode_count": e["episodeCount"], "available_episodes": availMap(e["availableEpisodes"]),
				"last_episode": map[string]any{"sub": epStr("sub"), "dub": epStr("dub")}, "season": e["season"]})
		}
		return map[string]any{"page": page, "limit": limit, "total": r.Data.Shows.PageInfo.Total, "count": len(shows), "shows": shows}, nil
	})
}

type showMeta struct{ Name, EnglishName, MalID string }

func (a *anime) meta(ctx context.Context, id string) (showMeta, error) {
	return cached(a.cache, "anime:meta:"+id, 24*time.Hour, func() (showMeta, error) {
		var r struct {
			Data struct {
				Show struct {
					Name        string `json:"name"`
					EnglishName string `json:"englishName"`
					MalID       any    `json:"malId"`
				} `json:"show"`
			} `json:"data"`
		}
		if err := a.gql(ctx, map[string]any{"showId": id}, aaMetaGQL, &r); err != nil {
			return showMeta{}, err
		}
		s := r.Data.Show
		mal := ""
		if s.MalID != nil {
			mal = fmt.Sprint(s.MalID)
		}
		return showMeta{s.Name, s.EnglishName, mal}, nil
	})
}

type streamLink struct {
	Quality  string `json:"quality"`
	URL      string `json:"url"`
	Type     string `json:"type"`
	Referer  string `json:"referer"`
	Subtitle string `json:"subtitle,omitempty"`
	Provider string `json:"provider"`
}

func zokoConfig(page string) (map[string]any, error) {
	blob := group(zokoBlobRE, page, 1)
	if blob == "" {
		return nil, nil // the embed answers 200 without a blob for missing episodes
	}
	raw, err := base64.StdEncoding.DecodeString(blob)
	if err != nil {
		return nil, err
	}
	for i := range raw {
		raw[i] ^= zokoKey[i%len(zokoKey)]
	}
	var cfg map[string]any
	return cfg, json.Unmarshal(raw, &cfg)
}

// zokoLinks resolves an embed into per-quality HLS links (nil when unavailable).
func (a *anime) zokoLinks(ctx context.Context, embed string) ([]streamLink, error) {
	u, err := url.Parse(embed)
	if err != nil {
		return nil, err
	}
	referer := u.Scheme + "://" + u.Host + "/"
	page, err := a.f.text(ctx, embed, reqOpts{headers: map[string]string{"User-Agent": hiAgent}})
	if err != nil {
		return nil, err
	}
	cfg, err := zokoConfig(page)
	if err != nil || cfg == nil {
		return nil, err
	}
	master, _ := cfg["src"].(string)
	if !strings.Contains(master, ".m3u8") {
		return nil, nil
	}
	sub := ""
	if subs, ok := cfg["subtitles"].([]any); ok {
		for _, s := range subs {
			if m, ok := s.(map[string]any); ok && m["default"] == true {
				sub, _ = m["src"].(string)
				break
			}
		}
	}
	var links []streamLink
	if m3u8, err := a.f.text(ctx, master, reqOpts{headers: map[string]string{"User-Agent": hiAgent, "Referer": referer}}); err == nil {
		base := master[:strings.LastIndex(master, "/")+1]
		for _, m := range m3u8InfRE.FindAllStringSubmatch(m3u8, -1) {
			p := strings.TrimSpace(m[2])
			if !strings.HasPrefix(p, "http") {
				p = base + p
			}
			links = append(links, streamLink{Quality: m[1] + "p", URL: p, Type: "m3u8", Referer: referer, Subtitle: sub, Provider: "ZokoAnime"})
		}
	}
	if len(links) == 0 {
		links = []streamLink{{Quality: "best", URL: master, Type: "m3u8", Referer: referer, Subtitle: sub, Provider: "ZokoAnime"}}
	}
	return links, nil
}

func normTitle(s string) string { return normTitleRE.ReplaceAllString(strings.ToLower(s), "") }

// hianimeEmbed is ani-cli's lookup: search → episode list → ZokoAnime server hash.
func (a *anime) hianimeEmbed(ctx context.Context, m showMeta, ep, mode string) (string, error) {
	h := map[string]string{"User-Agent": hiAgent}
	wanted := map[string]bool{}
	var names []string
	for _, n := range []string{m.Name, m.EnglishName} {
		if n != "" {
			names = append(names, n)
			wanted[normTitle(n)] = true
		}
	}
	var cards [][]string
	for _, q := range names {
		page, err := a.f.text(ctx, hiBase+"/search?keyword="+url.QueryEscape(q), reqOpts{headers: h})
		if err != nil {
			return "", err
		}
		page, _, _ = strings.Cut(page, `id="main-sidebar"`) // the top-10 sidebar repeats the result markup
		if cards = hiCardRE.FindAllStringSubmatch(page, -1); len(cards) > 0 {
			break
		}
	}
	if len(cards) == 0 {
		return "", nil
	}
	slug := cards[0][1]
	for _, c := range cards {
		if wanted[normTitle(html.UnescapeString(c[2]))] || wanted[normTitle(html.UnescapeString(c[3]))] {
			slug = c[1]
			break
		}
	}
	var list struct {
		HTML string `json:"html"`
	}
	b, _, err := a.f.do(ctx, hiBase+"/api/theme/episode/list/"+url.PathEscape(slug[strings.LastIndex(slug, "-")+1:]), reqOpts{headers: h})
	if err != nil || json.Unmarshal(b, &list) != nil {
		return "", err
	}
	epID := ""
	for _, e := range hiEpRE.FindAllStringSubmatch(list.HTML, -1) {
		if e[1] == ep {
			epID = e[2]
			break
		}
	}
	if epID == "" {
		return "", nil
	}
	var servers struct {
		HTML string `json:"html"`
	}
	b, _, err = a.f.do(ctx, hiBase+"/api/theme/episode/servers?episodeId="+url.QueryEscape(epID), reqOpts{headers: h})
	if err != nil || json.Unmarshal(b, &servers) != nil {
		return "", err
	}
	hashRE := regexp.MustCompile(`data-type="` + regexp.QuoteMeta(mode) + `"\s*data-server-name="ZokoAnime"\s*data-hash="([^"]*)"`)
	hash := group(hashRE, servers.HTML, 1)
	if hash == "" {
		return "", nil
	}
	dec, err := base64.StdEncoding.DecodeString(hash)
	return string(dec), err
}

var errNoStream = errors.New("no stream")

func (a *anime) links(ctx context.Context, id, ep, mode, quality string) (map[string]any, error) {
	m, err := a.meta(ctx, id)
	if err != nil {
		return nil, err
	}
	var links []streamLink
	if m.MalID != "" {
		links, _ = a.zokoLinks(ctx, fmt.Sprintf("%s/stream/mal/%s/%s/%s", zokoBase, url.PathEscape(m.MalID), url.PathEscape(ep), url.PathEscape(mode)))
	}
	if len(links) == 0 {
		if embed, _ := a.hianimeEmbed(ctx, m, ep, mode); embed != "" {
			links, _ = a.zokoLinks(ctx, embed)
		}
	}
	if len(links) == 0 {
		return nil, fmt.Errorf("%w: no %s stream found for episode %s", errNoStream, mode, ep)
	}
	q := func(l streamLink) int { return atoiDef(group(qualityRE, l.Quality, 1), 0) }
	sort.SliceStable(links, func(i, j int) bool { return q(links[i]) > q(links[j]) })
	sel := links[0]
	switch quality {
	case "best", "":
	case "worst":
		for i := len(links) - 1; i >= 0; i-- {
			if q(links[i]) > 0 {
				sel = links[i]
				break
			}
		}
	default:
		for _, l := range links {
			if strings.Contains(l.Quality, quality) {
				sel = l
				break
			}
		}
	}
	return map[string]any{"show_id": id, "episode": ep, "mode": mode, "providers": map[string]any{"ZokoAnime": links},
		"all_links": links, "selected": sel, "requested_quality": quality}, nil
}
