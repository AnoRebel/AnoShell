.pragma library
// Pure helpers for the wallpaper deck (no Qt.*), so node can check them:
// node scripts/dev/test-wallpaper-deck.js
//
// Colours are "#rrggbb" strings; HSL parts are 0..1.

function hexToHsl(hex) {
    const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || ""))
    if (!m) return null
    const n = parseInt(m[1], 16)
    const r = (n >> 16 & 255) / 255, g = (n >> 8 & 255) / 255, b = (n & 255) / 255
    const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2
    if (max === min) return { h: -1, s: 0, l }
    const d = max - min
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    let h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4
    return { h: h / 6, s, l }
}

function hslToHex(h, s, l) {
    h = ((h % 1) + 1) % 1
    const f = n => {
        const k = (n + h * 12) % 12
        const a = s * Math.min(l, 1 - l)
        const c = l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))
        return Math.round(Math.max(0, Math.min(1, c)) * 255).toString(16).padStart(2, "0")
    }
    return "#" + f(0) + f(8) + f(4)
}

// Where a wallpaper goes in the hue sort: round the wheel from red, then the
// greys dark to light, then the ones not read yet. `p` is anod's palette
// entry ({ source, hue 0..360 or -1, luminance }) or undefined.
function hueKey(p) {
    if (!p || !p.source) return 3
    const c = hexToHsl(p.source)
    if (!c || p.hue < 0 || c.s < 0.12) return 1 + (p.luminance ?? (c ? c.l : 0.5))
    return (p.hue / 360 + 0.035) % 1
}

// "img10.jpg" → ["img", 10, ".jpg"] (lower-cased), for naturalCompare.
function naturalKey(name) {
    return String(name).toLowerCase().match(/\d+|\D+/g)?.map(p => /^\d/.test(p) ? Number(p) : p) ?? []
}

function naturalCompare(a, b) {
    for (let i = 0; i < Math.min(a.length, b.length); i++) {
        const x = a[i], y = b[i]
        if (x === y) continue
        if (typeof x === "number" && typeof y === "number") return x - y
        if (typeof x === "number") return -1 // digits before letters
        if (typeof y === "number") return 1
        return x < y ? -1 : 1
    }
    return a.length - b.length
}

// entries: [{ name, modified (ms), … }]; palette: { path: entry }.
// sort: "name" | "hue" | "date" (newest first). Stable.
function sorted(entries, sort, palette) {
    const list = entries.map((w, i) => ({ w, i }))
    if (sort === "date") {
        list.sort((a, b) => (b.w.modified - a.w.modified) || (a.i - b.i))
    } else if (sort === "hue") {
        const key = {}
        for (const x of list) key[x.w.path] = hueKey(palette ? palette[x.w.path] : undefined)
        list.sort((a, b) => (key[a.w.path] - key[b.w.path]) || (a.i - b.i))
    } else {
        // Natural order ("2" before "10"), case-insensitive; keys made once
        // (localeCompare with options is slow, and QML's ignores them).
        for (const x of list) x.k = naturalKey(x.w.name)
        list.sort((a, b) => naturalCompare(a.k, b.k) || (a.i - b.i))
    }
    return list.map(x => x.w)
}

// Local search: every word must appear in the file name (case-insensitive).
function filtered(entries, query, favouritesOnly, favourites) {
    const words = String(query || "").toLowerCase().split(/\s+/).filter(w => w.length > 0)
    const favs = {}
    for (const f of favourites || []) favs[f] = true
    return entries.filter(w => (!favouritesOnly || favs[w.path] === true)
        && words.every(word => w.name.toLowerCase().indexOf(word) >= 0))
}

// A card's dress made from an image's colours: a dark surface in its main
// hue, the most vivid colour as the accent. `cols`: one or more hex colours.
function dressFrom(cols) {
    const qs = (cols || []).map(hexToHsl).filter(c => c !== null)
    if (qs.length === 0) return null
    const vividness = q => q.s * (1 - Math.abs(q.l - 0.5))
    const main = qs[0]
    let vivid = main
    for (const q of qs) if (vividness(q) > vividness(vivid)) vivid = q
    const h = main.s > 0.08 && main.h >= 0 ? main.h : Math.max(0, vivid.h)
    const s = Math.min(0.32, main.s)
    const va = vivid.h >= 0 ? vivid.h : h
    return {
        surface: hslToHex(h, s, 0.13),
        raised: hslToHex(h, s, 0.19),
        low: hslToHex(h, s, 0.1),
        ink: hslToHex(h, 0.16, 0.9),
        muted: hslToHex(h, 0.12, 0.72),
        line: hslToHex(h, Math.min(0.24, s + 0.06), 0.32),
        accent: hslToHex(va, Math.min(0.72, vivid.s + 0.18), 0.74),
        accentInk: hslToHex(va, 0.5, 0.16)
    }
}

// Five chips for a card from its source colour, labelled like the scheme
// roles they stand in for.
// ponytail: tones derived from the source colour in HSL, not matugen's real
// scheme; exact chips need palette.scan to return the scheme roles.
function chipsFrom(source) {
    const c = hexToHsl(source)
    if (!c) return []
    const h = c.h >= 0 ? c.h : 0, s = c.h >= 0 ? Math.max(0.25, c.s) : 0
    return [
        { label: "primary", fill: hslToHex(h, Math.min(0.7, s), 0.74) },
        { label: "secondary", fill: hslToHex(h, s * 0.35, 0.7) },
        { label: "tertiary", fill: hslToHex(h + 1 / 6, s * 0.5, 0.72) },
        { label: "container", fill: hslToHex(h, s * 0.6, 0.3) },
        { label: "surface", fill: hslToHex(h, s * 0.2, 0.17) }
    ]
}

// Ink that reads on a hex colour.
function inkOn(hex) {
    const c = hexToHsl(hex)
    return c && c.l > 0.55 ? "dark" : "light"
}

function kind(path) {
    const p = String(path || "").toLowerCase()
    if (/\.(mp4|webm|mkv|mov|m4v|avi|ogv)$/.test(p)) return "video"
    if (/\.(gif|webp)$/.test(p)) return "animated"
    return "image"
}

function bytes(n) {
    return n >= 1048576 ? (n / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(n / 1024)) + " KB"
}

function compact(n) {
    return n >= 1000 ? (n / 1000).toFixed(n >= 10000 ? 0 : 1) + "k" : String(n)
}

function baseName(name) {
    const dot = name.lastIndexOf(".")
    return dot > 0 ? name.substring(0, dot) : name
}
