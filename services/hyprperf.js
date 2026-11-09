.pragma library
// Hyprland levers of performance mode (services/GameMode.qml): which options
// each switch turns, how `hyprctl getoption` text reads, and the
// `hl.config({ … })` calls that set and restore them. Pure, so it can be
// checked with node: node scripts/dev/test-hyprperf.js

// performance.<key> → Hyprland options and the value they take while it lasts.
var LEVERS = {
    hyprAnimations: { "animations:enabled": false },
    hyprBlur: { "decoration:blur:enabled": false },
    hyprShadows: { "decoration:shadow:enabled": false },
    hyprGaps: { "general:gaps_in": 0, "general:gaps_out": 0 },
    hyprRounding: { "decoration:rounding": 0 },
    hyprTearing: { "general:allow_tearing": true }
}
var DEFAULTS = { hyprAnimations: true, hyprBlur: true, hyprShadows: true, hyprGaps: false, hyprRounding: false, hyprTearing: false }

// perf (Config.options.performance) → { option: value while on } of the switched-on levers.
function wanted(perf) {
    var out = {}
    for (var k in LEVERS) {
        var on = perf && perf[k] !== undefined ? perf[k] === true : DEFAULTS[k]
        if (!on) continue
        for (var o in LEVERS[k]) out[o] = LEVERS[k][o]
    }
    return out
}

// Text of `for o; do echo "@$o"; hyprctl getoption "$o"; done` → { option: value }.
// "bool: true", "int: 3", "float: 1.5", "css gap data: 5 5 5 5" (top right bottom left).
function parse(text) {
    var out = {}, cur = null
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var l = lines[i].trim(), m
        if (l.charAt(0) === "@") { cur = l.slice(1); continue }
        if (!cur || cur in out) continue
        if ((m = l.match(/^bool:\s*(true|false)$/))) out[cur] = m[1] === "true"
        else if ((m = l.match(/^(?:int|float):\s*(-?[\d.]+)$/))) out[cur] = Number(m[1])
        else if ((m = l.match(/^css gap data:\s*(-?\d+)\s+(-?\d+)\s+(-?\d+)\s+(-?\d+)$/)))
            out[cur] = { top: +m[1], right: +m[2], bottom: +m[3], left: +m[4] }
    }
    return out
}

function same(a, b) {
    if (typeof a === "object" && a !== null) {
        if (typeof b === "number") return a.top === b && a.right === b && a.bottom === b && a.left === b
        return typeof b === "object" && b !== null && a.top === b.top && a.right === b.right && a.bottom === b.bottom && a.left === b.left
    }
    if (typeof b === "object" && b !== null) return same(b, a)
    return a === b
}

function lua(v) {
    if (typeof v === "boolean") return v ? "true" : "false"
    if (typeof v === "number" && isFinite(v)) return String(v)
    if (v && typeof v === "object") {
        if (v.top === v.right && v.top === v.bottom && v.top === v.left) return lua(v.top)
        return "{ top = " + lua(v.top) + ", right = " + lua(v.right) + ", bottom = " + lua(v.bottom) + ", left = " + lua(v.left) + " }"
    }
    throw new Error("hyprperf: no Lua for " + JSON.stringify(v))
}

// { "a:b:c": v, … } → 'hl.config({ a = { b = { c = v } } })'; "" for none.
function configCall(values) {
    var tree = {}, n = 0
    for (var opt in values) {
        var parts = opt.split(":"), node = tree
        for (var i = 0; i < parts.length - 1; i++) node = node[parts[i]] = node[parts[i]] || {}
        node[parts[parts.length - 1]] = { leaf: values[opt] }
        n++
    }
    if (n === 0) return ""
    function emit(node) {
        var keys = Object.keys(node).sort()
        return "{ " + keys.map(function (k) {
            var v = node[k]
            return k + " = " + (v && "leaf" in v ? lua(v.leaf) : emit(v))
        }).join(", ") + " }"
    }
    return "hl.config(" + emit(tree) + ")"
}

// What to undo now: options in the snapshot that are no longer wanted.
// → { restore: {option: original}, snapshot: what stays, toRead: wanted options not yet held }
function reconcile(snapshot, want) {
    var restore = {}, keep = {}, toRead = []
    for (var o in snapshot) (o in want ? keep : restore)[o] = snapshot[o]
    for (var w in want) if (!(w in keep)) toRead.push(w)
    return { restore: restore, snapshot: keep, toRead: toRead }
}

// After reading toRead: the ones not already at their performance value get
// remembered (snapshot) and set (apply); the rest are left alone, so restore
// only ever touches what we changed.
function take(snapshot, want, current) {
    var snap = {}, apply = {}
    for (var o in snapshot) snap[o] = snapshot[o]
    for (var c in current) {
        if (!(c in want) || c in snap || same(current[c], want[c])) continue
        snap[c] = current[c]
        apply[c] = want[c]
    }
    return { snapshot: snap, apply: apply }
}
