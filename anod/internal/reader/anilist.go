package reader

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// ── AniList: airing schedule, season, top airing, new-episode counts ─────
//
// AniList's public GraphQL API (no login). It allows 90 requests a minute
// (30 while degraded), so its own fetcher paces requests 2 s apart and a 429
// is retried at most three times with backoff; answers are cached 10 minutes.
// Idea from Ryoku's AnimeService.

const anilistAPI = "https://graphql.anilist.co"

var anilistFetch = newFetcher(2 * time.Second)

type airingItem struct {
	AniListID int    `json:"anilistId"`
	MalID     int    `json:"malId,omitempty"`
	Title     string `json:"title"`
	Cover     string `json:"cover"`
	Episode   int    `json:"episode,omitempty"`  // airing schedule: this episode…
	AiringAt  int64  `json:"airingAt,omitempty"` // …at this time (unix)
	Episodes  int    `json:"episodes,omitempty"` // season/top: planned total
	Score     int    `json:"score,omitempty"`
}

type alMedia struct {
	ID         int  `json:"id"`
	IDMal      *int `json:"idMal"`
	Episodes   *int `json:"episodes"`
	AvgScore   *int `json:"averageScore"`
	IsAdult    bool `json:"isAdult"`
	Title      struct{ Romaji, English *string }
	CoverImage struct {
		Large string `json:"large"`
	} `json:"coverImage"`
	NextAiringEpisode *struct {
		Episode int `json:"episode"`
	} `json:"nextAiringEpisode"`
	Status string `json:"status"`
}

func (m alMedia) item() airingItem {
	it := airingItem{AniListID: m.ID, Cover: m.CoverImage.Large}
	if m.IDMal != nil {
		it.MalID = *m.IDMal
	}
	if m.Title.English != nil && *m.Title.English != "" {
		it.Title = *m.Title.English
	} else if m.Title.Romaji != nil {
		it.Title = *m.Title.Romaji
	}
	if m.Episodes != nil {
		it.Episodes = *m.Episodes
	}
	if m.AvgScore != nil {
		it.Score = *m.AvgScore
	}
	return it
}

const alMediaFields = `id idMal episodes averageScore isAdult status title { romaji english } coverImage { large } nextAiringEpisode { episode }`

func anilist(ctx context.Context, query string, vars map[string]any, out any) error {
	body, _ := json.Marshal(map[string]any{"query": query, "variables": vars})
	b, _, err := anilistFetch.do(ctx, anilistAPI, reqOpts{method: "POST", body: string(body), paced: true,
		headers: map[string]string{"Content-Type": "application/json", "Accept": "application/json"}})
	if err != nil {
		return err
	}
	var env struct {
		Data   json.RawMessage `json:"data"`
		Errors []struct {
			Message string `json:"message"`
		} `json:"errors"`
	}
	if err := json.Unmarshal(b, &env); err != nil {
		return err
	}
	if len(env.Errors) > 0 {
		return fmt.Errorf("anilist: %s", env.Errors[0].Message)
	}
	return json.Unmarshal(env.Data, out)
}

// season is AniList's name for the season of t (winter = Jan–Mar …).
func season(t time.Time) (string, int) {
	return [...]string{"WINTER", "SPRING", "SUMMER", "FALL"}[(int(t.Month())-1)/3], t.Year()
}

