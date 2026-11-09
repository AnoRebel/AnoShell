// Package alerts fetches official weather warnings for where you are and
// announces new ones as desktop notifications.
//
// The feed is picked by country (looked up once per place with a Nominatim
// reverse geocode): NWS for the US, MET Norway for Norway, DWD through
// Bright Sky for Germany, MeteoAlarm for the rest of Europe. All are free
// and keyless. Elsewhere there is no feed and nothing is fetched.
package alerts

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"strings"
)

// UserAgent identifies the app (MET Norway and Nominatim require one; no
// personal details).
const UserAgent = "AnoShell/1.0 github.com/AnoRebel/AnoShell"

// Alert is one warning, the same shape whatever the feed.
type Alert struct {
	ID          string `json:"id"`
	Source      string `json:"source"` // nws | metno | dwd | meteoalarm
	Event       string `json:"event"`
	Headline    string `json:"headline"`
	Description string `json:"description,omitempty"`
	Instruction string `json:"instruction,omitempty"`
	Severity    string `json:"severity"` // minor | moderate | severe | extreme | unknown
	Area        string `json:"area,omitempty"`
	Onset       string `json:"onset,omitempty"`   // RFC 3339
	Expires     string `json:"expires,omitempty"` // RFC 3339
}

func severity(s string) string {
	switch s = strings.ToLower(strings.TrimSpace(s)); s {
	case "minor", "moderate", "severe", "extreme":
		return s
	}
	return "unknown"
}

// actual drops tests, exercises and cancellations.
func actual(status, msgType string) bool {
	return (status == "" || strings.EqualFold(status, "actual")) && !strings.EqualFold(msgType, "cancel")
}

// Place is where alerts are fetched for.
type Place struct {
	Lat     float64  `json:"lat"`
	Lon     float64  `json:"lon"`
	Country string   `json:"country"` // ISO 3166-1 alpha-2, lower case
	Names   []string `json:"names"`   // town, county, state…: matched against MeteoAlarm's area names
}

// parseNominatim reads a jsonv2 reverse geocode into the country and the
// names of the areas around the point (local language: what MeteoAlarm uses).
func parseNominatim(b []byte) (country string, names []string, err error) {
	var r struct {
		Address map[string]string `json:"address"`
		Error   string            `json:"error"`
	}
	if err := json.Unmarshal(b, &r); err != nil {
		return "", nil, err
	}
	if r.Error != "" {
		return "", nil, fmt.Errorf("nominatim: %s", r.Error)
	}
	for _, k := range []string{"city", "town", "village", "municipality", "city_district", "county", "state_district", "state", "region", "province"} {
		if v := r.Address[k]; v != "" {
			names = append(names, v)
		}
	}
	return strings.ToLower(r.Address["country_code"]), names, nil
}

// ── NWS (api.weather.gov, GeoJSON) ──

func parseNWS(b []byte) ([]Alert, error) {
	var r struct {
		Features []struct {
			Properties struct {
				ID, AreaDesc, Status, MessageType, Severity, Event string
				Headline, Description, Instruction                 string
				Onset, Expires, Ends                               string
			} `json:"properties"`
		} `json:"features"`
	}
	if err := json.Unmarshal(b, &r); err != nil {
		return nil, err
	}
	out := []Alert{}
	for _, f := range r.Features {
		p := f.Properties
		if !actual(p.Status, p.MessageType) {
			continue
		}
		exp := p.Ends
		if exp == "" {
			exp = p.Expires
		}
		out = append(out, Alert{ID: p.ID, Source: "nws", Event: p.Event, Headline: p.Headline,
			Description: p.Description, Instruction: p.Instruction, Severity: severity(p.Severity),
			Area: p.AreaDesc, Onset: p.Onset, Expires: exp})
	}
	return out, nil
}

// ── MET Norway MetAlerts 2.0 (current.json, GeoJSON) ──

func parseMetNo(b []byte) ([]Alert, error) {
	var r struct {
		Features []struct {
			Properties struct {
				ID, Title, Event, EventAwarenessName, Severity, Status, Type string
				Description, Instruction, Area                               string
			} `json:"properties"`
			When struct {
				Interval []string `json:"interval"`
			} `json:"when"`
		} `json:"features"`
	}
	if err := json.Unmarshal(b, &r); err != nil {
		return nil, err
	}
	out := []Alert{}
	for _, f := range r.Features {
		p := f.Properties
		if !actual(p.Status, p.Type) {
			continue
		}
		a := Alert{ID: p.ID, Source: "metno", Event: p.EventAwarenessName, Headline: strings.TrimSpace(p.Title),
			Description: p.Description, Instruction: p.Instruction, Severity: severity(p.Severity), Area: p.Area}
		if a.Event == "" {
			a.Event = p.Event
		}
		if len(f.When.Interval) == 2 {
			a.Onset, a.Expires = f.When.Interval[0], f.When.Interval[1]
		}
		out = append(out, a)
	}
	return out, nil
}

// ── DWD through Bright Sky (api.brightsky.dev/alerts) ──

func parseBrightSky(b []byte) ([]Alert, error) {
	var r struct {
		Alerts []struct {
			AlertID       string `json:"alert_id"`
			Status        string `json:"status"`
			Severity      string `json:"severity"`
			EventEN       string `json:"event_en"`
			HeadlineEN    string `json:"headline_en"`
			DescriptionEN string `json:"description_en"`
			InstructionEN string `json:"instruction_en"`
			Onset         string `json:"onset"`
			Expires       string `json:"expires"`
		} `json:"alerts"`
		Location struct {
			Name string `json:"name"`
		} `json:"location"`
	}
	if err := json.Unmarshal(b, &r); err != nil {
		return nil, err
	}
	out := []Alert{}
	for _, a := range r.Alerts {
		if !actual(a.Status, "") {
			continue
		}
		out = append(out, Alert{ID: a.AlertID, Source: "dwd", Event: a.EventEN, Headline: a.HeadlineEN,
			Description: a.DescriptionEN, Instruction: a.InstructionEN, Severity: severity(a.Severity),
			Area: r.Location.Name, Onset: a.Onset, Expires: a.Expires})
	}
	return out, nil
}

