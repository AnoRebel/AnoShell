package xkb

import (
	"os"
	"testing"
)

func TestInstalledCatalogue(t *testing.T) {
	if _, err := os.Stat(Path); err != nil {
		t.Skip("no evdev.xml")
	}
	cat, err := Catalogue(Path)
	if err != nil {
		t.Fatal(err)
	}
	var us, azerty bool
	for _, l := range cat {
		us = us || (l.Layout == "us" && l.Variant == "" && l.Description == "English (US)")
		azerty = azerty || (l.Layout == "fr" && l.Variant == "azerty")
	}
	if !us || !azerty || len(cat) < 100 {
		t.Fatalf("us %v fr(azerty) %v, %d entries", us, azerty, len(cat))
	}
	ls, vs, err := Join(cat, []Layout{{Layout: "us"}, {Layout: "fr", Variant: "azerty"}})
	if err != nil || ls != "us,fr" || vs != ",azerty" {
		t.Fatalf("%q %q %v", ls, vs, err)
	}
	for _, bad := range []Layout{{Layout: "us\",x"}, {Layout: "zz"}, {Layout: "us", Variant: "nope"}} {
		if _, _, err := Join(cat, []Layout{bad}); err == nil {
			t.Fatalf("accepted %+v", bad)
		}
	}
}
