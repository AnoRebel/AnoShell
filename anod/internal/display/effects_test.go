package display

import (
	"strings"
	"testing"
)

func TestEffects(t *testing.T) {
	if hyprEffects(&Effects{Warp: true, Xray: true}) != "" || niriEffects(&Effects{Warp: true, Xray: true}) != "" || hyprEffects(nil) != "" {
		t.Fatal("defaults must write nothing")
	}
	if got := hyprEffects(&Effects{Warp: false}); !strings.Contains(got, "no_warps = true") {
		t.Fatalf("no warps: %q", got)
	}
	if got := hyprWarpLive(&Effects{Warp: true}); !strings.Contains(got, "no_warps = false") {
		t.Fatalf("live back on: %q", got)
	}
	got := niriEffects(&Effects{Warp: true, Xray: false})
	if strings.Count(got, "xray false") != 3 || strings.Contains(got, "blur") {
		t.Fatalf("niri xray off: %q", got)
	}
}
