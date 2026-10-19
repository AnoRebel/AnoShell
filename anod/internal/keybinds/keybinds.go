// Package keybinds is ano's one keybind set: chords mapped to
// compositor-neutral actions (spec keybinds), rendered to Hyprland Lua
// (hl.bind) and niri KDL. Binds that only make sense on one compositor are
// kept as that compositor's native action and rendered only there.
package keybinds

import (
	_ "embed"
	"fmt"
	"sort"
	"strconv"
	"strings"
)

// Bind is one chord → action. Action is a catalogue id (Catalogue), or
// "hyprland"/"niri" for a native action whose Args[0] is the backend's own
// text (a Lua expression, a whole raw `hl.bind(…)` statement when Raw is set,
// or a KDL action).
type Bind struct {
	Chord  string            `json:"chord"`            // canonical: Super+Ctrl+Alt+Shift+Key
	Action string            `json:"action"`           // catalogue id or "hyprland" / "niri"
	Args   []string          `json:"args,omitempty"`   //
	Only   string            `json:"only,omitempty"`   // "" (both), "hyprland" or "niri"
	Locked bool              `json:"locked,omitempty"` // also while the screen is locked
	Hypr   map[string]any    `json:"hyprland,omitempty"`
	Niri   map[string]string `json:"niri,omitempty"`   // extra bind properties (cooldown-ms=…)
	Submap string            `json:"submap,omitempty"` // Hyprland submap
	Raw    bool              `json:"raw,omitempty"`    // Args[0] is a whole hl.bind statement
}

// On reports whether b is generated for the compositor.
func (b Bind) On(comp string) bool {
	if b.Submap != "" && comp != "hyprland" { // submaps are Hyprland's
		return false
	}
	switch {
	case b.Action == "hyprland" || b.Action == "niri":
		return b.Action == comp
	case b.Only != "":
		return b.Only == comp
	}
	a, ok := Catalogue[b.Action]
	if !ok {
		return false
	}
	if comp == "hyprland" {
		return a.Hypr != nil
	}
	return a.Niri != nil
}

// ── Chords ────────────────────────────────────────────────────────────

var modOrder = []string{"Super", "Ctrl", "Alt", "Shift"}

var modNames = map[string]string{
	"super": "Super", "mod": "Super", "win": "Super", "mod4": "Super", "logo": "Super",
	"ctrl": "Ctrl", "control": "Ctrl", "alt": "Alt", "mod1": "Alt", "shift": "Shift",
}

// keyNames canonicalises key names (lower-case lookup) to niri's spelling,
// which is the xkb keysym name.
var keyNames = map[string]string{
	"return": "Return", "enter": "Return", "tab": "Tab", "space": "Space", "escape": "Escape",
	"left": "Left", "right": "Right", "up": "Up", "down": "Down",
	"comma": "Comma", "period": "Period", "slash": "Slash", "grave": "Grave", "minus": "Minus",
	"equal": "Equal", "apostrophe": "Apostrophe", "semicolon": "Semicolon", "backslash": "Backslash",
	"bracketleft": "BracketLeft", "bracketright": "BracketRight", "delete": "Delete", "backspace": "BackSpace",
	"page_up": "Page_Up", "page_down": "Page_Down", "prior": "Page_Up", "next": "Page_Down",
	"home": "Home", "end": "End", "print": "Print", "insert": "Insert",
	"mouse_down": "WheelScrollDown", "mouse_up": "WheelScrollUp",
	"mouse_left": "WheelScrollLeft", "mouse_right": "WheelScrollRight",
	"wheelscrolldown": "WheelScrollDown", "wheelscrollup": "WheelScrollUp",
	"wheelscrollleft": "WheelScrollLeft", "wheelscrollright": "WheelScrollRight",
}

