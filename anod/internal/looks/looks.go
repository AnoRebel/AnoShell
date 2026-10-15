// Package looks validates look files (ano/looks/schema.md). The rules mirror
// services/Looks.qml validate(), so `ano looks validate` and the shell agree.
package looks

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strings"

	"ano/anod/internal/config"
)

var (
	Shaders     = []string{"caustics", "paper_grain", "ink_bleed", "grid_scan", "clay_soft"}
	FontAliases = []string{"@main", "@mono", "@reading", "@expressive"}
	Motions     = []string{"liquid", "settle", "snappy"}
)

func BundledDir() string { return filepath.Join(config.ShellDir(), "looks") }
func UserDir() string    { return filepath.Join(filepath.Dir(config.UserPath()), "looks") }

// Entry is one look file and what's wrong with it.
type Entry struct {
	ID     string   `json:"id"`
	Name   string   `json:"name"`
	Source string   `json:"source"`
	Path   string   `json:"path"`
	Errors []string `json:"errors"`
}

// List reads every look; a user look overrides the built-in of the same id.
func List() []Entry {
	byID := map[string]Entry{}
	for _, d := range []struct{ dir, src string }{{BundledDir(), "bundled"}, {UserDir(), "user"}} {
		files, _ := filepath.Glob(filepath.Join(d.dir, "*.json"))
		for _, f := range files {
			e := Check(f)
			e.Source = d.src
			byID[e.ID] = e
		}
	}
	out := make([]Entry, 0, len(byID))
	for _, e := range byID {
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

// Check reads and validates one look file.
func Check(path string) Entry {
	id := strings.TrimSuffix(filepath.Base(path), ".json")
	e := Entry{ID: id, Name: id, Path: path}
	b, err := os.ReadFile(path)
	if err != nil {
		e.Errors = []string{err.Error()}
		return e
	}
	var v any
	if err := json.Unmarshal(b, &v); err != nil {
		e.Errors = []string{"invalid JSON: " + err.Error()}
		return e
	}
	if m, ok := v.(map[string]any); ok {
		if n, ok := m["name"].(string); ok && n != "" {
			e.Name = n
		}
	}
	e.Errors = Validate(v, id)
	return e
}

// Validate returns the problems with a decoded look whose file is <fileID>.json.
func Validate(v any, fileID string) []string {
	look, ok := v.(map[string]any)
	if !ok {
		return []string{"the file must contain a JSON object"}
	}
	var e []string
	switch id, _ := look["id"].(string); {
	case id == "":
		e = append(e, "id is required")
	case id != fileID:
		e = append(e, fmt.Sprintf("id %q must match the file name %q", id, fileID))
	}
	if n, _ := look["name"].(string); n == "" {
		e = append(e, "name is required")
	}
	e = validateBody(look, "", e)
	if s, present := look["surfaces"]; present && s != nil {
		surf, ok := s.(map[string]any)
		if !ok {
			return append(e, "surfaces must be an object")
		}
		for _, name := range sortedKeys(surf) {
			if m, ok := surf[name].(map[string]any); ok {
				e = validateBody(m, "surfaces."+name+".", e)
			} else {
				e = append(e, "surfaces."+name+" must be an object")
			}
		}
	}
	return e
}

// validateBody checks the keys a look and each of its surfaces share.
func validateBody(look map[string]any, pre string, e []string) []string {
	add := func(f string, a ...any) { e = append(e, pre+fmt.Sprintf(f, a...)) }
	obj := func(x any, path string) map[string]any {
		if x == nil {
			return nil
		}
		m, ok := x.(map[string]any)
		if !ok {
			add("%s must be an object", path)
		}
		return m
	}
	num := func(m map[string]any, k string, lo, hi float64, path string) {
		x, present := m[k]
		if !present {
			return
		}
		if f, ok := x.(float64); !ok || f < lo || f > hi {
			add("%s must be a number from %g to %g", path, lo, hi)
		}
	}
	sh := obj(look["shape"], "shape")
	mat := obj(look["material"], "material")
	typ := obj(look["typography"], "typography")
	mot := obj(look["motion"], "motion")
	num(sh, "radiusScale", 0.2, 3, "shape.radiusScale")
	num(sh, "stroke", 0, 4, "shape.stroke")
	num(sh, "connectedRadius", 0, 48, "shape.connectedRadius")
	if k, present := mat["kind"]; present && !slices.Contains([]any{"solid", "paper", "clay"}, k) {
		add("material.kind %q is not solid, paper or clay", fmt.Sprint(k))
	}
	if t := obj(look["texture"], "texture"); t != nil {
		if s, _ := t["shader"].(string); !slices.Contains(Shaders, s) {
			add("texture.shader %q is not a known shader (%s)", fmt.Sprint(t["shader"]), strings.Join(Shaders, ", "))
		}
		if a, present := t["animate"]; present && a != "static" && a != "interaction" {
			add("texture.animate must be static or interaction")
		}
	}
	if t, present := look["transition"]; present && t != "none" && t != "ink_bleed" {
		add("transition must be none or ink_bleed")
	}
	for _, role := range sortedKeys(typ) {
		s, ok := typ[role].(string)
		switch {
		case !ok:
			add("typography.%s must be a font name or %s", role, strings.Join(FontAliases, "/"))
		case strings.HasPrefix(s, "@") && !slices.Contains(FontAliases, s):
			add("typography.%s: unknown alias %s", role, s)
		}
	}
	for _, tok := range sortedKeys(mot) {
		if !slices.Contains(Motions, tok) {
			add("motion.%s is not liquid, settle or snappy", tok)
			continue
		}
		m, ok := mot[tok].(map[string]any)
		if !ok {
			add("motion.%s must be an object", tok)
			continue
		}
		num(m, "spring", 0.5, 40, "motion."+tok+".spring")
		num(m, "damping", 0.05, 1, "motion."+tok+".damping")
		num(m, "mass", 0.2, 3, "motion."+tok+".mass")
	}
	return e
}

func sortedKeys(m map[string]any) []string {
	ks := make([]string, 0, len(m))
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}
