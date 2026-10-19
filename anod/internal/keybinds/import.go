package keybinds

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

//go:embed stub.lua
var stubLua []byte

// hyprRecord is one hl.bind call as stub.lua records it.
type hyprRecord struct {
	Chord  string         `json:"chord"`
	Action any            `json:"action"`
	Opts   map[string]any `json:"opts"`
	Submap string         `json:"submap"`
	Line   int            `json:"line"`
	File   string         `json:"file"`
}

// ReadHyprland runs a Hyprland Lua config (and what it requires) against a
// recording hl and returns its binds, in order. Needs `lua` (dev tool).
func ReadHyprland(path string) ([]Bind, error) {
	out, err := runStub(path)
	if err != nil {
		return nil, err
	}
	var recs []hyprRecord
	if err := json.Unmarshal(out, &recs); err != nil {
		return nil, err
	}
	return recordsToBinds(recs), nil
}

// recordsToBinds converts stub records, reading raw binds' source text.
func recordsToBinds(recs []hyprRecord) []Bind {
	src := map[string][]string{}
	binds := make([]Bind, 0, len(recs))
	for _, r := range recs {
		b := fromHypr(r)
		if b.Raw { // a Lua function: keep the call site's source
			lines, ok := src[r.File]
			if !ok {
				data, _ := os.ReadFile(r.File)
				lines = strings.Split(string(data), "\n")
				src[r.File] = lines
			}
			b.Args = []string{statementAt(lines, r.Line)}
		}
		binds = append(binds, b)
	}
	return binds
}

// runStub runs path under stub.lua and returns its JSON.
func runStub(path string) ([]byte, error) {
	cmd := exec.Command("lua", "-", path)
	cmd.Stdin = bytes.NewReader(stubLua)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("lua %s: %v: %s", path, err, stderr.String())
	}
	return out, nil
}

// statementAt returns the source of the hl.bind(…) call the stub reported
// at line (1-based), found with strings and comments masked out.
func statementAt(lines []string, line int) string {
	code := strings.Split(maskLua(strings.Join(lines, "\n")), "\n")
	start, end, err := statementRange(code, line)
	if err != nil {
		if line >= 1 && line <= len(lines) {
			return strings.TrimSpace(lines[line-1])
		}
		return ""
	}
	return strings.TrimSpace(strings.Join(lines[start:end+1], "\n"))
}

func num(v any) (string, bool) {
	if f, ok := v.(float64); ok && f == float64(int(f)) {
		return strconv.Itoa(int(f)), true
	}
	return "", false
}

var qsIPCRE = regexp.MustCompile(`^qs -c ano ipc call ([A-Za-z0-9_]+(?: [A-Za-z0-9_.-]+)*)$`)

// execAction maps a command line to a neutral action.
func execAction(cmd string) (string, []string) {
	if m := qsIPCRE.FindStringSubmatch(cmd); m != nil {
		return "shell", strings.Fields(m[1])
	}
	if cmd == "hyprshutdown" {
		return "session.quit", nil
	}
	return "exec", []string{cmd}
}

func fromHypr(r hyprRecord) Bind {
	b := Bind{Chord: NormalizeChord(r.Chord), Submap: r.Submap, Hypr: map[string]any{}}
	for k, v := range r.Opts {
		if k == "locked" && v == true {
			b.Locked = true
			continue
		}
		b.Hypr[k] = v
	}
	if len(b.Hypr) == 0 {
		b.Hypr = nil
	}
	act, _ := r.Action.(map[string]any)
	if _, isFn := act["__function"]; isFn || act == nil {
		b.Action, b.Raw = "hyprland", true
		return b
	}
	dsp, _ := act["__dsp"].(string)
	args, _ := act["__args"].([]any)
	a0 := any(nil)
	if len(args) > 0 {
		a0 = args[0]
	}
	tbl, _ := a0.(map[string]any)
	only := func(keys ...string) bool {
		if len(tbl) != len(keys) {
			return false
		}
		for _, k := range keys {
			if _, ok := tbl[k]; !ok {
				return false
			}
		}
		return true
	}
	switch {
	case dsp == "dsp.exec_cmd" && len(args) == 1:
		if s, ok := a0.(string); ok {
			b.Action, b.Args = execAction(s)
			return b
		}
	case dsp == "dsp.window.close" && len(args) == 0:
		b.Action = "window.close"
		return b
	case dsp == "dsp.window.center" && len(args) == 0:
		b.Action = "window.center"
		return b
	case dsp == "dsp.window.fullscreen" && only("action") && tbl["action"] == "toggle":
		b.Action = "window.fullscreen"
		return b
	case dsp == "dsp.window.float" && only("action") && tbl["action"] == "toggle":
		b.Action = "window.float"
		return b
	case dsp == "dsp.focus" && only("direction"):
		if d, ok := tbl["direction"].(string); ok && dirs[d] != [2]string{} {
			b.Action = "focus." + d
			return b
		}
	case dsp == "dsp.window.move" && only("direction"):
		if d, ok := tbl["direction"].(string); ok && dirs[d] != [2]string{} {
			b.Action = "window.move." + d
			return b
		}
	case dsp == "dsp.focus" && only("workspace"):
		if n, ok := num(tbl["workspace"]); ok {
			b.Action, b.Args = "workspace.focus", []string{n}
			return b
		}
		if s, ok := tbl["workspace"].(string); ok && regexp.MustCompile(`^[er]?[+-]1$`).MatchString(s) {
			b.Action, b.Args = "workspace.relative", []string{s}
			return b
		}
	case dsp == "dsp.window.move" && only("workspace"):
		if n, ok := num(tbl["workspace"]); ok {
			b.Action, b.Args = "window.toWorkspace", []string{n}
			return b
		}
	case dsp == "dsp.window.move" && only("workspace", "follow") && tbl["follow"] == false:
		if n, ok := num(tbl["workspace"]); ok {
			b.Action, b.Args = "window.toWorkspaceSilent", []string{n}
			return b
		}
	}
	// Anything else stays a Hyprland-only action, rebuilt as the same Lua call.
	parts := make([]string, len(args))
	for i, x := range args {
		parts[i] = luaValue(x)
	}
	b.Action, b.Args = "hyprland", []string{"hl." + dsp + "(" + strings.Join(parts, ", ") + ")"}
	return b
}

