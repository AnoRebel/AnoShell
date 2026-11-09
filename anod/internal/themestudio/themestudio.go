// Package themestudio makes static themes from seed colours (Settings →
// Appearance → Theme studio): matugen turns 1–3 seeds into a full Material 3
// scheme, per-role overrides go on top, and the result is saved as a user
// theme JSON (the shape assets/themes/*.json have) in cfg/anoshell/themes.
//
// Every input is validated here; matugen runs as argv, never through a shell.
package themestudio

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"
)

// Exec runs matugen with args and returns its stdout (tests pass a fake).
type Exec func(ctx context.Context, args ...string) ([]byte, error)

// Request is one scheme to generate (and maybe save).
type Request struct {
	Name       string            `json:"name"`      // display name; the file name is its slug
	Primary    string            `json:"primary"`   // #rrggbb, required
	Secondary  string            `json:"secondary"` // optional seed for the secondary roles
	Tertiary   string            `json:"tertiary"`  // optional seed for the tertiary roles
	Mode       string            `json:"mode"`      // dark | light
	SchemeType string            `json:"schemeType"`
	Overrides  map[string]string `json:"overrides"` // role → #rrggbb, over the generated ones
}

var (
	hexRe  = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)
	slugRe = regexp.MustCompile(`^[a-z0-9]+(-[a-z0-9]+)*$`)
	// SchemeTypes matugen knows (without its "scheme-" prefix).
	SchemeTypes = []string{"tonal-spot", "content", "expressive", "fidelity", "fruit-salad", "monochrome", "neutral", "rainbow", "vibrant"}
)

// ValidHex reports whether s is #rrggbb.
func ValidHex(s string) bool { return hexRe.MatchString(s) }

// ValidSlug reports whether s can name a theme file (lowercase, digits, dashes).
func ValidSlug(s string) bool { return len(s) <= 64 && slugRe.MatchString(s) }

// Slug turns a display name into a file name: "Dusk Violet!" → "dusk-violet".
func Slug(name string) string {
	var b strings.Builder
	dash := false
	for _, r := range strings.ToLower(name) {
		if r < 128 && (unicode.IsLetter(r) || unicode.IsDigit(r)) {
			b.WriteRune(r)
			dash = false
		} else if b.Len() > 0 && !dash {
			b.WriteByte('-')
			dash = true
		}
	}
	s := strings.TrimSuffix(b.String(), "-")
	if len(s) > 64 {
		s = strings.TrimSuffix(s[:64], "-")
	}
	return s
}

// Validate normalises req (lowercase hex, default mode and scheme) and
// reports the first bad field. needName: saving needs a name with a slug.
func (r *Request) Validate(needName bool) error {
	r.Name = strings.TrimSpace(r.Name)
	if needName {
		if r.Name == "" || len(r.Name) > 64 {
			return errors.New("name: 1–64 characters")
		}
		for _, c := range r.Name {
			if unicode.IsControl(c) {
				return errors.New("name: no control characters")
			}
		}
		if Slug(r.Name) == "" {
			return errors.New("name: needs at least one letter or digit (a–z, 0–9)")
		}
	}
	for _, f := range []struct {
		name string
		v    *string
		need bool
	}{{"primary", &r.Primary, true}, {"secondary", &r.Secondary, false}, {"tertiary", &r.Tertiary, false}} {
		if *f.v == "" && !f.need {
			continue
		}
		if !ValidHex(*f.v) {
			return fmt.Errorf("%s: want #rrggbb, got %q", f.name, *f.v)
		}
		*f.v = strings.ToLower(*f.v)
	}
	switch r.Mode {
	case "":
		r.Mode = "dark"
	case "dark", "light":
	default:
		return fmt.Errorf("mode: want dark or light, got %q", r.Mode)
	}
	if r.SchemeType == "" {
		r.SchemeType = "tonal-spot"
	}
	ok := false
	for _, t := range SchemeTypes {
		ok = ok || t == r.SchemeType
	}
	if !ok {
		return fmt.Errorf("schemeType: want one of %s", strings.Join(SchemeTypes, ", "))
	}
	for k, v := range r.Overrides {
		if !ValidHex(v) {
			return fmt.Errorf("override %s: want #rrggbb, got %q", k, v)
		}
		r.Overrides[k] = strings.ToLower(v)
	}
	return nil
}

