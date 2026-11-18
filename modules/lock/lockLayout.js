.pragma library

// Lock screen layouts (lock.layouts.<lockscreen>): a list of elements
//   { uid, type, x, y, scale, rot, opacity, settings }
// x, y: the element's centre as fractions of the screen; scale: its size
// against its natural size on a 1080 px tall screen (so a layout made on one
// screen looks the same, proportionally, on another); rot: 0/90/180/270;
// opacity 0.2–1. Used by the lock screens that support layouts (the built-in
// one and Simple), the layout editor and the migration of the old lock.layout.

var REF_H = 1080

// Natural size (px at REF_H) of each element type. A piece's comes from its
// grid size (PIECE_CELL px per cell).
var PIECE_CELL = 110
var SIZES = {
    clock: { w: 380, h: 150 },
    avatar: { w: 104, h: 104 },
    name: { w: 300, h: 48 },
    field: { w: 340, h: 112 },
    keyboard: { w: 132, h: 40 },
    battery: { w: 132, h: 40 },
    notifications: { w: 380, h: 260 },
    piece: { w: 220, h: 220 }
}
var TYPES = Object.keys(SIZES)
var LABELS = { clock: "Clock", avatar: "Avatar", name: "User name", field: "Password field", keyboard: "Keyboard layout",
               battery: "Battery", notifications: "Notifications", piece: "Piece" }
var ICONS = { clock: "schedule", avatar: "account_circle", name: "badge", field: "password", keyboard: "keyboard",
              battery: "battery_full", notifications: "notifications", piece: "widgets" }

function el(type, x, y, scale, extra) {
    var e = { uid: type, type: type, x: x, y: y, scale: scale || 1, rot: 0, opacity: 1, settings: {} }
    if (extra) for (var k in extra) e[k] = extra[k]
    return e
}

// The built-in lock screen's own arrangement (also what Reset goes back to). A package that supports
// layouts brings its own as `layout` in lockscreen.json (`own` below).
var DEFAULTS = {
    // About where the centred column puts them on a 1080 px tall screen.
    "default": [el("clock", 0.5, 0.39, 0.86), el("avatar", 0.5, 0.5, 0.77), el("name", 0.5, 0.578), el("field", 0.5, 0.67)]
}

function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
// Lists that came through a QML `var` signal argument aren't JS arrays (Array.isArray is false): copy them.
function arr(l) { return Array.isArray(l) ? l : (l && typeof l === "object" && typeof l.length === "number" ? Array.prototype.slice.call(l) : null) }
function num(v, d) { return typeof v === "number" && isFinite(v) ? v : d }

function defaultsFor(id, own) {
    var o = arr(own)
    var src = o && o.length ? o : DEFAULTS["default"]
    var out = clean(JSON.parse(JSON.stringify(src)))
    if (!hasField(out)) out.push(el("field", 0.5, 0.66))
    return out
}

// A clean copy: known types only, values in range, unique uids, and always a
// password field (it can't be removed: without one nothing unlocks).
function normalize(list, id, own) {
    list = arr(list)
    if (!list) return defaultsFor(id, own)
    var out = clean(list)
    if (!hasField(out))
        out.push(defaultsFor(id, own).filter(function (e) { return e.type === "field" })[0])
    return out
}
function clean(list) {
    var out = [], seen = {}
    for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (!e || TYPES.indexOf(e.type) < 0) continue
        if (e.type === "piece" && !(e.settings && typeof e.settings.id === "string" && e.settings.id)) continue
        var uid = typeof e.uid === "string" && e.uid ? e.uid : e.type
        while (seen[uid]) uid = e.type + "-" + Math.floor(Math.random() * 1e6)
        seen[uid] = true
        var rot = Math.round(num(e.rot, 0) / 90) * 90 % 360
        out.push({ uid: uid, type: e.type, x: clamp(num(e.x, 0.5), 0, 1), y: clamp(num(e.y, 0.5), 0, 1),
                   scale: clamp(num(e.scale, 1), 0.3, 4), rot: rot < 0 ? rot + 360 : rot,
                   opacity: clamp(num(e.opacity, 1), 0.2, 1), settings: e.settings && typeof e.settings === "object" ? e.settings : {} })
    }
    return out
}
function hasField(list) { return list.some(function (e) { return e.type === "field" }) }