// xf86Keys are the common XF86 keysyms, for spellings like "xf86audiomute"
// (Hyprland matches keys case-insensitively; niri wants the exact name).
var xf86Keys = []string{"AudioRaiseVolume", "AudioLowerVolume", "AudioMute", "AudioMicMute", "AudioPlay", "AudioPause", "AudioNext", "AudioPrev", "AudioStop", "AudioMedia", "MonBrightnessUp", "MonBrightnessDown", "KbdBrightnessUp", "KbdBrightnessDown", "KbdLightOnOff", "TouchpadToggle", "Close", "WLAN", "Calculator", "Explorer", "Search", "Mail", "PowerOff", "Sleep", "Display", "Tools", "Favorites"}

func init() {
	for _, k := range xf86Keys {
		keyNames["xf86"+strings.ToLower(k)] = "XF86" + k
	}
}

// hyprKeys spells canonical keys the way Hyprland binds them, where it differs.
var hyprKeys = map[string]string{
	"WheelScrollDown": "mouse_down", "WheelScrollUp": "mouse_up",
	"WheelScrollLeft": "mouse_left", "WheelScrollRight": "mouse_right",
}

func canonKey(k string) string {
	if v, ok := keyNames[strings.ToLower(k)]; ok {
		return v
	}
	if len(k) == 1 {
		return strings.ToUpper(k)
	}
	if strings.HasPrefix(strings.ToLower(k), "f") && len(k) <= 3 {
		if _, err := strconv.Atoi(k[1:]); err == nil {
			return "F" + k[1:]
		}
	}
	return k
}

// NormalizeChord turns "SUPER + SHIFT + left", "Mod+Shift+Left" or
// "SUPER, T" into "Super+Shift+Left".
func NormalizeChord(c string) string {
	c = strings.ReplaceAll(c, ",", "+")
	var mods = map[string]bool{}
	var keys []string
	for _, p := range strings.Split(c, "+") {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		if m, ok := modNames[strings.ToLower(p)]; ok {
			mods[m] = true
			continue
		}
		keys = append(keys, canonKey(p))
	}
	var out []string
	for _, m := range modOrder {
		if mods[m] {
			out = append(out, m)
		}
	}
	return strings.Join(append(out, keys...), "+")
}

func hyprChord(c string) string {
	parts := strings.Split(c, "+")
	for i, p := range parts {
		switch {
		case i < len(parts)-1:
			parts[i] = strings.ToUpper(p)
		case hyprKeys[p] != "":
			parts[i] = hyprKeys[p]
		}
	}
	return strings.Join(parts, " + ")
}

func niriChord(c string) string {
	if c == "Super" || strings.HasPrefix(c, "Super+") {
		return "Mod" + c[len("Super"):]
	}
	return c
}

// ── Catalogue ─────────────────────────────────────────────────────────

// Action renders one neutral action per backend; nil = not available there.
type Action struct {
	Label string
	Hypr  func(args []string) string // Lua expression for hl.bind's second argument
	Niri  func(args []string) string // KDL action (inside the bind's braces, no ';')
}

func lit(s string) func([]string) string { return func([]string) string { return s } }

// arg returns args[i] or "".
func arg(a []string, i int) string {
	if i < len(a) {
		return a[i]
	}
	return ""
}

var dirs = map[string][2]string{ // direction → niri focus / move action
	"left":  {"focus-column-left", "move-column-left"},
	"right": {"focus-column-right", "move-column-right"},
	"up":    {"focus-window-or-workspace-up", "move-window-up-or-to-workspace-up"},
	"down":  {"focus-window-or-workspace-down", "move-window-down-or-to-workspace-down"},
}

