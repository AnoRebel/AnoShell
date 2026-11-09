package atelier

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"
)

// A catalog entry's changes: a string or a list, plain text, capped; any
// other shape reads as none without making the entry unusable.
func TestChanges(t *testing.T) {
	h, c, _ := setup(t)
	a1 := targz(t, tarEnt{name: "ocean.json", body: string(theme("ocean", "1.0.0"))})
	c.put(Entry{ID: "ocean", Type: "themes", Version: "1.0.0"}, a1, a1)
	h.Refresh("")
	install(t, h, "themes", "ocean")
	a2 := targz(t, tarEnt{name: "ocean.json", body: string(theme("ocean", "1.2.0"))})
	c.put(Entry{ID: "ocean", Type: "themes", Version: "1.2.0", Changes: Changes{"<b>Bolder</b> blues\x1b[31m", "  ", strings.Repeat("x", 400)}}, a2, a2)
	h.Refresh("")
	res, _ := h.List("themes")
	i := slices.IndexFunc(res.Items, func(it Item) bool { return it.ID == "ocean" })
	if i < 0 || res.Items[i].Update != "1.2.0" || len(res.Items[i].Changes) != 2 || res.Items[i].Changes[0] != "<b>Bolder</b> blues[31m" ||
		len([]rune(res.Items[i].Changes[1])) != maxChangeLen {
		t.Fatalf("changes on the update: %+v", res.Items)
	}
	p, err := h.Prepare("themes", "ocean", "")
	if err != nil || len(p.Changes) != 2 {
		t.Fatalf("changes on prepare: %+v %v", p, err)
	}
	h.Cancel(p.Token)

	var e struct{ Changes Changes }
	for in, want := range map[string]int{`"one\ntwo\n\nthree"`: 3, `["a","b"]`: 2, `42`: 0, `[1,2]`: 0, `null`: 0, `""`: 0} {
		e.Changes = nil
		if err := json.Unmarshal([]byte(`{"changes":`+in+`}`), &e); err != nil || len(e.Changes) != want {
			t.Fatalf("%s: %v %v", in, e.Changes, err)
		}
	}
	many := make([]string, 50)
	for i := range many {
		many[i] = "line"
	}
	b, _ := json.Marshal(map[string]any{"changes": many})
	json.Unmarshal(b, &e)
	if len(e.Changes) != maxChangeLines {
		t.Fatalf("lines not capped: %d", len(e.Changes))
	}
	var idx Index
	json.Unmarshal([]byte(`{"items":[{"id":"x","type":"themes","changes":{"bad":1}}]}`), &idx)
	if len(validEntries(idx.Items)) != 1 {
		t.Fatal("a bad changes field dropped the entry")
	}
}
