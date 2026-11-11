.pragma library

// Sway IPC replies → the backend contract (SwayBackend). Field names from
// sway-ipc(7), sway 1.12; tested against the man page's own examples in
// scripts/dev/test-sway-model.js.

// Every window (tiling or floating) under a node, depth first.
function _windows(node, out) {
    for (const child of (node.nodes || []).concat(node.floating_nodes || [])) {
        // A window is a con with no children of its own (an app_id, or an
        // XWayland window id); split containers only hold windows.
        const leaf = (child.type === "con" || child.type === "floating_con")
            && (child.nodes || []).length === 0 && (child.floating_nodes || []).length === 0
        if (leaf) out.push(child)
        else _windows(child, out)
    }
    return out
}

// The visible, real workspaces: [{ output, workspace }] (the scratchpad's
// `__i3` output and `__i3_scratch` workspace are left out).
function _workspaces(tree) {
    const out = []
    for (const output of (tree && tree.nodes) || []) {
        if (output.type !== "output" || output.name === "__i3") continue
        for (const ws of output.nodes || [])
            if (ws.type === "workspace" && ws.name !== "__i3_scratch") out.push({ output: output, workspace: ws })
    }
    return out
}

// Workspace name → true when it holds at least one window.
function occupied(tree) {
    const out = {}
    for (const e of _workspaces(tree))
        if (_windows(e.workspace, []).length > 0) out[e.workspace.name] = true
    return out
}

// Every container under a node (split containers included), depth first.
function _cons(node, out) {
    for (const child of (node.nodes || []).concat(node.floating_nodes || [])) {
        if (child.type === "con" || child.type === "floating_con") out.push(child)
        _cons(child, out)
    }
    return out
}

// Output name → true when the workspace it shows has a fullscreen container
// (fullscreen_mode 1, the workspace, on a window or a parent container); a
// global one (mode 2) covers every output.
function fullscreen(tree) {
    const out = {}
    const all = _workspaces(tree)
    for (const e of all) {
        const shown = e.output.current_workspace === undefined || e.output.current_workspace === e.workspace.name
        const modes = _cons(e.workspace, []).map(c => c.fullscreen_mode || 0)
        if (modes.some(m => m === 2)) { for (const o of all) out[o.output.name] = true; continue }
        if (shown && modes.some(m => m === 1)) out[e.output.name] = true
    }
    return out
}

// [left, top, right, bottom] an output reserves for panels: its shown
// workspace's rect (the usable area) inside the output's rect; null unknown.
function reserved(tree, outputName) {
    const e = _workspaces(tree).find(e => e.output.name === outputName
        && (e.output.current_workspace === undefined || e.output.current_workspace === e.workspace.name))
    const o = e && e.output.rect, w = e && e.workspace.rect
    if (!o || !w) return null
    return [w.x - o.x, w.y - o.y, (o.x + o.width) - (w.x + w.width), (o.y + o.height) - (w.y + w.height)].map(v => Math.max(0, v))
}

// The contract's window list, ids being sway container ids (for `[con_id=…]`).
function windows(tree) {
    const out = []
    for (const e of _workspaces(tree)) {
        const floating = new Set(_windows({ nodes: [], floating_nodes: e.workspace.floating_nodes || [] }, []).map(w => w.id))
        for (const w of _windows(e.workspace, [])) {
            const r = w.rect || {}
            out.push({
                key: String(w.id), id: w.id, title: w.name || "",
                appId: w.app_id || (w.window_properties && w.window_properties.class) || "",
                workspace: e.workspace.num !== undefined && e.workspace.num >= 0 ? e.workspace.num : 0,
                workspaceName: e.workspace.name,
                output: e.output.name, x: r.x || 0, y: r.y || 0, width: r.width || 0, height: r.height || 0,
                focused: !!w.focused, floating: floating.has(w.id), fullscreen: (w.fullscreen_mode || 0) > 0
            })
        }
    }
    return out
}

// { current, names } from GET_INPUTS: the first keyboard that lists its
// layouts, else the first keyboard's active layout alone.
function layouts(inputs) {
    const kbs = (inputs || []).filter(i => i && i.type === "keyboard")
    const full = kbs.find(k => Array.isArray(k.xkb_layout_names) && k.xkb_layout_names.length > 0)
    const k = full || kbs.find(k => k.xkb_active_layout_name) || null
    if (!k) return { current: "", names: [] }
    return { current: k.xkb_active_layout_name || "", names: full ? full.xkb_layout_names.slice() : [] }
}

// An INPUT event (`xkb_layout`, `xkb_keymap`) on a keyboard: the new
// { current, names }, or null when it isn't about layouts.
function layoutsFromEvent(event) {
    if (!event || !event.input || event.input.type !== "keyboard") return null
    if (event.change !== "xkb_layout" && event.change !== "xkb_keymap") return null
    return layouts([event.input])
}
