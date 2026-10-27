// Package config reads ano's JSON config (the bundled defaults plus the
// user's sparse delta), validates it against the schema exported from
// Config.qml, and migrates old layouts.
package config

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// Paths. ANO_SHELL_DIR overrides where the shell (and its bundled config.json) lives.
func configHome() string {
	if d := os.Getenv("XDG_CONFIG_HOME"); d != "" {
		return d
	}
	h, _ := os.UserHomeDir()
	return filepath.Join(h, ".config")
}

func ShellDir() string {
	if d := os.Getenv("ANO_SHELL_DIR"); d != "" {
		return d
	}
	return filepath.Join(configHome(), "quickshell", "ano")
}

func UserPath() string    { return filepath.Join(configHome(), "anoshell", "config.json") }
func BundledPath() string { return filepath.Join(ShellDir(), "config.json") }

// Load reads a JSON object; numbers stay json.Number so ints and reals differ.
// A missing file is an empty config.
func Load(path string) (map[string]any, error) {
	b, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return map[string]any{}, nil
	}
	if err != nil {
		return nil, err
	}
	return Parse(b)
}

func Parse(b []byte) (map[string]any, error) {
	d := json.NewDecoder(bytes.NewReader(b))
	d.UseNumber()
	var m map[string]any
	if err := d.Decode(&m); err != nil {
		return nil, err
	}
	if m == nil {
		m = map[string]any{}
	}
	return m, nil
}

// Effective is the bundled config with the user delta merged on top (what the shell sees).
func Effective() (map[string]any, error) {
	base, err := Load(BundledPath())
	if err != nil {
		return nil, fmt.Errorf("bundled config: %w", err)
	}
	user, err := Load(UserPath())
	if err != nil {
		return nil, fmt.Errorf("user config: %w", err)
	}
	return Merge(base, user), nil
}

// Merge deep-merges objects; any other value in over replaces base (arrays too,
// matching Config.qml's delta semantics).
func Merge(base, over map[string]any) map[string]any {
	out := make(map[string]any, len(base))
	for k, v := range base {
		out[k] = v
	}
	for k, v := range over {
		bo, ok1 := out[k].(map[string]any)
		oo, ok2 := v.(map[string]any)
		if ok1 && ok2 {
			out[k] = Merge(bo, oo)
		} else {
			out[k] = v
		}
	}
	return out
}

// Get walks a dot path.
func Get(m map[string]any, path string) (any, bool) {
	var cur any = m
	for _, k := range strings.Split(path, ".") {
		obj, ok := cur.(map[string]any)
		if !ok {
			return nil, false
		}
		if cur, ok = obj[k]; !ok {
			return nil, false
		}
	}
	return cur, true
}

func Bool(m map[string]any, path string, def bool) bool {
	if v, ok := Get(m, path); ok {
		if b, ok := v.(bool); ok {
			return b
		}
	}
	return def
}

func Int(m map[string]any, path string, def int) int {
	if v, ok := Get(m, path); ok {
		if n, ok := v.(json.Number); ok {
			if i, err := n.Int64(); err == nil {
				return int(i)
			}
		}
	}
	return def
}

func String(m map[string]any, path string, def string) string {
	if v, ok := Get(m, path); ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return def
}

// Set writes a dot path, creating objects on the way.
func Set(m map[string]any, path string, v any) { set(m, path, v) }

func set(m map[string]any, path string, v any) {
	keys := strings.Split(path, ".")
	for _, k := range keys[:len(keys)-1] {
		next, ok := m[k].(map[string]any)
		if !ok {
			next = map[string]any{}
			m[k] = next
		}
		m = next
	}
	m[keys[len(keys)-1]] = v
}

// Delete removes a dot path and any objects it leaves empty.
func Delete(m map[string]any, path string) { del(m, path) }

// del removes a dot path and any objects it leaves empty.
func del(m map[string]any, path string) {
	keys := strings.Split(path, ".")
	if len(keys) == 1 {
		delete(m, keys[0])
		return
	}
	child, ok := m[keys[0]].(map[string]any)
	if !ok {
		return
	}
	del(child, strings.Join(keys[1:], "."))
	if len(child) == 0 {
		delete(m, keys[0])
	}
}