// Catalogue is every neutral action. Ids are stable: they are what the
// user's keybinds.json refers to.
var Catalogue = map[string]Action{
	"exec": {Label: "Run a command",
		Hypr: func(a []string) string { return "hl.dsp.exec_cmd(" + luaStr(arg(a, 0)) + ")" },
		Niri: func(a []string) string { return "spawn-sh " + kdlStr(arg(a, 0)) }},
	"shell": {Label: "Shell action (qs ipc)",
		Hypr: func(a []string) string { return "hl.dsp.exec_cmd(" + luaStr(qsIPC(a)) + ")" },
		Niri: func(a []string) string { return "spawn-sh " + kdlStr(qsIPC(a)) }},
	"window.close":      {Label: "Close window", Hypr: lit("hl.dsp.window.close()"), Niri: lit("close-window")},
	"window.fullscreen": {Label: "Fullscreen", Hypr: lit(`hl.dsp.window.fullscreen({ action = "toggle" })`), Niri: lit("fullscreen-window")},
	"window.float":      {Label: "Toggle floating", Hypr: lit(`hl.dsp.window.float({ action = "toggle" })`), Niri: lit("toggle-window-floating")},
	"window.center":     {Label: "Center window", Hypr: lit("hl.dsp.window.center()"), Niri: lit("center-column")},
	"session.quit":      {Label: "Quit the compositor", Hypr: lit(`hl.dsp.exec_cmd("hyprshutdown")`), Niri: lit("quit")},
	"workspace.focus": {Label: "Go to workspace",
		Hypr: func(a []string) string { return "hl.dsp.focus({ workspace = " + arg(a, 0) + " })" },
		Niri: func(a []string) string { return "focus-workspace " + arg(a, 0) }},
	// Relative workspace, in Hyprland's notation (e+1, r-1, +1 …): niri goes down for +, up for −.
	"workspace.relative": {Label: "Next / previous workspace",
		Hypr: func(a []string) string { return "hl.dsp.focus({ workspace = " + luaStr(arg(a, 0)) + " })" },
		Niri: func(a []string) string {
			if strings.Contains(arg(a, 0), "-") {
				return "focus-workspace-up"
			}
			return "focus-workspace-down"
		}},
	"window.toWorkspace": {Label: "Move window to workspace",
		Hypr: func(a []string) string { return "hl.dsp.window.move({ workspace = " + arg(a, 0) + " })" },
		Niri: func(a []string) string { return "move-column-to-workspace " + arg(a, 0) }},
	"window.toWorkspaceSilent": {Label: "Send window to workspace",
		Hypr: func(a []string) string {
			return "hl.dsp.window.move({ follow = false, workspace = " + arg(a, 0) + " })"
		},
		Niri: func(a []string) string { return "move-column-to-workspace " + arg(a, 0) + " focus=false" }},
}

func init() {
	for d, n := range dirs {
		d, n := d, n
		Catalogue["focus."+d] = Action{Label: "Focus " + d, Hypr: lit(`hl.dsp.focus({ direction = "` + d + `" })`), Niri: lit(n[0])}
		Catalogue["window.move."+d] = Action{Label: "Move window " + d, Hypr: lit(`hl.dsp.window.move({ direction = "` + d + `" })`), Niri: lit(n[1])}
	}
}

// qsIPC is the shell IPC command line for a "shell" action's args (target, method, args…).
func qsIPC(a []string) string {
	return strings.Join(append([]string{"qs", "-c", "ano", "ipc", "call"}, a...), " ")
}

// ── Rendering ─────────────────────────────────────────────────────────

