package themestudio

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

// fakeMatugen answers like matugen 4's --json hex dump: every role's colour
// is the seed with the role's first letter in the last digit, so tests can
// tell which seed a role came from.
func fakeMatugen(calls *[][]string) Exec {
	return func(_ context.Context, args ...string) ([]byte, error) {
		*calls = append(*calls, args)
		i := slices.Index(args, "hex")
		if i < 0 || i+1 >= len(args) {
			return nil, errors.New("no seed")
		}
		seed := args[i+1]
		colors := map[string]any{}
		for _, r := range []string{"background", "surface", "outline", "primary", "on_primary", "primary_container",
			"on_primary_container", "primary_fixed", "primary_fixed_dim", "on_primary_fixed", "on_primary_fixed_variant",
			"secondary", "on_secondary", "secondary_container", "tertiary", "on_tertiary"} {
			colors[r] = map[string]any{"default": map[string]string{"color": seed[:6] + fmt.Sprintf("%x", len(r)%16)}}
		}
		return json.Marshal(map[string]any{"colors": colors})
	}
}

func TestValidate(t *testing.T) {
	bad := []Request{
		{Primary: ""},
		{Primary: "7c4dff"},
		{Primary: "#7c4dfz"},
		{Primary: "#7c4dff; rm -rf ~"},
		{Primary: "#7c4dff", Secondary: "red"},
		{Primary: "#7c4dff", Mode: "dim"},
		{Primary: "#7c4dff", SchemeType: "scheme-vibrant"},
		{Primary: "#7c4dff", Overrides: map[string]string{"primary": "#12"}},
	}
	for _, r := range bad {
		if err := r.Validate(false); err == nil {
			t.Errorf("%+v: want an error", r)
		}
	}
	r := Request{Primary: "#7C4DFF", Tertiary: "#00AA88"}
	if err := r.Validate(false); err != nil {
		t.Fatal(err)
	}
	if r.Primary != "#7c4dff" || r.Tertiary != "#00aa88" || r.Mode != "dark" || r.SchemeType != "tonal-spot" {
		t.Errorf("not normalised: %+v", r)
	}
	for _, n := range []string{"", "   ", "!!!", "a\x00b", strings.Repeat("x", 65)} {
		r := Request{Name: n, Primary: "#7c4dff"}
		if err := r.Validate(true); err == nil {
			t.Errorf("name %q: want an error", n)
		}
	}
}

func TestSlug(t *testing.T) {
	for in, want := range map[string]string{
		"Dusk Violet!": "dusk-violet", "../../etc/passwd": "etc-passwd", "  A  b  ": "a-b",
		"Café": "caf", "日本": "", "x" + strings.Repeat("-y", 40): "x" + strings.Repeat("-y", 31),
	} {
		got := Slug(in)
		if got != want {
			t.Errorf("Slug(%q) = %q, want %q", in, got, want)
		}
		if got != "" && !ValidSlug(got) {
			t.Errorf("Slug(%q) = %q is not a valid slug", in, got)
		}
	}
}