// ── Schema and validation ───────────────────────────────────────────────────

//go:embed schema.json
var schemaJSON []byte

type Schema struct {
	Leaves  map[string]string `json:"leaves"` // key -> QML type
	Objects []string          `json:"objects"`
	objects map[string]bool
}

func LoadSchema() (*Schema, error) {
	var s Schema
	if err := json.Unmarshal(schemaJSON, &s); err != nil {
		return nil, err
	}
	s.objects = map[string]bool{}
	for _, o := range s.Objects {
		s.objects[o] = true
	}
	return &s, nil
}

type Issue struct {
	Key   string `json:"key"`
	Level string `json:"level"` // "error" or "warning"
	Msg   string `json:"message"`
}

func (i Issue) String() string { return fmt.Sprintf("%s: %s: %s", i.Level, i.Key, i.Msg) }

// Validate checks a config (usually the user delta) against the schema:
// wrong types are errors, unknown keys are warnings.
func (s *Schema) Validate(m map[string]any) []Issue {
	var out []Issue
	s.walk(m, "", &out)
	sort.Slice(out, func(i, j int) bool { return out[i].Key < out[j].Key })
	return out
}

func (s *Schema) walk(m map[string]any, prefix string, out *[]Issue) {
	for k, v := range m {
		p := k
		if prefix != "" {
			p = prefix + "." + k
		}
		if t, ok := s.Leaves[p]; ok {
			if msg := typeError(t, v); msg != "" {
				*out = append(*out, Issue{p, "error", msg})
			}
			continue
		}
		if s.objects[p] {
			if obj, ok := v.(map[string]any); ok {
				s.walk(obj, p, out)
			} else {
				*out = append(*out, Issue{p, "error", "expected an object, got " + kind(v)})
			}
			continue
		}
		msg := "unknown key (not in the schema; the shell ignores it)"
		if hint, ok := renamed[p]; ok {
			msg = "renamed to " + hint + "; run `ano config migrate`"
		}
		*out = append(*out, Issue{p, "warning", msg})
	}
}

// Leaf reports whether path is a schema leaf and v fits its type
// (null, "use the default", fits every type).
func (s *Schema) Leaf(path string, v any) bool {
	t, ok := s.Leaves[path]
	return ok && typeError(t, v) == ""
}

// Object reports whether path is an object in the schema.
func (s *Schema) Object(path string) bool { return s.objects[path] }

func typeError(t string, v any) string {
	ok := false
	switch t {
	case "var":
		return ""
	case "bool":
		_, ok = v.(bool)
	case "string":
		_, ok = v.(string)
	case "int":
		if n, isNum := v.(json.Number); isNum {
			_, err := n.Int64()
			ok = err == nil
		}
	case "real":
		_, ok = v.(json.Number)
	default:
		return ""
	}
	if ok || v == nil { // null = "use the default", which the shell tolerates
		return ""
	}
	return fmt.Sprintf("expected %s, got %s", t, kind(v))
}

func kind(v any) string {
	switch x := v.(type) {
	case nil:
		return "null"
	case bool:
		return "bool"
	case string:
		return "string"
	case json.Number:
		if _, err := x.Int64(); err == nil {
			return "int"
		}
		return "real"
	case []any:
		return "array"
	case map[string]any:
		return "object"
	}
	return fmt.Sprintf("%T", v)
}

// ── Migration ───────────────────────────────────────────────────────────────

// renamed maps old keys to their replacements (also used for validate hints).
var renamed = map[string]string{
	"hud.enabled":             "hud.enable",
	"activSpot":               "anoSpot",
	"appearance.theme.static": "appearance.theme.name",
	"bar.bars":                "bars",
}

// barsOverrides: per-bar copies of global settings that shadowed the global
// switches in Settings; bars[0]'s value moves to the global key.
var barsOverrides = map[string]string{
	"autoHide":       "bar.autoHide.enable",
	"showBackground": "bar.showBackground",
}