// Airing lists "week" (episodes airing in the next 7 days), "season" (this
// season's shows by popularity) or "top" (airing shows by score).
func (s *Service) Airing(ctx context.Context, list string) ([]airingItem, error) {
	key := "anilist:" + list
	if list == "week" { // the window moves; a coarse key keeps the cache useful
		key += ":" + strconv.FormatInt(time.Now().Unix()/600, 10)
	}
	return cached(s.meta, key, 10*time.Minute, func() ([]airingItem, error) {
		switch list {
		case "week":
			now := time.Now().Unix()
			var r struct {
				Page struct {
					AiringSchedules []struct {
						AiringAt int64   `json:"airingAt"`
						Episode  int     `json:"episode"`
						Media    alMedia `json:"media"`
					} `json:"airingSchedules"`
				}
			}
			q := `query ($a: Int, $b: Int) { Page(perPage: 50) { airingSchedules(airingAt_greater: $a, airingAt_lesser: $b, sort: TIME) { airingAt episode media { ` + alMediaFields + ` } } } }`
			if err := anilist(ctx, q, map[string]any{"a": now, "b": now + 7*86400}, &r); err != nil {
				return nil, err
			}
			out := []airingItem{}
			for _, x := range r.Page.AiringSchedules {
				if x.Media.IsAdult {
					continue
				}
				it := x.Media.item()
				it.Episode, it.AiringAt = x.Episode, x.AiringAt
				out = append(out, it)
			}
			return out, nil
		case "season", "top":
			// GraphQL refuses declared but unused variables: only season has them.
			vars := map[string]any{}
			q := `query { Page(perPage: 40) { media(type: ANIME, isAdult: false, status: RELEASING, sort: SCORE_DESC) { ` + alMediaFields + ` } } }`
			if list == "season" {
				se, y := season(time.Now())
				vars["s"], vars["y"] = se, y
				q = `query ($s: MediaSeason, $y: Int) { Page(perPage: 40) { media(type: ANIME, isAdult: false, season: $s, seasonYear: $y, sort: POPULARITY_DESC) { ` + alMediaFields + ` } } }`
			}
			var r struct {
				Page struct{ Media []alMedia }
			}
			if err := anilist(ctx, q, vars, &r); err != nil {
				return nil, err
			}
			out := []airingItem{}
			for _, m := range r.Page.Media {
				out = append(out, m.item())
			}
			return out, nil
		}
		return nil, badInput("list must be week, season or top")
	})
}

// LatestAired maps AllAnime show ids to the newest aired episode number,
// through their MAL ids (one AniList request for all of them).
func (s *Service) LatestAired(ctx context.Context, ids []string) (map[string]int, error) {
	if len(ids) > 100 {
		ids = ids[:100]
	}
	s.mu.Lock()
	a := s.anime
	s.mu.Unlock()
	if a == nil {
		return nil, fmt.Errorf("the reader backend is not running")
	}
	byMal := map[int][]string{}
	mals := []int{}
	for _, id := range ids {
		m, err := a.meta(ctx, id) // cached a day
		if err != nil {
			continue
		}
		if n, err := strconv.Atoi(m.MalID); err == nil {
			if byMal[n] == nil {
				mals = append(mals, n)
			}
			byMal[n] = append(byMal[n], id)
		}
	}
	out := map[string]int{}
	if len(mals) == 0 {
		return out, nil
	}
	key := fmt.Sprint("anilist:latest:", mals)
	latest, err := cached(s.meta, key, 10*time.Minute, func() (map[int]int, error) { return latestByMal(ctx, mals) })
	if err != nil {
		return nil, err
	}
	for mal, n := range latest {
		for _, id := range byMal[mal] {
			out[id] = n
		}
	}
	return out, nil
}

// latestByMal maps MAL ids to their newest aired episode (airing: the next
// episode − 1; finished: the episode count).
func latestByMal(ctx context.Context, mals []int) (map[int]int, error) {
	q := `query ($ids: [Int]) { Page(perPage: 50) { media(idMal_in: $ids, type: ANIME) { ` + alMediaFields + ` } } }`
	var r struct {
		Page struct{ Media []alMedia }
	}
	if err := anilist(ctx, q, map[string]any{"ids": mals}, &r); err != nil {
		return nil, err
	}
	l := map[int]int{}
	for _, m := range r.Page.Media {
		if m.IDMal == nil {
			continue
		}
		switch {
		case m.NextAiringEpisode != nil:
			l[*m.IDMal] = m.NextAiringEpisode.Episode - 1
		case m.Status == "FINISHED" && m.Episodes != nil:
			l[*m.IDMal] = *m.Episodes
		}
	}
	return l, nil
}

func splitIDs(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
