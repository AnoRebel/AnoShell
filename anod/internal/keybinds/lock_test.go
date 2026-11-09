package keybinds

import (
	"path/filepath"
	"testing"
	"time"
)

// A second holder waits until the first releases (separate opens, as two
// processes or two anod requests would).
func TestLockExcludes(t *testing.T) {
	p := Paths{Overrides: filepath.Join(t.TempDir(), "anoshell", "keybinds.json")}
	unlock, err := Lock(p)
	if err != nil {
		t.Fatal(err)
	}
	got := make(chan struct{})
	go func() {
		u, err := Lock(p)
		if err != nil {
			t.Error(err)
			return
		}
		u()
		close(got)
	}()
	select {
	case <-got:
		t.Fatal("second lock taken while the first was held")
	case <-time.After(100 * time.Millisecond):
	}
	unlock()
	select {
	case <-got:
	case <-time.After(2 * time.Second):
		t.Fatal("second lock never taken after release")
	}
}