// accent roles a secondary/tertiary seed takes from its own scheme's primary family.
var accentRoles = []string{"", "on_", "_container", "on__container", "_fixed", "_fixed_dim", "on__fixed", "on__fixed_variant"}

func role(pattern, family string) string {
	if strings.HasPrefix(pattern, "on_") {
		return "on_" + family + strings.TrimPrefix(pattern, "on_")
	}
	return family + pattern
}

// Generate makes the scheme: matugen from the primary seed, then the
// secondary and tertiary families from their own seeds (each seed's scheme
// primary family), then the overrides. Unknown override roles are an error.
func Generate(ctx context.Context, run Exec, config string, r Request) (map[string]string, error) {
	if err := r.Validate(false); err != nil {
		return nil, err
	}
	scheme := func(seed string) (map[string]string, error) {
		args := []string{"color", "hex", seed, "--mode", r.Mode, "--type", "scheme-" + r.SchemeType, "--json", "hex", "--dry-run"}
		if config != "" {
			args = append([]string{"-c", config}, args...)
		}
		out, err := run(ctx, args...)
		if err != nil {
			return nil, fmt.Errorf("matugen: %w", err)
		}
		return parse(out)
	}
	colors, err := scheme(r.Primary)
	if err != nil {
		return nil, err
	}
	for _, s := range []struct{ seed, family string }{{r.Secondary, "secondary"}, {r.Tertiary, "tertiary"}} {
		if s.seed == "" {
			continue
		}
		other, err := scheme(s.seed)
		if err != nil {
			return nil, err
		}
		for _, p := range accentRoles {
			if v, ok := other[role(p, "primary")]; ok {
				colors[role(p, s.family)] = v
			}
		}
	}
	for k, v := range r.Overrides {
		if _, ok := colors[k]; !ok {
			return nil, fmt.Errorf("override: unknown role %q", k)
		}
		colors[k] = v
	}
	return colors, nil
}

// parse reads matugen 4's --json hex dump into {role: hex}.
func parse(dump []byte) (map[string]string, error) {
	var d struct {
		Colors map[string]struct {
			Default struct {
				Color string `json:"color"`
			} `json:"default"`
		} `json:"colors"`
	}
	if err := json.Unmarshal(dump, &d); err != nil {
		return nil, fmt.Errorf("matugen output: %w", err)
	}
	out := map[string]string{}
	for role, v := range d.Colors {
		if ValidHex(v.Default.Color) {
			out[role] = strings.ToLower(v.Default.Color)
		}
	}
	if out["primary"] == "" || out["background"] == "" {
		return nil, errors.New("matugen output has no primary/background")
	}
	return out, nil
}

// Meta is a theme file's _meta.
type Meta struct {
	Name        string            `json:"name"`
	Description string            `json:"description,omitempty"`
	Darkmode    bool              `json:"darkmode"`
	Studio      bool              `json:"studio,omitempty"` // made here: the studio may overwrite or delete it
	Seeds       map[string]string `json:"seeds,omitempty"`
	SchemeType  string            `json:"schemeType,omitempty"`
	Overrides   map[string]string `json:"overrides,omitempty"`
}

// Store is the user and bundled theme directories.
type Store struct {
	UserDir    string // cfg/anoshell/themes
	BundledDir string // <shell>/assets/themes
}

func readMeta(path string) (Meta, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return Meta{}, err
	}
	var t struct {
		Meta Meta `json:"_meta"`
	}
	err = json.Unmarshal(b, &t)
	return t.Meta, err
}

