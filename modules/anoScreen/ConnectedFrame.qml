pragma ComponentBehavior: Bound

import qs.modules.common
import "ConnectedSurfaceGeometry.js" as SurfaceGeometry
import QtQuick
import Quickshell

/**
 * ConnectedFrame — the whole connected-corners silhouette, drawn in ONE SDF pass.
 *
 * Ported from DMS's `connected_arc.frag`. The shader computes
 *
 *     frame ring = screen box  minus  a rounded inner cutout
 *     silhouette = ring  smin-unioned with each active "chrome" surface
 *
 * where every surface carries per-corner radii AND per-corner junction-fillet
 * radii `k`. Wherever `k > 0` the smooth-minimum yields the CONCAVE ARC that
 * makes the surface look carved out of the frame — analytically, at any DPR, in
 * a single pass. The same pass renders the M3 key + ambient elevation shadow.
 *
 * This replaces the old stacked-opaque-RoundCorner carve, which could not
 * animate, z-fought panel content, and only handled horizontal bars.
 *
 * Feed `surfaces` a list of descriptors in item-local px:
 *     { side: "top"|"bottom"|"left"|"right",
 *       x, y, w, h,                       // the surface body rect
 *       surfaceRadius,                    // its own convex rounding (optional)
 *       omitStartConnector, omitEndConnector }   // flush against a frame corner
 * At most 4 (the shader's fixed slot capacity); extras are dropped.
 */
Item {
    id: root

    /// Radius of the rounded inner cutout — i.e. the screen-corner rounding.
    property real cornerRadius: 18
    /// Thickness of the frame band on each edge. 0 ⇒ the ring collapses to the
    /// four corner arcs, which is the "rounded screen corners only" look.
    property real frameThickness: 0
    /// Junction fillet radius: how far the concave arc reaches where a surface
    /// meets the frame. This is DMS's `connectedRadius`.
    property real connectedRadius: 18
    /// Default convex rounding for a surface's far corners.
    property real surfaceRadius: 12
    property color surfaceColor: Appearance?.colors.colLayer0 ?? "#1C1B1F"
    /// Overall opacity of the silhouette (the shader folds this into alpha).
    property real surfaceOpacity: 1.0

    // The shader derives the shadow from the CHROME surfaces only (the frame ring
    // is excluded — it's the outermost surface, so a ring shadow would just bleed
    // inward over windows). That makes the shadow valid at any frame thickness:
    // the bar/sidebars cast onto the desktop, the ring casts nothing.
    property bool shadowEnabled: Config.options?.appearance?.shadows?.enable ?? false
    property real shadowIntensity: Config.options?.appearance?.shadows?.intensity ?? 1.0
    property real shadowOpacity: Config.options?.appearance?.shadows?.opacity ?? 1.0
    property color shadowColor: "#000000"

    /// Up to 4 surface descriptors to fuse into the frame.
    property var surfaces: []

    // Cutout edges in px: left, top, right, bottom. Clamped so a thick frame on
    // a small screen can never invert the cutout.
    readonly property real _cutL: Math.min(frameThickness, width / 2)
    readonly property real _cutT: Math.min(frameThickness, height / 2)
    readonly property real _cutR: Math.max(_cutL, width - Math.min(frameThickness, width / 2))
    readonly property real _cutB: Math.max(_cutT, height - Math.min(frameThickness, height / 2))
    readonly property real _cutRadius: Math.max(0, Math.min(cornerRadius,
        Math.floor(Math.min(_cutR - _cutL, _cutB - _cutT) / 2)))

    /// Pack the descriptors into the shader's four fixed slots.
    /// Mirrors DMS FrameWindow._sdfSlots. Plain arrays in, vector4d out.
    readonly property var _slots: {
        const dpr = Screen.devicePixelRatio || 1
        const src = root.surfaces ?? []
        const ctx = {
            cutL: root._cutL, cutT: root._cutT, cutR: root._cutR, cutB: root._cutB,
            connectedRadius: root.connectedRadius,
            surfaceRadius: root.surfaceRadius,
            dpr: dpr
        }
        const out = []
        for (let i = 0; i < 4; i++) {
            const s = (i < src.length) ? src[i] : null
            const p = s ? SurfaceGeometry.packSlot(s, ctx) : SurfaceGeometry.emptySlot()
            out.push({
                rect: Qt.vector4d(p.rect[0], p.rect[1], p.rect[2], p.rect[3]),
                corner: Qt.vector4d(p.corner[0], p.corner[1], p.corner[2], p.corner[3]),
                k: Qt.vector4d(p.k[0], p.k[1], p.k[2], p.k[3]),
                param: Qt.vector4d(p.active, 0, 0, 0)
            })
        }
        return out
    }

    ShaderEffect {
        anchors.fill: parent
        // The shader emits premultiplied-alpha coverage; it must composite over
        // the (transparent) layershell surface rather than replace it.
        blending: true
        fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/connected_arc.frag.qsb"))

        property real widthPx: width
        property real heightPx: height
        property real cutoutRadius: root._cutRadius
        property vector4d cutout: Qt.vector4d(root._cutL, root._cutT, root._cutR, root._cutB)

        // Straight (non-premultiplied) rgba; .a is the overall silhouette opacity.
        property vector4d surfaceColor: Qt.vector4d(
            root.surfaceColor.r, root.surfaceColor.g, root.surfaceColor.b, root.surfaceOpacity)
        // .a == 0 disables BOTH shadow terms in the shader.
        property vector4d shadowColor: Qt.vector4d(
            root.shadowColor.r, root.shadowColor.g, root.shadowColor.b,
            root.shadowEnabled ? 0.30 * root.shadowOpacity : 0)
        // key: x=blur px, y=spread px, zw=offset px
        property vector4d shadowParam: Qt.vector4d(12 * root.shadowIntensity, 0, 0, 3)
        // ambient: x=blur px, y=spread px, z=alpha
        property vector4d ambientParam: Qt.vector4d(
            20 * root.shadowIntensity, 0, root.shadowEnabled ? 0.15 * root.shadowOpacity : 0, 0)

        property vector4d chromeRect0: root._slots[0].rect
        property vector4d chromeCorner0: root._slots[0].corner
        property vector4d chromeK0: root._slots[0].k
        property vector4d chromeParam0: root._slots[0].param
        property vector4d chromeRect1: root._slots[1].rect
        property vector4d chromeCorner1: root._slots[1].corner
        property vector4d chromeK1: root._slots[1].k
        property vector4d chromeParam1: root._slots[1].param
        property vector4d chromeRect2: root._slots[2].rect
        property vector4d chromeCorner2: root._slots[2].corner
        property vector4d chromeK2: root._slots[2].k
        property vector4d chromeParam2: root._slots[2].param
        property vector4d chromeRect3: root._slots[3].rect
        property vector4d chromeCorner3: root._slots[3].corner
        property vector4d chromeK3: root._slots[3].k
        property vector4d chromeParam3: root._slots[3].param
    }
}
