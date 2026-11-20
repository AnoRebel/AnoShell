.pragma library

// The desktop pet's logic: colour presets, poses, the behaviours it picks, floors and the fall. Pure functions, checked
// by scripts/dev/test-pet.js. Coordinates are px in the usable area (the screen less the bars); a pet stands with its
// feet at (x, y). Poses are in rig units (the rig is 100 × 100, feet at the bottom middle).

const KINDS = ["duck", "cat", "dog"]
const CALLS = { duck: "Quack!", cat: "Meow", dog: "Woof!" }
const SOUNDS = { duck: "pet-quack", cat: "pet-meow", dog: "pet-bark" }

// Natural colours per kind: they don't follow the theme.
const PRESETS = {
    duck: {
        white:   { label: "White",   body: "#f6f3ec", wing: "#e4ded1", head: "#f6f3ec", bill: "#f3a73b", legs: "#f08d2e", ring: "",        patch: "" },
        mallard: { label: "Mallard", body: "#a89f8f", wing: "#776d60", head: "#1f6e4b", bill: "#e9c63c", legs: "#f08d2e", ring: "#f5f3ee", patch: "#3b5cb8" },
        apricot: { label: "Apricot", body: "#f1c79a", wing: "#e2ad78", head: "#f1c79a", bill: "#e7a63f", legs: "#ea8a35", ring: "",        patch: "" }
    },
    cat: {
        tabby:  { label: "Tabby",  base: "#cf9150", belly: "#f2dcbc", mark: "#8c5527", mark2: "",        pattern: "stripes", eye: "#79b452", nose: "#e48c8c" },
        black:  { label: "Black",  base: "#28282d", belly: "#36363c", mark: "",        mark2: "",        pattern: "none",    eye: "#e9c63c", nose: "#4e3c3c" },
        calico: { label: "Calico", base: "#f6f1e7", belly: "#fcfaf5", mark: "#dc8c3e", mark2: "#2e2b2b", pattern: "patches", eye: "#c9a23a", nose: "#e9a0a0" }
    },
    dog: {
        golden: { label: "Golden",          base: "#dba55c", belly: "#f1d4a2", ear: "#bb823d", mark: "",        pattern: "none", nose: "#2b2b2b" },
        tuxedo: { label: "Black and white", base: "#2b2b30", belly: "#f4f3f0", ear: "#202024", mark: "#f4f3f0", pattern: "tux",  nose: "#1b1b1b" },
        brown:  { label: "Brown",           base: "#7c502e", belly: "#ab7b51", ear: "#5e3c21", mark: "",        pattern: "none", nose: "#231a14" }
    }
}
const DEFAULT_PRESET = { duck: "white", cat: "tabby", dog: "golden" }

function kindOf(k) { return KINDS.includes(k) ? k : "duck" }
function presetOf(kind, name) {
    kind = kindOf(kind)
    return PRESETS[kind][name] ?? PRESETS[kind][DEFAULT_PRESET[kind]]
}
function presetNames(kind) { return Object.keys(PRESETS[kindOf(kind)]) }

// Where the head is in the rig's 100 × 100 space facing right: [x1, y1, x2, y2]; and the body's box (the input area).
const HEADS = { duck: [57, 14, 97, 46], cat: [62, 21, 99, 58], dog: [60, 22, 100, 58] }
const BODY = [12, 14, 100, 100]
// Is a press at (lx, ly) px in a pet box of `size` px, facing `facing`, on its head?
function onHead(kind, lx, ly, size, facing) {
    const u = 100 / size, x = facing < 0 ? 100 - lx * u : lx * u, y = ly * u
    const h = HEADS[kindOf(kind)]
    return x >= h[0] && x <= h[2] && y >= h[1] && y <= h[3]
}
// The body box in px for a pet box of `size` px: { x, y, w, h }.
function bodyBox(size, facing) {
    const k = size / 100
    return { x: (facing < 0 ? 100 - BODY[2] : BODY[0]) * k, y: BODY[1] * k, w: (BODY[2] - BODY[0]) * k, h: (BODY[3] - BODY[1]) * k }
}