// ── niri ──────────────────────────────────────────────────────────────

var (
	niriBindRE  = regexp.MustCompile(`^\s*([A-Za-z0-9_+]+)((?:\s+[a-z-]+=(?:"[^"]*"|\S+?))*)\s*\{\s*(.*?);?\s*\}\s*$`)
	niriPropRE  = regexp.MustCompile(`([a-z-]+)=("[^"]*"|\S+)`)
	niriTokenRE = regexp.MustCompile(`"((?:[^"\\]|\\.)*)"|(\S+)`)
)

// ReadNiri returns the binds of a niri config's `binds {}` block(s).
func ReadNiri(path string) ([]Bind, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var out []Bind
	in := false
	for i, line := range strings.Split(string(data), "\n") {
		t := strings.TrimSpace(line)
		if c := strings.Index(t, "//"); c == 0 {
			continue
		}
		switch {
		case !in && regexp.MustCompile(`^binds\s*\{`).MatchString(t):
			in = true
		case in && t == "}":
			in = false
		case in && t != "":
			m := niriBindRE.FindStringSubmatch(t)
			if m == nil {
				return nil, fmt.Errorf("%s:%d: can't read bind %q", path, i+1, t)
			}
			out = append(out, fromNiri(m[1], m[2], strings.TrimSuffix(strings.TrimSpace(m[3]), ";")))
		}
	}
	return out, nil
}

func unquote(tok []string) string {
	if tok[1] != "" || strings.HasPrefix(tok[0], `"`) {
		s, err := strconv.Unquote(`"` + tok[1] + `"`)
		if err == nil {
			return s
		}
		return tok[1]
	}
	return tok[2]
}

var niriNeutral = map[string]string{
	"close-window": "window.close", "fullscreen-window": "window.fullscreen",
	"toggle-window-floating": "window.float", "center-column": "window.center", "quit": "session.quit",
	"focus-workspace-down": "workspace.relative:e+1", "focus-workspace-up": "workspace.relative:e-1",
}

func fromNiri(chord, props, act string) Bind {
	b := Bind{Chord: NormalizeChord(chord)}
	for _, p := range niriPropRE.FindAllStringSubmatch(props, -1) {
		if p[1] == "allow-when-locked" && p[2] == "true" {
			b.Locked = true
			continue
		}
		if b.Niri == nil {
			b.Niri = map[string]string{}
		}
		b.Niri[p[1]] = p[2]
	}
	toks := niriTokenRE.FindAllStringSubmatch(act, -1)
	name := ""
	if len(toks) > 0 {
		name = unquote(toks[0])
	}
	words := make([]string, 0, len(toks))
	for _, t := range toks[1:] {
		words = append(words, unquote(t))
	}
	switch {
	case name == "spawn-sh" && len(words) == 1:
		b.Action, b.Args = execAction(words[0])
		return b
	case name == "spawn" && len(words) > 0:
		b.Action, b.Args = execAction(shellJoin(words))
		return b
	case niriNeutral[name] != "" && len(words) == 0:
		id, a, _ := strings.Cut(niriNeutral[name], ":")
		b.Action = id
		if a != "" {
			b.Args = []string{a}
		}
		return b
	case name == "focus-workspace" && len(words) == 1:
		b.Action, b.Args = "workspace.focus", words
		return b
	case name == "move-column-to-workspace" && len(words) == 1:
		b.Action, b.Args = "window.toWorkspace", words
		return b
	case name == "move-column-to-workspace" && len(words) == 2 && words[1] == "focus=false":
		b.Action, b.Args = "window.toWorkspaceSilent", words[:1]
		return b
	}
	for d, n := range dirs {
		if len(words) == 0 && name == n[0] {
			b.Action = "focus." + d
			return b
		}
		if len(words) == 0 && name == n[1] {
			b.Action = "window.move." + d
			return b
		}
	}
	b.Action, b.Args = "niri", []string{act}
	return b
}

