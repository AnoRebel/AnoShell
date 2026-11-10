.pragma library

// `umbriel subscribe` lines → the backend contract (UmbrielBackend). Shapes
// recorded from umbriel 0.1.0 (scripts/dev/fixtures/umbriel), tested in
// scripts/dev/test-umbriel-model.js. Every event carries the whole state of
// its kind: { event: "windows" | "workspaces" | "keyboard_layout" | …, data }.

// One line: { event, data }, or null for a partial or malformed line.
function parse(line) {
    try {
        const o = JSON.parse(line)
        return o && typeof o.event === "string" ? o : null
    } catch (e) { return null }
}

// Workspaces are per output and numbered from 1 (`index`); `focused` is the
// focused one on the focused output, `active` the one each output shows.
function workspaces(list) {
    return (list || []).map(w => ({
        id: w.id, number: w.index || 0, name: w.name || String(w.index || ""), output: w.output || "",
        focused: !!w.focused, active: !!w.active, occupied: !!w.occupied || (w.window_count || 0) > 0,
        urgent: !!w.urgent
    }))
}

function focusedOutput(list) {
    const w = (list || []).find(w => w.focused)
    return w ? w.output || "" : ""
}

// Output name → true for a shown fullscreen window (fullscreen), and for a
// shown fullscreen or edge-to-edge maximised one (covered). `maximized` alone
// is a full-width column, which leaves the bar's strut and gaps.
function fullscreen(windows) {
    const out = {}
    for (const w of windows || []) if (w.visible && w.fullscreen && w.output) out[w.output] = true
    return out
}
function covered(windows) {
    const out = {}
    for (const w of windows || [])
        if (w.visible && (w.fullscreen || w.maximized_to_edges) && w.output) out[w.output] = true
    return out
}

// The contract's window list. Ids are umbriel's (hex strings, for
// `window-focus <id>`); `active` is the focused window (`focused` is only
// the one focused within its workspace). Hidden scratchpad windows are left out.
function windows(list, wsList) {
    const numOf = {}
    for (const ws of wsList || []) numOf[ws.id] = ws.index || 0
    return (list || []).filter(w => !w.scratchpad || w.visible).map(w => ({
        key: String(w.id), id: String(w.id), title: w.title || "", appId: w.app_id || "",
        workspace: numOf[w.workspace] || 0, output: w.output || "",
        x: w.x || 0, y: w.y || 0, width: w.w || 0, height: w.h || 0,
        focused: !!w.active, floating: !!w.floating, fullscreen: !!w.fullscreen
    }))
}

// { current, names } from a keyboard_layout event (full XKB names, "English (US)").
function layouts(data) {
    const names = Array.isArray(data && data.names) ? data.names.slice() : []
    return { current: names[(data && data.current_index) || 0] || "", names: names }
}

// argv for `umbriel msg <action> <args…> [--<opt> <value>…]`, or null when a
// value is empty or would read as a flag (each is one argv word, so nothing
// else needs escaping).
function msg(action, args, opts) {
    const out = ["umbriel", "msg", action].concat((args || []).map(String))
    const values = out.slice(2)
    for (const k of Object.keys(opts || {})) { out.push("--" + k, String(opts[k])); values.push(String(opts[k])) }
    if (values.some(p => p.length === 0 || p.startsWith("-") && !/^-\d/.test(p))) return null
    return out
}

// A window id as umbriel prints it (hex), else false.
function validId(id) { return typeof id === "string" && /^[0-9a-f]{8,64}$/.test(id) }
