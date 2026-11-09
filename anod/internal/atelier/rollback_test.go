package atelier

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func pieceUpdate(t *testing.T, h *Store, c *fakeCatalog, v string) string {
	t.Helper()
	a := targz(t, tarEnt{name: "piece.json", body: `{"id":"wx","name":"Wx","version":"` + v + `"}`}, tarEnt{name: "main.qml", body: "Item {} // " + v})
	c.put(Entry{ID: "wx", Type: "pieces", Version: v}, a, a)
	h.Refresh("")
	_, path := install(t, h, "pieces", "wx")
	return path
}

func dirNames(dir string) []string {
	ents, _ := os.ReadDir(dir)
	out := []string{}
	for _, e := range ents {
		out = append(out, e.Name())
	}
	return out
}

// An update keeps exactly one previous version until the new one loads
// (confirm) or fails (rollback); a restart in between keeps both.
func TestKeepConfirmRollback(t *testing.T) {
	h, c, tmp := setup(t)
	dir := filepath.Join(tmp, ".config/anoshell/pieces")
	os.MkdirAll(filepath.Join(dir, "mine"), 0o755) // the user's own piece: never touched
	os.WriteFile(filepath.Join(dir, "mine/piece.json"), []byte(`{"name":"Mine"}`), 0o644)

	v1 := pieceUpdate(t, h, c, "1")
	if ok, err := h.Confirm("pieces", "wx", v1); ok || err != nil {
		t.Fatalf("confirm with nothing kept: %v %v", ok, err)
	}
	if _, err := h.Rollback("pieces", "wx", ""); err == nil {
		t.Fatal("rollback with nothing kept")
	}
	v2 := pieceUpdate(t, h, c, "2")
	if got := dirNames(dir); !slices.Equal(got, []string{".atelier-prev-wx", "mine", "wx~2"}) {
		t.Fatalf("after update: %v", got)
	}
	if r := h.receipt("pieces", "wx"); r.Previous == nil || r.Previous.Version != "1" || r.Previous.Path != h.prevPath("pieces", "wx") {
		t.Fatalf("receipt %+v", r)
	}
	res, _ := h.List("pieces")
	if n := len(slices.DeleteFunc(res.Items, func(it Item) bool { return it.ID != "wx" })); n != 1 {
		t.Fatalf("the kept version is listed: %d", n)
	}
	if ok, _ := h.Confirm("pieces", "wx", v1); ok { // a report about another folder is ignored
		t.Fatal("confirmed a stale folder")
	}
	if ok, err := h.Confirm("pieces", "wx", v2); !ok || err != nil {
		t.Fatalf("confirm: %v %v", ok, err)
	}
	if got := dirNames(dir); !slices.Equal(got, []string{"mine", "wx~2"}) || h.receipt("pieces", "wx").Previous != nil {
		t.Fatalf("after confirm: %v", got)
	}

	// Two updates without a load in between: the last good one stays the fallback.
	pieceUpdate(t, h, c, "3")
	v4 := pieceUpdate(t, h, c, "4")
	if got := dirNames(dir); !slices.Equal(got, []string{".atelier-prev-wx", "mine", "wx~4"}) || h.receipt("pieces", "wx").Previous.Version != "2" {
		t.Fatalf("after two updates: %v", got)
	}

	// Crash in between: a new anod sees both folders and keeps the update pending.
	h2 := New()
	h2.Client, h2.Catalogs = h.Client, h.Catalogs
	if err := h2.Init(); err != nil {
		t.Fatal(err)
	}
	if got := dirNames(dir); !slices.Equal(got, []string{".atelier-prev-wx", "mine", "wx~4"}) {
		t.Fatalf("after restart: %v", got)
	}
	if _, err := h2.Rollback("pieces", "wx", v1); err == nil {
		t.Fatal("rolled back on a stale report")
	}
	rev := h2.Revision()
	ver, err := h2.Rollback("pieces", "wx", v4)
	if err != nil || ver != "2" {
		t.Fatalf("rollback: %q %v", ver, err)
	}
	r := h2.receipt("pieces", "wx")
	if got := dirNames(dir); !slices.Equal(got, []string{"mine", "wx~5"}) || r.Version != "2" || r.Seq != 5 || r.Previous != nil ||
		r.Path != filepath.Join(dir, "wx~5") || h2.Revision() != rev+1 {
		t.Fatalf("after rollback: %v %+v", got, r)
	}
	if b, _ := os.ReadFile(filepath.Join(dir, "wx~5/main.qml")); string(b) != "Item {} // 2" {
		t.Fatalf("rolled back to %q", b)
	}
	if len(h2.modifiedFiles(r)) != 0 {
		t.Fatal("the rolled-back receipt doesn't match its files")
	}
	if _, err := h2.Rollback("pieces", "wx", ""); err == nil {
		t.Fatal("rolled back twice")
	}
	// The catalog still has 4: it is offered as an update again.
	res, _ = h2.List("pieces")
	if i := slices.IndexFunc(res.Items, func(it Item) bool { return it.ID == "wx" }); i < 0 || res.Items[i].Update != "4" {
		t.Fatalf("no update offered after the rollback: %+v", res.Items)
	}

	// Remove while an update waits takes the kept folder too, and only that.
	pieceUpdate(t, h2, c, "5")
	if err := h2.Remove("pieces", "wx"); err != nil {
		t.Fatal(err)
	}
	if got := dirNames(dir); !slices.Equal(got, []string{"mine"}) {
		t.Fatalf("after remove: %v", got)
	}
	if _, err := h2.Confirm("themes", "x", ""); err == nil {
		t.Fatal("confirm on a data type")
	}
}

// A crash during an update, after the old folder moved aside but before the
// receipt: the next start puts the old one back and drops the half install.
func TestRecoverHalfUpdate(t *testing.T) {
	h, c, tmp := setup(t)
	dir := filepath.Join(tmp, ".config/anoshell/pieces")
	v1 := pieceUpdate(t, h, c, "1")
	os.Rename(v1, h.prevPath("pieces", "wx"))
	os.MkdirAll(filepath.Join(dir, "wx~2"), 0o755)
	os.WriteFile(filepath.Join(dir, "wx~2/piece.json"), []byte(`{"name":"Wx"}`), 0o644)
	os.MkdirAll(filepath.Join(dir, ".atelier-prev-gone"), 0o755) // no receipt waits on it
	if err := h.Init(); err != nil {
		t.Fatal(err)
	}
	if got := dirNames(dir); !slices.Equal(got, []string{"wx~1"}) {
		t.Fatalf("after recovery: %v", got)
	}
	if b, _ := os.ReadFile(filepath.Join(v1, "main.qml")); string(b) != "Item {} // 1" {
		t.Fatalf("recovered %q", b)
	}
}