// ── MeteoAlarm (legacy Atom feed per country) ──

// The feed has no geometry, only area names, one entry per area. An entry
// is kept when its area's name (before " - ", generic words dropped) is
// one of the place's names, or contained in one.
// ponytail: name matching, misses areas named unlike OSM's (e.g. "&" vs "and"); EMMA_ID polygons if it matters.
func parseMeteoAlarm(b []byte, names []string) ([]Alert, error) {
	var r struct {
		Entries []struct {
			Title       string `xml:"title"`
			AreaDesc    string `xml:"areaDesc"`
			Event       string `xml:"event"`
			Severity    string `xml:"severity"`
			Status      string `xml:"status"`
			MessageType string `xml:"message_type"`
			Identifier  string `xml:"identifier"`
			Onset       string `xml:"onset"`
			Expires     string `xml:"expires"`
		} `xml:"entry"`
	}
	if err := xml.Unmarshal(b, &r); err != nil {
		return nil, err
	}
	out := []Alert{}
	seen := map[string]bool{}
	for _, e := range r.Entries {
		if !actual(e.Status, e.MessageType) || seen[e.Identifier] || !areaMatches(e.AreaDesc, names) {
			continue
		}
		seen[e.Identifier] = true
		out = append(out, Alert{ID: e.Identifier, Source: "meteoalarm", Event: e.Event, Headline: e.Title,
			Severity: severity(e.Severity), Area: e.AreaDesc, Onset: e.Onset, Expires: e.Expires})
	}
	return out, nil
}

var generic = map[string]bool{"kreis": true, "landkreis": true, "stadt": true, "stadtkreis": true, "county": true,
	"province": true, "provincia": true, "region": true, "district": true, "of": true, "de": true, "du": true, "la": true,
	"the": true, "and": true, "&": true, "e": true, "et": true, "y": true, "und": true}

// core is an area name without its " - part", punctuation and generic
// words: "Kreis Wittmund - Küste" → "wittmund", "Hautes-Alpes" → "hautes alpes",
// "Yorkshire & Humber" and "Yorkshire and the Humber" → "yorkshire humber".
func core(s string) string {
	s, _, _ = strings.Cut(s, " - ")
	s = strings.NewReplacer("-", " ", "'", " ", "’", " ", ",", " ").Replace(strings.ToLower(s))
	var keep []string
	for _, w := range strings.Fields(s) {
		if !generic[w] {
			keep = append(keep, w)
		}
	}
	return strings.Join(keep, " ")
}

// areaMatches: one of the areas (UK lists several, "|"-separated) is one
// of the names, or a whole-word part of one.
func areaMatches(areaDesc string, names []string) bool {
	for _, area := range strings.Split(areaDesc, "|") {
		a := core(area)
		if a == "" {
			continue
		}
		for _, n := range names {
			if c := core(n); c != "" && strings.Contains(" "+c+" ", " "+a+" ") {
				return true
			}
		}
	}
	return false
}

// meteoAlarmSlugs: ISO country code → the feed's name
// (feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-<slug>).
var meteoAlarmSlugs = map[string]string{
	"ad": "andorra", "at": "austria", "be": "belgium", "ba": "bosnia-herzegovina", "bg": "bulgaria",
	"hr": "croatia", "cy": "cyprus", "cz": "czechia", "dk": "denmark", "ee": "estonia", "fi": "finland",
	"fr": "france", "gr": "greece", "hu": "hungary", "is": "iceland", "ie": "ireland", "il": "israel",
	"it": "italy", "lv": "latvia", "lt": "lithuania", "lu": "luxembourg", "mt": "malta", "md": "moldova",
	"me": "montenegro", "nl": "netherlands", "pl": "poland", "pt": "portugal", "mk": "republic-of-north-macedonia",
	"ro": "romania", "rs": "serbia", "sk": "slovakia", "si": "slovenia", "es": "spain", "se": "sweden",
	"ch": "switzerland", "ua": "ukraine", "gb": "united-kingdom",
}

// Feed is how alerts are fetched for a place.
type Feed struct {
	Name  string
	URL   string
	Parse func([]byte) ([]Alert, error)
}

// FeedFor picks the feed for a place; ok is false where there is none.
func FeedFor(p Place) (Feed, bool) {
	ll := fmt.Sprintf("lat=%.4f&lon=%.4f", p.Lat, p.Lon)
	switch p.Country {
	case "us", "pr", "gu", "vi", "as", "mp":
		return Feed{"nws", fmt.Sprintf("https://api.weather.gov/alerts/active?status=actual&point=%.4f,%.4f", p.Lat, p.Lon), parseNWS}, true
	case "no", "sj":
		return Feed{"metno", "https://api.met.no/weatherapi/metalerts/2.0/current.json?lang=en&" + ll, parseMetNo}, true
	case "de":
		return Feed{"dwd", "https://api.brightsky.dev/alerts?" + ll, parseBrightSky}, true
	}
	if slug, ok := meteoAlarmSlugs[p.Country]; ok {
		names := p.Names
		return Feed{"meteoalarm", "https://feeds.meteoalarm.org/feeds/meteoalarm-legacy-atom-" + slug,
			func(b []byte) ([]Alert, error) { return parseMeteoAlarm(b, names) }}, true
	}
	return Feed{}, false
}