// ── Behaviours ─────────────────────────────────────────────────────────────
// [name, weight, [min s, max s]]; walk ends when it arrives.
const COMMON = [["idle", 30, [2, 5]], ["walk", 26, [0, 0]], ["sit", 12, [4, 9]], ["groom", 7, [3, 6]],
                ["stretch", 5, [2.4, 2.4]], ["look", 10, [3, 6]], ["call", 4, [1.3, 1.3]]]
const OWN = {
    duck: [["preen", 8, [3, 5]], ["peck", 9, [2, 4]]],
    cat:  [["knead", 7, [3, 6]], ["flick", 8, [2, 4]]],
    dog:  [["sniff", 9, [3, 6]], ["wag", 9, [2, 4]]]
}
const SLEEP_AFTER = 180 // s without the user touching it
// Icons for the editor's "Try" buttons (Material Symbols).
const ICONS = { idle: "pause", walk: "directions_walk", sit: "chair", groom: "wash", stretch: "sports_gymnastics",
    look: "visibility", call: "campaign", sleep: "bedtime", happy: "favorite", preen: "brush", peck: "grain",
    knead: "back_hand", flick: "gesture", sniff: "search", wag: "waving_hand" }
function behaviours(kind) { return COMMON.concat(OWN[kindOf(kind)]).map(b => b[0]).concat(["sleep"]) }
function ownBehaviours(kind) { return OWN[kindOf(kind)].map(b => b[0]) }

// The next behaviour: { name, duration } from r1, r2 in [0, 1). A long quiet spell makes sleep likely.
function pick(kind, r1, r2, quietSec) {
    if (quietSec >= SLEEP_AFTER && r1 < 0.6) return { name: "sleep", duration: 60 + r2 * 60 }
    const list = COMMON.concat(OWN[kindOf(kind)])
    const total = list.reduce((a, b) => a + b[1], 0)
    let acc = 0
    const at = (quietSec >= SLEEP_AFTER ? (r1 - 0.6) / 0.4 : r1) * total
    for (const b of list) {
        acc += b[1]
        if (at < acc) return { name: b[0], duration: b[2][0] + r2 * (b[2][1] - b[2][0]) }
    }
    const last = list[list.length - 1]
    return { name: last[0], duration: last[2][0] }
}
// Walking speed in px/s for a pet of `size` px.
function speed(kind, name, size) { return size * (name === "sniff" ? 0.22 : kindOf(kind) === "dog" ? 0.7 : 0.55) }
// Behaviours that walk.
function walks(name) { return name === "walk" || name === "sniff" }

// ── Poses ──────────────────────────────────────────────────────────────────
// legs: front near, front far, back near, back far (degrees, + swings forward); a duck uses the first and third.
function base() {
    return { bx: 0, by: 0, rot: 0, sq: 1, hx: 0, hy: 0, hr: 0, legs: [0, 0, 0, 0], tail: 0, eye: 1, mouth: 0,
             ear: 0, wing: 0, sit: 0, lie: 0 }
}
const bump = p => Math.sin(Math.PI * Math.max(0, Math.min(1, p)))