// Migrate rewrites old layouts in place and returns a log line per change.
// With pruneUnknown, keys the schema doesn't know (and that no rule moves) are removed.
func Migrate(m map[string]any, s *Schema, pruneUnknown bool) []string {
	var log []string
	olds := make([]string, 0, len(renamed))
	for o := range renamed {
		olds = append(olds, o)
	}
	sort.Strings(olds)
	for _, old := range olds {
		v, ok := Get(m, old)
		if !ok {
			continue
		}
		nu := renamed[old]
		cur, has := Get(m, nu)
		if !has || cur == nil || cur == "" {
			set(m, nu, v)
			log = append(log, fmt.Sprintf("moved %s -> %s", old, nu))
		} else {
			log = append(log, fmt.Sprintf("dropped %s (%s is already set)", old, nu))
		}
		del(m, old)
	}

	if bars, ok := m["bars"].([]any); ok && len(bars) > 0 {
		if b0, ok := bars[0].(map[string]any); ok {
			for _, k := range []string{"autoHide", "showBackground"} {
				v, ok := b0[k].(bool)
				if !ok {
					continue
				}
				global := barsOverrides[k]
				if _, has := Get(m, global); !has {
					set(m, global, v)
					log = append(log, fmt.Sprintf("moved bars[0].%s -> %s", k, global))
				} else {
					log = append(log, fmt.Sprintf("dropped bars[0].%s (%s is already set)", k, global))
				}
				b0[k] = nil // null = follow the global setting
			}
		}
	}

	if pruneUnknown && s != nil {
		for _, is := range s.Validate(m) {
			if is.Level == "warning" {
				del(m, is.Key)
				log = append(log, "removed unknown key "+is.Key)
			}
		}
	}
	return log
}

// MigrateFile migrates path in place. When anything changes it first writes a
// new <path>.bak-YYYYMMDD-HHMMSS[-N] (never overwriting an older backup), then
// replaces the file atomically. A symlinked config is followed, so the link
// stays and its target is updated; the file keeps its permissions.
func MigrateFile(path string, s *Schema, pruneUnknown, dryRun bool, now time.Time) (backup string, log []string, err error) {
	real, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", nil, err
	}
	fi, err := os.Stat(real)
	if err != nil {
		return "", nil, err
	}
	orig, err := os.ReadFile(real)
	if err != nil {
		return "", nil, err
	}
	m, err := Parse(orig)
	if err != nil {
		return "", nil, fmt.Errorf("%s: %w", path, err)
	}
	log = Migrate(m, s, pruneUnknown)
	if len(log) == 0 || dryRun {
		return "", log, nil
	}
	if backup, err = writeBackup(real, orig, now); err != nil {
		return "", nil, fmt.Errorf("backup: %w", err)
	}
	out, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return backup, nil, err
	}
	return backup, log, writeAtomic(real, append(out, '\n'), fi.Mode().Perm())
}

func writeBackup(path string, data []byte, now time.Time) (string, error) {
	base := path + ".bak-" + now.Format("20060102-150405")
	for i := 0; i < 100; i++ {
		name := base
		if i > 0 {
			name = fmt.Sprintf("%s-%d", base, i)
		}
		f, err := os.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
		if errors.Is(err, os.ErrExist) {
			continue
		}
		if err != nil {
			return "", err
		}
		_, werr := f.Write(data)
		if cerr := f.Close(); werr == nil {
			werr = cerr
		}
		return name, werr
	}
	return "", fmt.Errorf("too many backups named %s*", base)
}

// WriteAtomic replaces path via a unique temp file in the same directory.
func WriteAtomic(path string, data []byte, perm os.FileMode) error {
	return writeAtomic(path, data, perm)
}

// writeAtomic replaces path via a unique temp file in the same directory.
func writeAtomic(path string, data []byte, perm os.FileMode) error {
	f, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp) // no-op after a successful rename
	if _, err := f.Write(data); err != nil {
		f.Close()
		return err
	}
	if err := f.Chmod(perm); err != nil {
		f.Close()
		return err
	}
	if err := f.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}
