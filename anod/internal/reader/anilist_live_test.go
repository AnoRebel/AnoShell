package reader

import (
	"context"
	"os"
	"testing"
	"time"
)

// Hits AniList for real: ANO_LIVE=1 go test -run AniListLive ./internal/reader/
func TestAniListLive(t *testing.T) {
	if os.Getenv("ANO_LIVE") == "" {
		t.Skip("set ANO_LIVE=1 to query AniList")
	}
	s := newService(t)
	s.init()
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	for _, list := range []string{"week", "season", "top"} {
		items, err := s.Airing(ctx, list)
		if err != nil {
			t.Fatalf("%s: %v", list, err)
		}
		if len(items) == 0 || items[0].Title == "" || items[0].Cover == "" {
			t.Fatalf("%s: empty or untitled: %+v", list, items)
		}
		t.Logf("%s: %d items, first %+v", list, len(items), items[0])
	}
	l, err := latestByMal(ctx, []int{21, 1}) // One Piece (airing), Cowboy Bebop (finished, 26)
	if err != nil || l[21] < 1000 || l[1] != 26 {
		t.Fatalf("latestByMal = %v, %v", l, err)
	}
	t.Logf("latest aired: %v", l)
	if _, err := s.Airing(ctx, "nope"); err == nil {
		t.Fatal("unknown list accepted")
	}
}