func luaStr(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch r {
		case '"', '\\':
			b.WriteByte('\\')
			b.WriteRune(r)
		case '\n':
			b.WriteString(`\n`)
		case '\t':
			b.WriteString(`\t`)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
	return b.String()
}

func kdlStr(s string) string { return luaStr(s) } // KDL strings escape the same characters

// luaValue renders a decoded JSON value as a Lua literal (sorted keys).
func luaValue(v any) string {
	switch t := v.(type) {
	case string:
		return luaStr(t)
	case bool:
		return strconv.FormatBool(t)
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	case nil:
		return "nil"
	case []any:
		if len(t) == 0 {
			return "{}"
		}
		parts := make([]string, len(t))
		for i, x := range t {
			parts[i] = luaValue(x)
		}
		return "{ " + strings.Join(parts, ", ") + " }"
	case map[string]any:
		if len(t) == 0 {
			return "{}"
		}
		keys := make([]string, 0, len(t))
		for k := range t {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		parts := make([]string, len(keys))
		for i, k := range keys {
			parts[i] = k + " = " + luaValue(t[k])
		}
		return "{ " + strings.Join(parts, ", ") + " }"
	}
	return fmt.Sprint(v)
}

// hyprOpts is hl.bind's third argument ("" when there is none).
func (b Bind) hyprOpts() string {
	o := map[string]any{}
	for k, v := range b.Hypr {
		o[k] = v
	}
	if b.Locked {
		o["locked"] = true
	}
	if len(o) == 0 {
		return ""
	}
	return luaValue(o)
}

// HyprlandLua renders the binds that apply on Hyprland as a Lua chunk to be
// dofile'd. helpers is Lua source placed first (locals the raw binds use).
func HyprlandLua(binds []Bind, helpers string) string {
	var b strings.Builder
	b.WriteString("-- Generated by anod from your keybinds (ano keybinds). Do not edit: change\n-- them in Settings → Keybinds or ~/.config/anoshell/keybinds.json.\n\n")
	if helpers != "" {
		b.WriteString(helpers)
		b.WriteString("\n")
	}
	bySubmap := map[string][]Bind{}
	var order []string
	for _, x := range binds {
		if !x.On("hyprland") {
			continue
		}
		if _, ok := bySubmap[x.Submap]; !ok {
			order = append(order, x.Submap)
		}
		bySubmap[x.Submap] = append(bySubmap[x.Submap], x)
	}
	for _, sm := range order {
		indent := ""
		if sm != "" {
			b.WriteString("\nhl.define_submap(" + luaStr(sm) + ", function()\n")
			indent = "\t"
		}
		for _, x := range bySubmap[sm] {
			b.WriteString(indent + hyprLine(x) + "\n")
		}
		if sm != "" {
			b.WriteString("end)\n")
		}
	}
	return b.String()
}

func hyprLine(x Bind) string {
	if x.Raw {
		return arg(x.Args, 0)
	}
	expr := arg(x.Args, 0)
	if a, ok := Catalogue[x.Action]; ok {
		expr = a.Hypr(x.Args)
	}
	line := "hl.bind(" + luaStr(hyprChord(x.Chord)) + ", " + expr
	if o := x.hyprOpts(); o != "" {
		line += ", " + o
	}
	return line + ")"
}

// NiriKDL renders the binds that apply on niri as a `binds {}` block.
func NiriKDL(binds []Bind) string {
	var b strings.Builder
	b.WriteString("// Generated by anod from your keybinds (ano keybinds). Do not edit: change\n// them in Settings → Keybinds or ~/.config/anoshell/keybinds.json.\nbinds {\n")
	seen := map[string]bool{}
	for _, x := range binds {
		// niri allows one bind per chord (Hyprland runs them all): the first wins.
		if !x.On("niri") || seen[x.Chord] {
			continue
		}
		seen[x.Chord] = true
		b.WriteString("    " + niriLine(x) + "\n")
	}
	b.WriteString("}\n")
	return b.String()
}

func niriLine(x Bind) string {
	act := arg(x.Args, 0)
	if a, ok := Catalogue[x.Action]; ok {
		act = a.Niri(x.Args)
	}
	props := ""
	keys := make([]string, 0, len(x.Niri))
	for k := range x.Niri {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		props += " " + k + "=" + x.Niri[k]
	}
	if x.Locked && strings.HasPrefix(act, "spawn") { // niri allows it on spawn binds only
		props += " allow-when-locked=true"
	}
	return niriChord(x.Chord) + props + " { " + act + "; }"
}