func TestGenerateSeedsAndOverrides(t *testing.T) {
	var calls [][]string
	r := Request{Primary: "#111111", Secondary: "#222222", Mode: "light", SchemeType: "vibrant",
		Overrides: map[string]string{"surface": "#ABCDEF"}}
	c, err := Generate(context.Background(), fakeMatugen(&calls), "/cfg.toml", r)
	if err != nil {
		t.Fatal(err)
	}
	if len(calls) != 2 {
		t.Fatalf("want 2 matugen runs (primary, secondary), got %d", len(calls))
	}
	want := []string{"-c", "/cfg.toml", "color", "hex", "#111111", "--mode", "light", "--type", "scheme-vibrant", "--json", "hex", "--dry-run"}
	if !slices.Equal(calls[0], want) {
		t.Errorf("argv %q, want %q", calls[0], want)
	}
	if !strings.HasPrefix(c["primary"], "#11111") || !strings.HasPrefix(c["tertiary"], "#11111") {
		t.Errorf("primary/tertiary should come from the primary seed: %v", c)
	}
	// secondary family = the secondary seed's primary family
	if c["secondary"] != c2("primary") || c["on_secondary_container"] != c2("on_primary_container") ||
		c["secondary_fixed_dim"] != c2("primary_fixed_dim") {
		t.Errorf("secondary roles not from the secondary seed: %v", c)
	}
	if c["surface"] != "#abcdef" {
		t.Errorf("override not applied: %s", c["surface"])
	}
	if _, err := Generate(context.Background(), fakeMatugen(&calls), "", Request{Primary: "#111111",
		Overrides: map[string]string{"nonsense": "#000000"}}); err == nil {
		t.Error("unknown override role: want an error")
	}
	if _, err := Generate(context.Background(), func(context.Context, ...string) ([]byte, error) { return []byte("{}"), nil },
		"", Request{Primary: "#111111"}); err == nil {
		t.Error("empty matugen output: want an error")
	}
}

// c2 is what the fake gives role for the second seed.
func c2(role string) string {
	return "#22222" + fmt.Sprintf("%x", len(role)%16)
}

func TestStore(t *testing.T) {
	dir := t.TempDir()
	s := Store{UserDir: filepath.Join(dir, "user"), BundledDir: filepath.Join(dir, "bundled")}
	os.MkdirAll(s.BundledDir, 0o755)
	os.MkdirAll(s.UserDir, 0o755)
	os.WriteFile(filepath.Join(s.BundledDir, "nord-dark.json"), []byte(`{"_meta":{"darkmode":true},"primary":"#88C0D0","background":"#2e3440"}`), 0o644)
	os.WriteFile(filepath.Join(s.UserDir, "mine.json"), []byte(`{"_meta":{"name":"Mine"},"primary":"#000000","background":"#ffffff"}`), 0o644)
	colors := map[string]string{"primary": "#123456", "background": "#fafafa"}

	slug, err := s.Save(Request{Name: "Sea Glass", Primary: "#123456", Mode: "light"}, colors)
	if err != nil || slug != "sea-glass" {
		t.Fatalf("save: %q %v", slug, err)
	}
	if _, err := s.Save(Request{Name: "Sea  glass", Primary: "#654321"}, colors); err != nil {
		t.Errorf("overwriting a studio theme: %v", err)
	}
	if _, err := s.Save(Request{Name: "Nord Dark", Primary: "#123456"}, colors); err == nil {
		t.Error("a built-in theme's name: want an error")
	}
	if _, err := s.Save(Request{Name: "mine", Primary: "#123456"}, colors); err == nil {
		t.Error("overwriting a hand-written theme: want an error")
	}

	b, dark, err := s.Palette("sea-glass")
	if err != nil {
		t.Fatal(err)
	}
	var flat map[string]any
	json.Unmarshal(b, &flat)
	if !dark || flat["primary"] != "#123456" || flat["darkmode"] != true || flat["_meta"] != nil {
		t.Errorf("palette: dark=%v %v", dark, flat) // the second save was dark (the default mode)
	}
	if _, dark, err := s.Palette("nord-dark"); err != nil || !dark {
		t.Errorf("bundled palette: %v %v", dark, err)
	}
	if _, _, err := s.Palette("../nord-dark"); err == nil {
		t.Error("path in a name: want an error")
	}

	if err := s.Delete("mine"); err == nil {
		t.Error("deleting a hand-written theme: want an error")
	}
	if err := s.Delete("nord-dark"); err == nil {
		t.Error("deleting a bundled theme: want an error")
	}
	if err := s.Delete("../user/sea-glass"); err == nil {
		t.Error("path in a name: want an error")
	}
	if err := s.Delete("sea-glass"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(s.UserDir, "sea-glass.json")); !os.IsNotExist(err) {
		t.Error("still there after delete")
	}
}