// The pose for behaviour `name` of `kind` at t seconds into it.
function pose(kind, name, t) {
    const p = base(), s = Math.sin
    p.by = s(t * 2.2) * 0.5
    p.tail = s(t * 1.3) * 5
    switch (name) {
    case "walk": case "sniff": {
        const f = name === "sniff" ? 6 : 11, w = s(t * f)
        p.legs = [w * 24, -w * 24, -w * 24, w * 24]
        p.by = -Math.abs(Math.cos(t * f)) * 1.6
        p.hr = s(t * f) * 2
        p.tail = s(t * f / 2) * 8
        if (kind === "duck") { p.rot = s(t * f) * 4; p.legs = [w * 28, 0, -w * 28, 0] }
        if (name === "sniff") { p.hr = 38; p.hy = 7; p.hx = 3 + s(t * 16) * 0.8; p.tail = 20 + s(t * 9) * 12 }
        break
    }
    case "sit": p.sit = 1; p.tail = 20 + s(t * 1.2) * 6; break
    case "groom": p.sit = 0.7; p.hr = 32 + s(t * 6) * 6; p.hy = 5; p.eye = 0.25; break
    case "preen": p.hr = 75 + s(t * 5) * 8; p.hx = -9; p.hy = 9; p.wing = 18 + s(t * 5) * 8; p.eye = 0.3; break
    case "stretch": {
        const k = bump(t / 2.4)
        p.rot = 10 * k; p.legs = [48 * k, 42 * k, -6 * k, -6 * k]; p.tail = 40 * k; p.eye = 1 - 0.6 * k; p.mouth = 0.5 * k
        if (kind === "duck") { p.rot = 0; p.wing = -55 * k; p.hr = -20 * k; p.legs = [0, 0, 0, 0] }
        break
    }
    case "look": p.hr = s(t * 1.1) * 18; p.hx = s(t * 0.55) * 2; break
    case "sleep": p.lie = 1; p.eye = 0; p.by = 1 + s(t * 1.2) * 0.8; p.tail = 30; p.hr = 18; p.legs = [70, 70, -70, -70]; break
    case "call": {
        const m = Math.max(bump(t / 0.55), bump((t - 0.65) / 0.55))
        p.mouth = m; p.hr = -14 * m; p.tail = 15 * m
        break
    }
    case "peck": { const k = Math.max(0, s(t * 5)); p.hr = 62 * k; p.hy = 12 * k; p.hx = 5 * k; break }
    case "knead": p.sit = 0.55; p.legs = [s(t * 6) * 18, -s(t * 6) * 18, 0, 0]; p.eye = 0.35; break
    case "flick": p.sit = 1; p.tail = 15 + s(t * 14) * 26; break
    case "wag": p.tail = s(t * 20) * 32; p.mouth = 0.6; p.ear = s(t * 10) * 4; break
    case "carry": p.legs = [22 + s(t * 3) * 8, 26 + s(t * 3 + 1) * 8, 18 + s(t * 3 + 2) * 8, 22 + s(t * 3 + 3) * 8]
        p.eye = 1; p.mouth = 0.25; p.tail = -20 + s(t * 4) * 10; p.wing = -30 + s(t * 6) * 12; break
    case "fall": p.legs = [-30, -24, 30, 24]; p.mouth = 0.5; p.tail = 40; p.wing = -45 + s(t * 26) * 35; p.ear = -25; break
    case "happy": p.eye = -1; p.mouth = 0.45; p.tail = s(t * 16) * 22; p.ear = -12; p.hr = -6; break
    }
    return p
}
// Pose a → b by k (0..1).
function mix(a, b, k) {
    const out = {}
    for (const key in b) {
        const x = a[key], y = b[key]
        out[key] = Array.isArray(y) ? y.map((v, i) => (x?.[i] ?? v) + (v - (x?.[i] ?? v)) * k)
                                    : (x ?? y) + (y - (x ?? y)) * k
    }
    return out
}
// Eye openness while not in a pose that sets it: a blink every few seconds.
function blink(t) { const c = t % 4.3; return c < 0.12 ? 1 - bump(c / 0.12) : 1 }

// ── Floors ─────────────────────────────────────────────────────────────────
// The bottom of the usable area, plus window tops where the compositor reports them: windows given in layout
// coordinates, (ox, oy) the usable area's top-left in layout coordinates, (w, h) its size.
function floors(windows, ox, oy, w, h, petW) {
    const out = [{ id: "ground", x1: 0, x2: w, y: h }]
    for (const win of windows ?? []) {
        if (!win || win.fullscreen || !(win.width > 0)) continue
        const x1 = Math.max(0, win.x - ox), x2 = Math.min(w, win.x - ox + win.width), y = win.y - oy
        if (x2 - x1 < petW * 1.3 || y < 60 || y > h - 20) continue
        out.push({ id: String(win.key ?? win.id ?? `${win.x},${win.y}`), x1: x1, x2: x2, y: y })
    }
    return out
}
// The floor under feet at (x, y): the highest one at or below y that spans x.
function floorUnder(list, x, y) {
    let best = null
    for (const f of list)
        if (x >= f.x1 && x <= f.x2 && f.y >= y - 0.5 && (!best || f.y < best.y)) best = f
    return best ?? list[0]
}
// Keeps x on a floor for a pet half its width wide.
function clampTo(f, x, half) { return Math.max(f.x1 + half, Math.min(f.x2 - half, x)) }

