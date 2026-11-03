.pragma library

// Geometry for the connected-frame SDF (`shaders/frag/connected_arc.frag`).
// Ported from DMS's ConnectedSurfaceGeometry.js + FrameWindow._sdfSlots, trimmed
// to what ano needs: turn a surface descriptor into the shader's fixed slot
// layout {rect, corner, k, param}.
//
// Corner order everywhere is (topLeft, topRight, bottomRight, bottomLeft) — the
// order sdRoundBox4/chromeK index into.

function isHorizontal(side) {
    return side === "top" || side === "bottom";
}

function snap(value, dpr) {
    var scale = dpr || 1;
    var n = Number(value);
    if (isNaN(n))
        n = 0;
    return Math.round(n * scale) / scale;
}

// Clamp the surface's NEAR edge to the frame's inner cutout, so the body only
// protrudes inward from the ring. Without this a bar drawn at y=0 would poke
// through a thick frame instead of growing out of it.
function clampNear(side, rect, cut) {
    var r = { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
    if (side === "top") {
        r.height = Math.max(0, rect.y + rect.height - cut.cutT);
        r.y = cut.cutT;
    } else if (side === "bottom") {
        r.height = Math.max(0, cut.cutB - rect.y);
    } else if (side === "left") {
        r.width = Math.max(0, rect.x + rect.width - cut.cutL);
        r.x = cut.cutL;
    } else if (side === "right") {
        r.width = Math.max(0, cut.cutR - rect.x);
    }
    return r;
}

// near = the concave junction fillet where the body meets the frame.
// far  = the body's own convex rounding on the corners away from the frame.
function connectorRadii(descriptor, rect, connectedRadius, surfaceRadius) {
    var side = descriptor.side || "top";
    var horizontal = isHorizontal(side);
    var extent = horizontal ? rect.height : rect.width;   // depth into the screen
    var crossSize = horizontal ? rect.width : rect.height; // along the edge

    var near = Math.max(0, Math.min(connectedRadius, extent, crossSize / 2));
    var far = Math.max(0, Math.min(connectedRadius, surfaceRadius, crossSize / 2));

    var omitStart = !!descriptor.omitStartConnector;
    var omitEnd = !!descriptor.omitEndConnector;
    return {
        near: near,
        far: far,
        startCr: omitStart ? 0 : near,
        endCr: omitEnd ? 0 : near,
        farStartCr: omitStart ? far : 0,
        farEndCr: omitEnd ? far : 0,
        surfaceRadius: surfaceRadius
    };
}

/**
 * Pack one surface descriptor into a shader slot.
 *
 * descriptor: { side, x, y, w, h, surfaceRadius?, omitStartConnector?, omitEndConnector? }
 * ctx:        { cutL, cutT, cutR, cutB, connectedRadius, surfaceRadius, dpr }
 *
 * Returns plain arrays — `Qt.vector4d` is not in scope in a .pragma library, so
 * the caller builds the vectors:
 *     { rect: [x,y,w,h], corner: [tl,tr,br,bl], k: [tl,tr,br,bl], active: 0|1 }
 *
 * "start" is the low-coordinate end along the surface's edge (left for a
 * horizontal bar, top for a vertical one); "end" is the high-coordinate end.
 * Omitting a connector means that end is flush with a frame corner, so it takes
 * the body's convex radius there instead of a concave fillet.
 */
// Liquid motion (Liquid look). While a surface grows out of its edge
// (0 < progress < 1) its junction fillets swell like a meniscus and settle back
// to connectedRadius when fully open. ponytail: fixed swell; looks (W3) will
// provide it as a motion token.
var MENISCUS_SWELL = 0.6;

function meniscusK(base, progress) {
    var p = Math.max(0, Math.min(1, progress === undefined ? 1 : progress));
    return p >= 1 ? base : base * (1 + MENISCUS_SWELL * Math.sin(Math.PI * p));
}

function packSlot(descriptor, ctx) {
    var dpr = ctx.dpr || 1;
    var side = descriptor.side || "top";

    var raw = {
        x: snap(descriptor.x, dpr),
        y: snap(descriptor.y, dpr),
        width: Math.max(0, snap(descriptor.w, dpr)),
        height: Math.max(0, snap(descriptor.h, dpr))
    };
    // A detached surface (an island) keeps its own near edge instead of
    // growing out of the frame; the smooth-min k between it and the frame
    // then draws a liquid neck that thins and breaks as the gap opens.
    var detached = !!descriptor.detached;
    var b = detached ? raw : clampNear(side, raw, ctx);
    var active = (b.width > 0 && b.height > 0) ? 1 : 0;

    var bodyR = descriptor.surfaceRadius !== undefined ? descriptor.surfaceRadius : ctx.surfaceRadius;
    var radii = connectorRadii(descriptor, b, meniscusK(ctx.connectedRadius, descriptor.progress), bodyR);
    var youngK = 0;
    if (descriptor.progress !== undefined && descriptor.progress < 1) {
        // The swell is wider than the young body is deep; don't clamp it to the
        // extent, or the meniscus collapses exactly when it should show.
        var cross = isHorizontal(side) ? b.width : b.height;
        var k = Math.min(meniscusK(ctx.connectedRadius, descriptor.progress), cross / 2);
        radii.startCr = descriptor.omitStartConnector ? 0 : k;
        radii.endCr = descriptor.omitEndConnector ? 0 : k;
        youngK = k;
    }
    if (detached) {
        // Fully round island; k on every corner so the neck forms evenly.
        var nk = descriptor.neckK !== undefined ? descriptor.neckK : ctx.connectedRadius;
        return {
            rect: [b.x, b.y, b.width, b.height],
            corner: [bodyR, bodyR, bodyR, bodyR],
            k: [nk, nk, nk, nk],
            active: active,
            junction: null
        };
    }

    var extent = isHorizontal(side) ? b.height : b.width;
    // Bury, don't shrink (Ryoku docs/frame.md): a body shallower than its two
    // far corners keeps their full radius and reaches back into the ring
    // instead (solid there, or off-screen at thickness 0), so a closing
    // panel retracts into its edge rather than squashing into a nub.
    var fc = radii.far;
    var bury = Math.max(0, 2 * fc - extent);
    if (bury > 0) {
        if (side === "top") { b.y -= bury; b.height += bury; }
        else if (side === "bottom") { b.height += bury; }
        else if (side === "left") { b.x -= bury; b.width += bury; }
        else { b.width += bury; }
    }
    var omitS = radii.farStartCr > 0;
    var omitE = radii.farEndCr > 0;

    // A corner is either a concave junction (k > 0, radius 0) or a convex body
    // corner (radius = bodyR, k = the fillet that blends it into the ring).
    // An omitted end keeps its far corner round too: k = fc smooth-unions it
    // into whatever it butts against (a fillet), and where nothing is there
    // (a sidebar sliding beside a pill, under open desktop) it stays round
    // instead of showing a square corner.
    var nearS = omitS ? radii.surfaceRadius : 0;
    var nearE = omitE ? radii.surfaceRadius : 0;
    var farS = radii.surfaceRadius;
    var farE = radii.surfaceRadius;
    var kS = omitS ? fc : radii.startCr;
    var kE = omitE ? fc : radii.endCr;
    // The shader picks a corner's k by the quadrant around the body's centre,
    // so beside a young body (shallower than its swollen fillet) the k jumped
    // at mid-height and the meniscus showed a terrace. While growing, the far
    // corner of a joined end takes the same k: one smooth blend per side.
    var fS = (youngK > 0 && !omitS && !descriptor.omitStartConnector) ? Math.max(fc, youngK) : fc;
    var fE = (youngK > 0 && !omitE && !descriptor.omitEndConnector) ? Math.max(fc, youngK) : fc;

    var ks, cr;
    if (side === "top") {
        // near = top edge (TL, TR); far = bottom edge (BR, BL)
        ks = [kS, kE, fE, fS];
        cr = [nearS, nearE, farE, farS];
    } else if (side === "bottom") {
        ks = [fS, fE, kE, kS];
        cr = [farS, farE, nearE, nearS];
    } else if (side === "left") {
        ks = [kS, fS, fE, kE];
        cr = [nearS, farS, farE, nearE];
    } else { // right
        ks = [fS, kS, kE, fE];
        cr = [farS, nearS, nearE, farE];
    }

    return {
        rect: [b.x, b.y, b.width, b.height],
        corner: cr,
        k: ks,
        active: active,
        // For fillets(): the slot in its edge's local frame, and its junction k.
        junction: { side: side, omitS: omitS || !!descriptor.omitStartConnector,
                    omitE: omitE || !!descriptor.omitEndConnector, kS: kS, kE: kE, fc: fc }
    };
}

// Edge-local frame: u runs along the edge, v is the depth into the screen.
function _local(side, r, W, H) {
    if (side === "top") return { u0: r[0], u1: r[0] + r[2], v1: r[1] + r[3] };
    if (side === "bottom") return { u0: r[0], u1: r[0] + r[2], v1: H - r[1] };
    if (side === "left") return { u0: r[1], u1: r[1] + r[3], v1: r[0] + r[2] };
    return { u0: r[1], u1: r[1] + r[3], v1: W - r[0] };
}
function _screen(side, u, v, W, H) {
    if (side === "top") return [u, v];
    if (side === "bottom") return [u, H - v];
    if (side === "left") return [v, u];
    return [W - v, u];
}

/**
 * The concave fillets the shader's smooth-min draws OUTSIDE the slot rects,
 * as {x, y, w, h, cx, cy, r}: a k×k square minus the circle of radius k
 * centred at (cx, cy). The blur region needs them, or they show unblurred
 * next to blurred bodies. Junctions: where a slot's side meets the surface it
 * grows out of (the deepest same-edge slot under it, else the ring), and
 * where a slot's end is flush with the band or surface beside it (far corner).
 * ctx: { cutL, cutT, cutR, cutB, width, height }.
 */
function fillets(packed, ctx) {
    var W = ctx.width, H = ctx.height, out = [];
    var near = { top: ctx.cutT, bottom: H - ctx.cutB, left: ctx.cutL, right: W - ctx.cutR };
    var slots = [];
    for (var i = 0; i < packed.length; i++) {
        var p = packed[i];
        if (p.active && p.junction) {
            var l = _local(p.junction.side, p.rect, W, H);
            slots.push({ j: p.junction, u0: l.u0, u1: l.u1, v1: l.v1 });
        }
    }
    function depth(s, u) {
        var d = near[s.j.side];
        for (var n = 0; n < slots.length; n++) {
            var o = slots[n];
            if (o !== s && o.j.side === s.j.side && o.u0 <= u && u <= o.u1) d = Math.max(d, o.v1);
        }
        return d;
    }
    function push(s, u, v, du, k) {
        if (!(k > 0)) return;
        var a = _screen(s.j.side, u, v, W, H), b = _screen(s.j.side, u + du * k, v + k, W, H);
        out.push({ x: Math.min(a[0], b[0]), y: Math.min(a[1], b[1]), w: k, h: k, cx: b[0], cy: b[1], r: k });
    }
    // Is the screen point under another active slot? (An omitted end only
    // fillets into a surface that is actually there.)
    function covered(s, u, v) {
        var q = _screen(s.j.side, u, v, W, H);
        for (var n = 0; n < packed.length; n++) {
            var r = packed[n].rect;
            if (packed[n].active && packed[n].junction !== s.j && q[0] >= r[0] - 0.5 && q[0] <= r[0] + r[2] + 0.5
                    && q[1] >= r[1] - 0.5 && q[1] <= r[1] + r[3] + 0.5) return true;
        }
        return false;
    }
    for (var m = 0; m < slots.length; m++) {
        var s = slots[m], side = s.j.side, horiz = isHorizontal(side);
        var c0 = horiz ? ctx.cutL : ctx.cutT, c1 = horiz ? ctx.cutR : ctx.cutB;
        if (s.u0 <= c0 + 0.5 || (s.j.omitS && covered(s, s.u0 - 1, s.v1 - 1))) push(s, Math.max(s.u0, c0), s.v1, 1, s.j.fc);
        else if (!s.j.omitS) { var d0 = depth(s, s.u0 - 0.5); if (d0 < s.v1 - 0.5) push(s, s.u0, d0, -1, s.j.kS); }
        if (s.u1 >= c1 - 0.5 || (s.j.omitE && covered(s, s.u1 + 1, s.v1 - 1))) push(s, Math.min(s.u1, c1), s.v1, -1, s.j.fc);
        else if (!s.j.omitE) { var d1 = depth(s, s.u1 + 0.5); if (d1 < s.v1 - 0.5) push(s, s.u1, d1, 1, s.j.kE); }
    }
    return out;
}

/// The inert slot for an unused shader chrome channel.
function emptySlot() {
    return { rect: [0, 0, 0, 0], corner: [0, 0, 0, 0], k: [0, 0, 0, 0], active: 0 };
}