// shellJoin quotes argv for sh where needed.
func shellJoin(argv []string) string {
	out := make([]string, len(argv))
	for i, a := range argv {
		if a != "" && !strings.ContainsAny(a, " \t\n'\"\\$`!*?[]{}()<>|&;#~") {
			out[i] = a
		} else {
			out[i] = "'" + strings.ReplaceAll(a, "'", `'\''`) + "'"
		}
	}
	return strings.Join(out, " ")
}

// ── Merge ─────────────────────────────────────────────────────────────

// Key identifies a bind's chord within its submap.
func (b Bind) Key() string { return b.Submap + "\x00" + b.Chord }

// Same reports whether two binds do the same thing.
func Same(a, b Bind) bool {
	return a.Action == b.Action && strings.Join(a.Args, "\x00") == strings.Join(b.Args, "\x00")
}

// Conflict is one chord the two compositor sets disagree on.
type Conflict struct {
	Chord    string `json:"chord"`
	Hyprland string `json:"hyprland"`
	Niri     string `json:"niri"`
	Outcome  string `json:"outcome"`
}

// Describe is a one-line summary of a bind's action.
func (b Bind) Describe() string {
	if b.Raw {
		return "Lua function (kept as written)"
	}
	if len(b.Args) == 0 {
		return b.Action
	}
	return b.Action + " " + strings.Join(b.Args, " ")
}

// Merge builds the default set: Hyprland's binds, plus niri's. Where both
// bind a chord to different things and both would be generated on the same
// compositor, Hyprland's wins (spec keybinds) and the clash is reported;
// a niri-only action on a chord Hyprland gives a Hyprland-only action
// coexists (they never meet).
func Merge(hypr, niri []Bind) (out []Bind, conflicts []Conflict) {
	out = append(out, hypr...)
	hByKey := map[string][]int{}
	for i, b := range hypr {
		hByKey[b.Key()] = append(hByKey[b.Key()], i)
	}
	for _, n := range niri {
		idx := hByKey[n.Key()]
		if len(idx) == 0 {
			out = append(out, n)
			continue
		}
		same := false
		for _, i := range idx {
			if Same(out[i], n) {
				same = true
				if n.Niri != nil { // niri's extra properties ride along
					out[i].Niri = n.Niri
				}
				if n.Locked {
					out[i].Locked = true
				}
			}
		}
		if same {
			continue
		}
		var hd []string
		hOnNiri := false
		for _, i := range idx {
			hd = append(hd, out[i].Describe())
			if out[i].On("niri") {
				hOnNiri = true
			}
		}
		c := Conflict{Chord: n.Chord, Hyprland: strings.Join(hd, " ; "), Niri: n.Describe()}
		switch {
		case hOnNiri:
			c.Outcome = "Hyprland's bind wins on both"
		default:
			// Hyprland's action is Hyprland-only, so niri keeps its own there.
			n.Only = "niri"
			out = append(out, n)
			c.Outcome = "each compositor keeps its own"
		}
		conflicts = append(conflicts, c)
	}
	sort.SliceStable(conflicts, func(i, j int) bool { return conflicts[i].Chord < conflicts[j].Chord })
	return out, conflicts
}

// ── Helpers for raw binds ─────────────────────────────────────────────

var localRE = regexp.MustCompile(`^local (?:function )?([A-Za-z_][A-Za-z0-9_]*)`)

// Helpers returns the top-level locals of a Lua source (in source order) that
// the raw binds use, directly or through each other, so the generated file
// can define them (a dofile'd chunk doesn't see the config's locals).
func Helpers(src string, binds []Bind) string {
	lines := strings.Split(src, "\n")
	type def struct {
		name string
		text string
	}
	var defs []def
	for i := 0; i < len(lines); i++ {
		m := localRE.FindStringSubmatch(lines[i])
		if m == nil {
			continue
		}
		j := i
		if strings.HasPrefix(lines[i], "local function ") || strings.HasSuffix(strings.TrimSpace(lines[i]), "{") {
			for j = i + 1; j < len(lines); j++ { // to the closing line at column 0
				if strings.HasPrefix(lines[j], "end") || strings.HasPrefix(lines[j], "}") {
					break
				}
			}
		}
		defs = append(defs, def{m[1], strings.Join(lines[i:min(j+1, len(lines))], "\n")})
		i = j
	}
	need := map[string]bool{}
	var scan func(text string)
	scan = func(text string) {
		for _, d := range defs {
			if !need[d.name] && regexp.MustCompile(`\b`+d.name+`\b`).MatchString(text) {
				need[d.name] = true
				scan(d.text)
			}
		}
	}
	for _, b := range binds {
		if b.Raw {
			scan(arg(b.Args, 0))
		}
	}
	var out []string
	for _, d := range defs {
		if need[d.name] {
			out = append(out, d.text)
		}
	}
	return strings.Join(out, "\n\n")
}
