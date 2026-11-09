.pragma library
// Index math for reordering the dock's pinned apps (the dock's drag and the
// Settings up/down buttons). Check: node scripts/dev/test-dock-reorder.js

// A copy of list with the entry at `from` moved to `to` (clamped).
function move(list, from, to) {
    const out = list.slice()
    if (from < 0 || from >= out.length) return out
    const x = out.splice(from, 1)[0]
    out.splice(Math.max(0, Math.min(to, out.length)), 0, x)
    return out
}

// The slot a dragged entry lands in: `delta` px from its own slot, slots
// `slot` px apart, `count` slots in all.
function target(from, delta, slot, count) {
    if (count <= 0 || slot <= 0) return from
    return Math.max(0, Math.min(count - 1, from + Math.round(delta / slot)))
}

// How far entry i slides to make room while `from` is dragged over `to`.
function shift(i, from, to, slot) {
    if (from < 0 || to < 0 || i === from) return 0
    if (from < to && i > from && i <= to) return -slot
    if (to < from && i >= to && i < from) return slot
    return 0
}