// The layout to draw: the saved one, or the lock screen's own.
function resolve(layouts, id, own) {
    var l = arr(layouts && layouts[id])
    return l && l.length ? normalize(l, id, own) : defaultsFor(id, own)
}

// Natural size of an element (px at REF_H), pieces by their grid size.
function natural(e, pieceSize) {
    if (e.type === "piece" && pieceSize) return { w: pieceSize.w * PIECE_CELL, h: pieceSize.h * PIECE_CELL }
    return SIZES[e.type] || { w: 100, h: 100 }
}

// Where an element is drawn on a W × H screen: its bounding box (turned 90°
// swaps the sides) and the factor its natural size is drawn at. Kept whole on
// the screen when it fits (a layout made on a wider screen, a narrow one).
function rectOf(e, W, H, pieceSize) {
    var n = natural(e, pieceSize), k = e.scale * H / REF_H
    var turned = e.rot === 90 || e.rot === 270
    var w = (turned ? n.h : n.w) * k, h = (turned ? n.w : n.h) * k
    var x = e.x * W - w / 2, y = e.y * H - h / 2
    if (w <= W) x = clamp(x, 0, W - w)
    if (h <= H) y = clamp(y, 0, H - h)
    return { x: x, y: y, w: w, h: h, k: k }
}

// The old built-in layout ({ clock|user|status|field: { x, y, scale } }) as
// elements: the user block becomes the avatar over the name.
function migrate(old) {
    if (!old || typeof old !== "object" || !Object.keys(old).length) return null
    var out = defaultsFor("default")
    function at(type) { return out.filter(function (e) { return e.type === type })[0] }
    function put(type, o, dy) {
        if (!o || !isFinite(o.x) || !isFinite(o.y)) return
        var s = clamp(num(o.scale, 1), 0.3, 4), e = at(type)
        if (!e) { e = el(type, 0.5, 0.5); out.push(e) }
        e.x = clamp(o.x, 0, 1); e.y = clamp(o.y + (dy || 0) * s, 0, 1); e.scale = (type === "avatar" ? 0.8 : 1) * s
    }
    put("clock", old.clock)
    put("avatar", old.user, -0.045)
    put("name", old.user, 0.04)
    put("battery", old.status)
    put("field", old.field)
    return out
}

// Snapping a moved box (px) to the screen's centre lines and the other boxes'
// edges and centres, within `tol` px; with `grid` > 0, to the grid when nothing
// else is near. Returns the snapped position and the guide lines to draw.
function snap(r, others, W, H, tol, grid) {
    function best(pos, size, targets) {
        var cand = [pos, pos + size / 2, pos + size], hit = null
        for (var i = 0; i < targets.length; i++)
            for (var j = 0; j < 3; j++) {
                var d = targets[i] - cand[j]
                if (Math.abs(d) <= tol && (!hit || Math.abs(d) < Math.abs(hit.d))) hit = { d: d, at: targets[i] }
            }
        return hit
    }
    var tx = [W / 2], ty = [H / 2]
    for (var i = 0; i < others.length; i++) {
        var o = others[i]
        tx.push(o.x, o.x + o.w / 2, o.x + o.w); ty.push(o.y, o.y + o.h / 2, o.y + o.h)
    }
    var hx = best(r.x, r.w, tx), hy = best(r.y, r.h, ty)
    var x = r.x, y = r.y, guides = []
    if (hx) { x += hx.d; guides.push({ axis: "x", at: hx.at }) }
    else if (grid > 0) x = Math.round(r.x / grid) * grid
    if (hy) { y += hy.d; guides.push({ axis: "y", at: hy.at }) }
    else if (grid > 0) y = Math.round(r.y / grid) * grid
    return { x: x, y: y, guides: guides }
}

// Undo history: { past: [layouts], future: [layouts] } (at most `max` kept).
function record(h, before, max) {
    var past = h.past.concat([before])
    if (past.length > (max || 50)) past = past.slice(past.length - (max || 50))
    return { past: past, future: [] }
}
function undo(h, cur) {
    if (!h.past.length) return null
    return { layout: h.past[h.past.length - 1], h: { past: h.past.slice(0, -1), future: h.future.concat([cur]) } }
}
function redo(h, cur) {
    if (!h.future.length) return null
    return { layout: h.future[h.future.length - 1], h: { past: h.past.concat([cur]), future: h.future.slice(0, -1) } }
}