// Save writes r's scheme as <slug>.json in the user dir and returns the slug.
// A built-in theme's name, or a user theme the studio didn't make (an Atelier
// install, a hand-written file), is never overwritten.
func (s Store) Save(r Request, colors map[string]string) (string, error) {
	if err := r.Validate(true); err != nil {
		return "", err
	}
	slug := Slug(r.Name)
	if _, err := os.Stat(filepath.Join(s.BundledDir, slug+".json")); err == nil {
		return "", fmt.Errorf("%q is a built-in theme's name; pick another", slug)
	}
	path := filepath.Join(s.UserDir, slug+".json")
	if m, err := readMeta(path); err == nil && !m.Studio {
		return "", fmt.Errorf("%s is a theme the studio didn't make; pick another name", path)
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("%s exists and isn't a readable theme; pick another name", path)
	}
	seeds := map[string]string{"primary": r.Primary}
	if r.Secondary != "" {
		seeds["secondary"] = r.Secondary
	}
	if r.Tertiary != "" {
		seeds["tertiary"] = r.Tertiary
	}
	doc := map[string]any{"_meta": Meta{Name: r.Name, Description: "Made in the Theme studio",
		Darkmode: r.Mode == "dark", Studio: true, Seeds: seeds, SchemeType: r.SchemeType, Overrides: r.Overrides}}
	for k, v := range colors {
		doc[k] = v
	}
	b, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(s.UserDir, 0o755); err != nil {
		return "", err
	}
	tmp, err := os.CreateTemp(s.UserDir, ".tmp-*")
	if err != nil {
		return "", err
	}
	defer os.Remove(tmp.Name()) // no-op after the rename
	if _, err := tmp.Write(append(b, '\n')); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Chmod(0o644); err != nil {
		tmp.Close()
		return "", err
	}
	if err := tmp.Close(); err != nil {
		return "", err
	}
	return slug, os.Rename(tmp.Name(), path)
}

// Delete removes a studio-made user theme.
func (s Store) Delete(slug string) error {
	if !ValidSlug(slug) {
		return fmt.Errorf("bad theme name %q", slug)
	}
	path := filepath.Join(s.UserDir, slug+".json")
	m, err := readMeta(path)
	if errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("no user theme %q", slug)
	}
	if err != nil || !m.Studio {
		return fmt.Errorf("%s wasn't made in the Theme studio; remove it yourself if you mean to", path)
	}
	return os.Remove(path)
}

// Palette reads theme slug (user dir first, then bundled) as colors.json
// content: {role: hex, …, darkmode}. dark is the theme's mode.
func (s Store) Palette(slug string) (colors []byte, dark bool, err error) {
	if !ValidSlug(slug) {
		return nil, false, fmt.Errorf("bad theme name %q", slug)
	}
	var b []byte
	for _, dir := range []string{s.UserDir, s.BundledDir} {
		if b, err = os.ReadFile(filepath.Join(dir, slug+".json")); err == nil {
			break
		}
	}
	if err != nil {
		return nil, false, fmt.Errorf("no theme %q", slug)
	}
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(b, &raw); err != nil {
		return nil, false, fmt.Errorf("theme %s: %w", slug, err)
	}
	flat := map[string]any{}
	for k, v := range raw {
		var c string
		if k != "_meta" && json.Unmarshal(v, &c) == nil && ValidHex(c) {
			flat[k] = strings.ToLower(c)
		}
	}
	if flat["primary"] == nil || flat["background"] == nil {
		return nil, false, fmt.Errorf("theme %s has no primary/background", slug)
	}
	var meta struct {
		Darkmode *bool `json:"darkmode"`
	}
	_ = json.Unmarshal(raw["_meta"], &meta)
	dark = meta.Darkmode == nil || *meta.Darkmode
	flat["darkmode"] = dark
	colors, err = json.MarshalIndent(flat, "", "  ")
	return colors, dark, err
}
