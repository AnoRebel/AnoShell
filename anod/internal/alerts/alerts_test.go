package alerts

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func fixture(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", name))
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func TestParseNWS(t *testing.T) {
	as, err := parseNWS(fixture(t, "nws.json"))
	if err != nil || len(as) != 2 {
		t.Fatalf("got %d alerts, %v", len(as), err)
	}
	a := as[0]
	if a.Source != "nws" || a.Event != "Wind Advisory" || a.Severity != "moderate" || !strings.HasPrefix(a.ID, "urn:oid:") ||
		a.Expires != "2026-11-09T18:00:00-09:00" || a.Headline == "" || a.Area == "" {
		t.Fatalf("%+v", a)
	}
}

func TestParseMetNo(t *testing.T) {
	as, err := parseMetNo(fixture(t, "metno.json"))
	if err != nil || len(as) != 2 {
		t.Fatalf("got %d alerts, %v", len(as), err)
	}
	a := as[0]
	if a.Source != "metno" || a.Event != "Gale Force" || a.Severity != "moderate" || a.ID != "2.49.0.1.578.0.261109220000.0852_1_0" ||
		a.Onset != "2026-11-10T22:00:00+00:00" || a.Expires != "2026-11-11T00:00:00+00:00" || a.Area != "D2" {
		t.Fatalf("%+v", a)
	}
}

func TestParseBrightSky(t *testing.T) {
	as, err := parseBrightSky(fixture(t, "brightsky.json"))
	if err != nil || len(as) != 1 {
		t.Fatalf("got %d alerts, %v", len(as), err)
	}
	a := as[0]
	if a.Source != "dwd" || a.Event != "frost" || a.Severity != "minor" || a.Headline != "Official WARNING of FROST" ||
		a.Area != "Berl. - Mitte" || a.Expires != "2026-11-10T08:00:00+00:00" {
		t.Fatalf("%+v", a)
	}
}

func TestParseMeteoAlarm(t *testing.T) {
	b := fixture(t, "meteoalarm.xml")
	// Both Wittmund areas carry one identifier: one alert.
	as, err := parseMeteoAlarm(b, []string{"Esens", "Landkreis Wittmund", "Niedersachsen"})
	if err != nil || len(as) != 1 {
		t.Fatalf("got %d alerts, %v", len(as), err)
	}
	if a := as[0]; a.Event != "fog" || a.Severity != "minor" || !strings.Contains(a.Headline, "Wittmund") || a.Expires == "" {
		t.Fatalf("%+v", a)
	}
	if as, _ := parseMeteoAlarm(b, []string{"Fulda", "Landkreis Fulda", "Hessen"}); len(as) != 0 {
		t.Fatalf("Fulda matched %+v", as)
	}
	if as, _ := parseMeteoAlarm(b, nil); len(as) != 0 {
		t.Fatalf("no names matched %+v", as)
	}
}

func TestParseNominatim(t *testing.T) {
	c, names, err := parseNominatim(fixture(t, "nominatim.json"))
	if err != nil || c != "de" || strings.Join(names, "|") != "Fulda|Landkreis Fulda|Hessen" {
		t.Fatalf("%q %q %v", c, names, err)
	}
}

func TestFeedFor(t *testing.T) {
	for country, want := range map[string]string{"us": "nws", "no": "metno", "de": "dwd", "fr": "meteoalarm", "gb": "meteoalarm"} {
		f, ok := FeedFor(Place{Lat: 1, Lon: 2, Country: country})
		if !ok || f.Name != want {
			t.Errorf("%s: %v %q", country, ok, f.Name)
		}
	}
	if _, ok := FeedFor(Place{Country: "tz"}); ok {
		t.Error("tz has no feed")
	}
}

func TestInQuiet(t *testing.T) {
	at := func(h, m int) time.Time { return time.Date(2026, 1, 1, h, m, 0, 0, time.Local) }
	cases := []struct {
		h, m     int
		from, to string
		want     bool
	}{
		{23, 0, "22:00", "07:00", true}, {3, 0, "22:00", "07:00", true}, {7, 0, "22:00", "07:00", false},
		{12, 0, "22:00", "07:00", false}, {13, 0, "12:00", "14:00", true}, {14, 0, "12:00", "14:00", false},
		{1, 0, "bad", "07:00", false}, {1, 0, "07:00", "07:00", false},
	}
	for _, c := range cases {
		if got := InQuiet(at(c.h, c.m), c.from, c.to); got != c.want {
			t.Errorf("%02d:%02d in %s–%s: %v", c.h, c.m, c.from, c.to, got)
		}
	}
}

// One alert is announced once, across polls and a restart.
func TestWatcherAnnouncesOnce(t *testing.T) {
	future := time.Now().Add(time.Hour).UTC().Format(time.RFC3339)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte(`{"alerts":[{"alert_id":"a1","status":"actual","severity":"severe","event_en":"storm","expires":"` + future + `"},
			{"alert_id":"old","status":"actual","expires":"2000-01-01T00:00:00Z"}],"location":{"name":"X"}}`))
	}))
	defer srv.Close()
	cache := filepath.Join(t.TempDir(), "alerts.json")
	var got []string
	mk := func() *Watcher {
		return &Watcher{CachePath: cache, Settings: func() Settings { return Settings{Enable: true} },
			Announce: func(a Alert, quiet bool) { got = append(got, a.ID) }}
	}
	feed := Feed{"dwd", srv.URL, parseBrightSky}
	w := mk()
	w.Client = srv.Client()
	w.SetPlace(52.5, 13.4)
	for range 2 {
		b, err := w.get(context.Background(), feed.URL)
		if err != nil {
			t.Fatal(err)
		}
		as, _ := feed.Parse(b)
		w.update(feed.Name, current(as, time.Now()), "")
	}
	if st := w.State(); len(st["alerts"].([]Alert)) != 1 {
		t.Fatalf("state %+v", st)
	}
	w2 := mk() // restarted: the cache remembers a1
	w2.update("dwd", []Alert{{ID: "a1"}, {ID: "a2"}}, "")
	if strings.Join(got, ",") != "a1,a2" {
		t.Fatalf("announced %v", got)
	}
}

func TestAreaMatches(t *testing.T) {
	cases := []struct {
		area  string
		names []string
		want  bool
	}{
		{"Hautes Alpes", []string{"Gap", "Hautes-Alpes", "Provence-Alpes-Côte d'Azur"}, true},
		{"Emilia e Romagna", []string{"Bologna", "Emilia-Romagna"}, true},
		{"East Midlands | Yorkshire & Humber", []string{"Leeds", "West Yorkshire", "Yorkshire and the Humber", "England"}, true},
		{"Kreis Fulda", []string{"Fulda", "Landkreis Fulda", "Hessen"}, true},
		{"Gard", []string{"Montpellier", "Hérault", "Occitanie"}, false},
		{"Alpes", []string{"Hautes-Alpes"}, true}, // whole word: accepted ceiling
		{"Lazio", nil, false},
	}
	for _, c := range cases {
		if got := areaMatches(c.area, c.names); got != c.want {
			t.Errorf("%q in %q: %v", c.area, c.names, got)
		}
	}
}
