.pragma library

// The generic backend's mapping (GenericBackend; sway and labwc build on it):
// ext-workspace windowsets and foreign-toplevel windows → the contract.
// Tested in scripts/dev/test-generic-model.js.

// screens: [{ name, windowsets: [Windowset-like {name, coordinates, shouldDisplay, …}] }]
// → [{ set, output, number }], sorted by number. Coordinates are
// compositor-defined (Hyprland uses the workspace id), so a numeric name
// comes first, then the first coordinate, then the order on its screen.
function sets(screens) {
    const out = []
    for (const screen of screens || []) {
        const shown = (screen.windowsets || []).filter(ws => ws.shouldDisplay !== false)
        shown.forEach((ws, i) => out.push({ set: ws, output: screen.name,
            number: parseInt(ws.name) || (ws.coordinates && ws.coordinates[0]) || i + 1 }))
    }
    return out.sort((x, y) => x.number - y.number)
}

// One contract workspace per entry; occupiedOf(entry) is the backend's say.
function workspaces(entries, focusedOutput, occupiedOf) {
    return (entries || []).map(e => ({
        id: `${e.output}:${e.number}`, number: e.number, name: e.set.name || String(e.number),
        output: e.output, focused: !!e.set.active && e.output === focusedOutput,
        active: !!e.set.active, occupied: !!occupiedOf(e), urgent: !!e.set.urgent
    }))
}

// Output name → true for each output a toplevel matching `pred` is on
// (fullscreen: t => t.fullscreen; covered: also maximised).
function outputsWhere(toplevels, pred) {
    const out = {}
    for (const t of toplevels || [])
        if (t && pred(t)) for (const s of (t.screens || [])) out[s.name] = true
    return out
}