// One step of a fall over dt s: s = { x, y, vx, vy }; w the usable width, half the pet's half width, top its height
// (its feet can't go above that). Returns { s, landed: floor | null }.
const GRAVITY = 2600
function fall(s, dt, list, w, half, top) {
    const n = { x: s.x + s.vx * dt, y: s.y + s.vy * dt, vx: s.vx * (1 - 0.5 * dt), vy: s.vy + GRAVITY * dt }
    if (n.x < half) { n.x = half; n.vx = Math.abs(n.vx) * 0.4 }
    if (n.x > w - half) { n.x = w - half; n.vx = -Math.abs(n.vx) * 0.4 }
    if (n.y < top) { n.y = top; n.vy = Math.max(0, n.vy) }
    if (n.vy > 0) {
        let land = null
        for (const f of list)
            if (n.x >= f.x1 && n.x <= f.x2 && s.y <= f.y + 0.5 && n.y >= f.y && (!land || f.y < land.y)) land = f
        if (land) { n.y = land.y; return { s: n, landed: land } }
    }
    // The ground catches it even from below (the area shrank mid-fall, or it was let go under it): it never falls out.
    const ground = list.find(f => f.id === "ground")
    if (ground && n.y >= ground.y) { n.y = ground.y; return { s: n, landed: ground } }
    return { s: n, landed: null }
}
// A throw's velocity from recent pointer samples [{x, y, t ms}], capped.
function throwVelocity(samples, now) {
    const recent = samples.filter(p => now - p.t <= 90)
    if (recent.length < 2) return { vx: 0, vy: 0 }
    const a = recent[0], b = recent[recent.length - 1], dt = Math.max(16, b.t - a.t) / 1000
    const cap = v => Math.max(-2600, Math.min(2600, v))
    return { vx: cap((b.x - a.x) / dt), vy: cap((b.y - a.y) / dt) }
}

// ── Stacking (pet.layer) ──
// The layer modes; anything else is "above".
const LAYERS = ["above", "below", "auto"]
function layerOf(v) { return LAYERS.includes(v) ? v : "above" }
// True when a shell panel body (PanelRegistry descriptors, screen px) on that screen overlaps r = { x, y, w, h }.
function panelOver(panels, screenName, r) {
    for (const p of panels ?? []) {
        if (!p || p.screenName !== screenName || !(p.w > 0 && p.h > 0) || (p.progress ?? 1) < 0.02) continue
        if (p.x < r.x + r.w && p.x + p.w > r.x && p.y < r.y + r.h && p.y + p.h > r.y) return true
    }
    return false
}
// True when a window covers nearly all the usable area (maximised, or one tiled alone) over the pet's x.
// Windows in layout px; (ox, oy, w, h) the area.
function maximisedOver(windows, ox, oy, w, h, x) {
    for (const win of windows ?? []) {
        if (!win || win.fullscreen || !(win.width > 0)) continue
        if (win.width >= w * 0.9 && win.height >= h * 0.85 && x >= win.x - ox && x <= win.x - ox + win.width) return true
    }
    return false
}
// Where it's drawn: "top" or "bottom". why = { panel, maximised, moving } (only "auto" heeds the last two).
function layerFor(mode, why) {
    if (mode === "below" || why.panel) return "bottom"
    return mode === "auto" && (why.maximised || why.moving) ? "bottom" : "top"
}
