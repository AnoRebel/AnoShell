.pragma library
// Infinite desktop (services/InfiniteDesktop.qml): the canvas arithmetic, kept
// pure for scripts/dev/test-infinite-model.js. Rects are { id, x, y, width,
// height } in layout coordinates; a window's canvas rect is where it would be
// on screen now (parked ones keep that place in the shell, not the compositor).

function intersects(a, b) {
    return a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
}

// Every window moved by (dx, dy).
function pan(wins, dx, dy) {
    return wins.map(w => Object.assign({}, w, { x: w.x + dx, y: w.y + dy }))
}

// Where each window goes: its canvas place, or parked when it is off `view`
// but would show on another output (Hyprland and sway draw a floating window
// on every output it overlaps), or its centre left `view` for another output
// (sway then moves it to that output's workspace). Parked windows wait past
// every output's right edge. Returns [{ id, x, y, parked }].
function place(wins, view, others) {
    const all = [view].concat(others || [])
    const parkX = Math.max(...all.map(o => o.x + o.width)) + 2000
    return wins.map(w => {
        const c = { x: w.x + w.width / 2, y: w.y + w.height / 2, width: 0.001, height: 0.001 }
        const park = (!intersects(w, view) && (others || []).some(o => intersects(w, o)))
            || (!intersects(c, view) && (others || []).some(o => intersects(c, o)))
        return { id: w.id, x: park ? parkX : Math.round(w.x), y: Math.round(w.y), parked: park }
    })
}

// Only the placements that differ from the last sent ones (by id).
function changed(next, last) {
    const prev = {}
    for (const p of last || []) prev[p.id] = p
    return next.filter(p => !prev[p.id] || prev[p.id].x !== p.x || prev[p.id].y !== p.y)
}

// The pan that brings `r` fully into `view` with `margin` (centred when it
// doesn't fit); { dx, dy } to add to every window.
function follow(r, view, margin) {
    const m = margin || 0
    const axis = (pos, size, vpos, vsize) => {
        if (size + 2 * m > vsize) return vpos + (vsize - size) / 2 - pos
        if (pos < vpos + m) return vpos + m - pos
        if (pos + size > vpos + vsize - m) return vpos + vsize - m - (pos + size)
        return 0
    }
    return { dx: axis(r.x, r.width, view.x, view.width), dy: axis(r.y, r.height, view.y, view.height) }
}

// Top-left that centres a width × height window in `view`.
function centred(view, width, height) {
    return { x: Math.round(view.x + (view.width - width) / 2), y: Math.round(view.y + (view.height - height) / 2) }
}

// Spread the windows out without overlap: rows (tallest first) as wide as a
// block of their total area shaped like the view, the block centred on the
// view. Returns [{ id, x, y }].
function arrange(wins, view, gap) {
    const g = gap ?? 24
    if (!wins.length) return []
    const area = wins.reduce((s, w) => s + (w.width + g) * (w.height + g), 0)
    const widest = Math.max(...wins.map(w => w.width))
    const rowMax = Math.max(widest, Math.sqrt(area * view.width / Math.max(1, view.height)))
    const sorted = wins.slice().sort((a, b) => b.height - a.height || String(a.id).localeCompare(String(b.id)))
    const rows = []
    let row = null
    for (const w of sorted) {
        if (!row || row.width + g + w.width > rowMax) { row = { items: [], width: -g, height: 0 }; rows.push(row) }
        row.items.push(w); row.width += g + w.width; row.height = Math.max(row.height, w.height)
    }
    const blockH = rows.reduce((s, r) => s + r.height, 0) + g * (rows.length - 1)
    let y = view.y + (view.height - blockH) / 2
    const out = []
    for (const r of rows) {
        let x = view.x + (view.width - r.width) / 2
        for (const w of r.items) { out.push({ id: w.id, x: Math.round(x), y: Math.round(y + (r.height - w.height) / 2) }); x += w.width + g }
        y += r.height + g
    }
    return out
}

// Bounding box of the windows and the view, for the overview map.
function bounds(wins, view) {
    const rs = wins.concat([view])
    const x = Math.min(...rs.map(r => r.x)), y = Math.min(...rs.map(r => r.y))
    return { x, y, width: Math.max(...rs.map(r => r.x + r.width)) - x, height: Math.max(...rs.map(r => r.y + r.height)) - y }
}
