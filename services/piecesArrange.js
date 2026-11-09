.pragma library

// Arranging pieces on a page (services/Pieces.qml). A page is a list of
// { uid, x, y, w, h, … } in cells; the grid is cols × rows. Every function
// is pure and deterministic and returns a new page (or null when it can't),
// with no two pieces overlapping and all inside the grid.
// Check: node scripts/dev/test-pieces-arrange.js

function overlap(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}
function inside(r, cols, rows) {
    return r.x >= 0 && r.y >= 0 && r.w >= 1 && r.h >= 1 && r.x + r.w <= cols && r.y + r.h <= rows
}

// The free top-left for a w × h piece nearest to (x, y) (straight-line
// distance; ties go to the upper, then the left one), or null.
function nearestFree(others, w, h, cols, rows, x, y) {
    let best = null, bestD = Infinity
    for (let cy = 0; cy + h <= rows; cy++)
        for (let cx = 0; cx + w <= cols; cx++) {
            const d = (cx - x) * (cx - x) + (cy - y) * (cy - y)
            if (d >= bestD) continue
            const r = { x: cx, y: cy, w, h }
            if (!others.some(o => overlap(o, r))) { best = { x: cx, y: cy }; bestD = d }
        }
    return best
}

function _copy(page) { return Array.from(page, o => Object.assign({}, o)) }

// Moves `uid` to rect, or the free spot nearest to it (a drop on a taken cell).
function drop(page, uid, rect, cols, rows) {
    const items = _copy(page)
    const me = items.find(o => o.uid === uid)
    if (!me) return null
    const spot = nearestFree(items.filter(o => o !== me), rect.w, rect.h, cols, rows, rect.x, rect.y)
    if (!spot) return null
    Object.assign(me, { x: spot.x, y: spot.y, w: rect.w, h: rect.h })
    return items
}

// Puts `uid` at rect and moves whatever it covers out of the way: along dir
// ({ dx, dy }, each -1/0/1) just far enough to clear it, which can push the
// next one on (a chain); a piece that can't go that way (the edge) goes to
// the free spot nearest to where it was. Null when something has nowhere to go.
function push(page, uid, rect, cols, rows, dir) {
    if (!inside(rect, cols, rows)) return null
    const items = _copy(page)
    const me = items.find(o => o.uid === uid)
    if (!me) return null
    Object.assign(me, { x: rect.x, y: rect.y, w: rect.w, h: rect.h })
    const fixed = [me]
    const ahead = o => o.x * dir.dx + o.y * dir.dy
    for (;;) {
        const hit = items.filter(o => !fixed.includes(o) && fixed.some(f => overlap(o, f)))
        if (!hit.length) return items
        // the one nearest the mover in the push direction first; then reading order
        hit.sort((a, b) => ahead(a) - ahead(b) || a.y - b.y || a.x - b.x || (a.uid < b.uid ? -1 : a.uid > b.uid ? 1 : 0))
        const o = hit[0]
        const spot = _shove(o, fixed, dir, cols, rows) ?? nearestFree(items.filter(i => i !== o), o.w, o.h, cols, rows, o.x, o.y)
        if (!spot) return null
        o.x = spot.x; o.y = spot.y
        fixed.push(o)
    }
}
// o shifted along one axis of dir until it clears every fixed piece; the
// shorter of the two axes (x on a tie), null when both run off the grid.
function _shove(o, fixed, dir, cols, rows) {
    let best = null, bestD = Infinity
    for (const axis of ["x", "y"]) {
        const d = axis === "x" ? dir.dx : dir.dy
        if (!d) continue
        const r = { x: o.x, y: o.y, w: o.w, h: o.h }
        let f
        while ((f = fixed.find(g => overlap(g, r))))
            r[axis] = d > 0 ? f[axis] + (axis === "x" ? f.w : f.h) : f[axis] - (axis === "x" ? r.w : r.h)
        if (!inside(r, cols, rows)) continue
        const dist = Math.abs(r[axis] - o[axis])
        if (dist < bestD) { best = { x: r.x, y: r.y }; bestD = dist }
    }
    return best
}

// Resizes `uid` (top-left fixed) to w × h, pushing what it grows into right
// and down. When that doesn't fit, the size nearest the asked one (between it
// and the current) that does: the resize stops at the last size that fits.
function resize(page, uid, w, h, cols, rows) {
    const me = Array.from(page).find(o => o.uid === uid)
    if (!me) return null
    const sw = w >= me.w ? -1 : 1, sh = h >= me.h ? -1 : 1
    let best = null, bestD = Infinity
    for (let cw = w; ; cw += sw) {
        for (let ch = h; ; ch += sh) {
            const d = Math.abs(cw - w) + Math.abs(ch - h)
            if (d < bestD) {
                const dir = { dx: cw > me.w ? 1 : 0, dy: ch > me.h ? 1 : 0 }
                const r = push(page, uid, { x: me.x, y: me.y, w: cw, h: ch }, cols, rows, dir)
                if (r) { best = r; bestD = d }
            }
            if (ch === me.h) break
        }
        if (cw === me.w) break
    }
    return best
}
