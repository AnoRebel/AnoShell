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
function packSlot(descriptor, ctx) {
    var dpr = ctx.dpr || 1;
    var side = descriptor.side || "top";

    var raw = {
        x: snap(descriptor.x, dpr),
        y: snap(descriptor.y, dpr),
        width: Math.max(0, snap(descriptor.w, dpr)),
        height: Math.max(0, snap(descriptor.h, dpr))
    };
    var b = clampNear(side, raw, ctx);
    var active = (b.width > 0 && b.height > 0) ? 1 : 0;

    var bodyR = descriptor.surfaceRadius !== undefined ? descriptor.surfaceRadius : ctx.surfaceRadius;
    var radii = connectorRadii(descriptor, b, ctx.connectedRadius, bodyR);

    var extent = isHorizontal(side) ? b.height : b.width;
    var fc = Math.min(radii.far, extent);
    var omitS = radii.farStartCr > 0;
    var omitE = radii.farEndCr > 0;

    // A corner is either a concave junction (k > 0, radius 0) or a convex body
    // corner (radius = bodyR, k = the fillet that blends it into the ring).
    var nearS = omitS ? radii.surfaceRadius : 0;
    var nearE = omitE ? radii.surfaceRadius : 0;
    var farS = omitS ? 0 : radii.surfaceRadius;
    var farE = omitE ? 0 : radii.surfaceRadius;
    var kS = omitS ? fc : radii.startCr;
    var kE = omitE ? fc : radii.endCr;

    var ks, cr;
    if (side === "top") {
        // near = top edge (TL, TR); far = bottom edge (BR, BL)
        ks = [kS, kE, fc, fc];
        cr = [nearS, nearE, farE, farS];
    } else if (side === "bottom") {
        ks = [fc, fc, kE, kS];
        cr = [farS, farE, nearE, nearS];
    } else if (side === "left") {
        ks = [kS, fc, fc, kE];
        cr = [nearS, farS, farE, nearE];
    } else { // right
        ks = [fc, kS, kE, fc];
        cr = [farS, nearS, nearE, farE];
    }

    return {
        rect: [b.x, b.y, b.width, b.height],
        corner: cr,
        k: ks,
        active: active
    };
}

/// The inert slot for an unused shader chrome channel.
function emptySlot() {
    return { rect: [0, 0, 0, 0], corner: [0, 0, 0, 0], k: [0, 0, 0, 0], active: 0 };
}
