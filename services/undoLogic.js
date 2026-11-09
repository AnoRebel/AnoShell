.pragma library

// The Undo stack (services/Undo.qml): newest last, at most `max` kept, each
// gone `ttl` ms after it was pushed. Entries are { label, restore, commit?, at }.
// Functions return the new stack plus the entries that dropped out, whose
// commit() the caller runs (a deferred delete happening for real).
// Check: node scripts/dev/test-undo.js

function push(stack, entry, now, max, ttl) {
    const live = expire(stack, now, ttl)
    const all = live.stack.concat([Object.assign({}, entry, { at: now })])
    const cut = Math.max(0, all.length - max)
    return { stack: all.slice(cut), dropped: live.dropped.concat(all.slice(0, cut)) }
}

function expire(stack, now, ttl) {
    return { stack: stack.filter(e => now - e.at < ttl), dropped: stack.filter(e => now - e.at >= ttl) }
}

// The newest live entry, taken off the stack (entry null when none).
function take(stack, now, ttl) {
    const live = expire(stack, now, ttl)
    const s = live.stack
    return { entry: s.length ? s[s.length - 1] : null, stack: s.slice(0, -1), dropped: live.dropped }
}

// Deep equality that ignores object key order (a layout read back from the
// config file may list keys in another order).
function same(a, b) {
    return stable(a) === stable(b)
}
function stable(v) {
    if (Array.isArray(v)) return "[" + v.map(stable).join(",") + "]"
    if (v && typeof v === "object") return "{" + Object.keys(v).sort().map(k => JSON.stringify(k) + ":" + stable(v[k])).join(",") + "}"
    return JSON.stringify(v === undefined ? null : v)
}
