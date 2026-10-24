.pragma library

// Mango IPC replies → the backend contract (MangoBackend). Field names from
// mango 0.18.3 src/ipc/ipc.c (build_monitor_json, build_tags_json,
// build_client_json); tested in scripts/dev/test-mango-model.js.

// One line from `get`/`watch all-monitors` or `all-clients`: the parsed object,
// or null for a partial or malformed line.
function parse(line) {
    try { return JSON.parse(line) } catch (e) { return null }
}

// Tags are per monitor and numbered from 1 (several can be shown at once).
function workspaces(monitors) {
    const out = []
    for (const m of monitors || []) {
        for (const t of m.tags || []) {
            out.push({
                id: `${m.name}:${t.index}`, number: t.index, name: String(t.index), output: m.name,
                focused: !!t.is_active && !!m.active, active: !!t.is_active,
                occupied: (t.client_count || 0) > 0, urgent: !!t.is_urgent
            })
        }
    }
    return out
}

// The selected monitor (`active` in mango's terms).
function focusedOutput(monitors) {
    const m = (monitors || []).find(m => m.active)
    return m ? m.name : ""
}

// The active XKB layout as mango reports it: its full name
// (xkb_keymap_layout_get_name, e.g. "English (US)").
function keyboardLayout(monitors) {
    const m = (monitors || []).find(m => m.active) || (monitors || [])[0]
    return m && m.keyboardlayout ? m.keyboardlayout : ""
}

// Monitor name → true for a visible fullscreen client (fullscreen), and for
// a visible fullscreen or maximised one (covered).
function fullscreen(clients) {
    const out = {}
    for (const c of clients || []) if (c.is_visible && c.is_fullscreen && c.monitor) out[c.monitor] = true
    return out
}
function covered(clients) {
    const out = {}
    for (const c of clients || [])
        if (c.is_visible && (c.is_fullscreen || c.is_maximized) && c.monitor) out[c.monitor] = true
    return out
}

// The contract's window list; ids are mango client ids (`client,<id>`).
// A window has one workspace in the contract: a shown one reports the tag
// its monitor shows first (the one the shell treats as active there), so a
// window on the second of two shown tags isn't left out of that output.
function windows(clients, monitors) {
    const shownTag = {}
    for (const m of monitors || []) {
        const t = (m.tags || []).find(t => t.is_active)
        if (t) shownTag[m.name] = t.index
    }
    return (clients || []).filter(c => !c.is_scratchpad || c.is_visible).map(c => ({
        key: String(c.id), id: c.id, title: c.title || "", appId: c.appid || "",
        workspace: (c.is_visible && shownTag[c.monitor]) || (c.tags || []).find(t => t > 0) || 0,
        output: c.monitor || "",
        x: c.x || 0, y: c.y || 0, width: c.width || 0, height: c.height || 0,
        focused: !!c.is_focused, floating: !!c.is_floating, fullscreen: !!c.is_fullscreen
    }))
}

// A dispatch line (`dispatch <func>,<args…> [client,<id>]`). Arguments are
// numbers or monitor names here; anything with a newline, comma or space
// would split the command, so it is refused (null).
function dispatchLine(func, args, clientId) {
    const parts = [func].concat((args || []).map(String))
    if (parts.some(p => p.length === 0 || /[\s,]/.test(p))) return null
    let line = "dispatch " + parts.join(",")
    if (clientId !== undefined && clientId !== null) {
        if (!Number.isInteger(clientId) || clientId <= 0) return null
        line += " client," + clientId
    }
    return line + "\n"
}
