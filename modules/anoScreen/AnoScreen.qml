import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.anoScreen
import qs.services

/**
 * AnoScreen — the connected-corners frame: one decorative full-screen surface per
 * screen that draws the shell's whole silhouette.
 *
 * A WlrLayer.Top PanelWindow spanning the output (ExclusionMode.Ignore + all-4
 * anchors) so the rounded screen corners, the frame ring, and every bar/panel
 * fused into it live in ONE coordinate space. It is DECORATIVE AND CLICK-THROUGH:
 * it hosts no panel content and reserves no space.
 *
 * That separation is load-bearing, not stylistic. Attaching a deep Layout+anchors
 * tree into a freshly-committed full-screen layershell window trips a refWindow
 * recursion segfault in QS 0.3.0 on roughly half of cold starts. So the bars keep
 * living in their own thin BarWindows (which also own the exclusive zone), and
 * this window only ever holds a single ShaderEffect. Even that is attached one
 * event-loop turn late, via the `ready` latch + an async Loader.
 *
 * Geometry comes from two places: the bars, whose rects AnoScreen computes itself
 * from Config, and PanelRegistry, where sidebars/popouts/trays publish their
 * screen-space rect as they open. Both are packed into the frame shader's four
 * chrome slots — see ConnectedFrame / ConnectedSurfaceGeometry.js.
 *
 * Multi-monitor + multi-bar aware. Opt-in via appearance.connectedCorners.enable.
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.appearance?.connectedCorners?.enable ?? false
    readonly property int cornerRadius: Math.max(1, Config.options?.appearance?.connectedCorners?.radius ?? 18)
    // Painted bezel width on each screen edge. 0 ⇒ corner arcs only.
    readonly property real frameThickness: Math.max(0, Config.options?.appearance?.connectedCorners?.thickness ?? 0)
    // Frame surface opacity; < 1.0 makes the frame translucent (pair with the
    // `blur` layer rule so the desktop behind it is blurred rather than raw).
    readonly property real frameOpacity: Math.max(0, Math.min(1, Config.options?.appearance?.connectedCorners?.opacity ?? 1.0))
    // Bar surface colour.
    readonly property color frameColor: Appearance?.colors.colLayer0 ?? "#1C1B1F"
    // Screen-corner colour: a bezel tone that reads on ANY wallpaper. Pure black
    // (like a rounded display) so the desktop looks clipped to a rounded rect —
    // colLayer0 was invisible against dark wallpaper edges.
    // Match the shell surface (same as the bar/panels) so the rounded corners
    // read as part of the theme, seamless with the rest of the shell. Force it
    // OPAQUE — colLayer0 may carry transparency, which would make the corners
    // faint/invisible; the corner is a solid carve.
    readonly property color cornerColor: Qt.rgba(
        (Appearance?.colors.colLayer0.r ?? 0.11),
        (Appearance?.colors.colLayer0.g ?? 0.11),
        (Appearance?.colors.colLayer0.b ?? 0.12), 1.0)
    readonly property real globalMargin: Config.options?.appearance?.bezel ?? 0
    readonly property bool barsShown: GlobalStates.barOpen && !GlobalStates.screenLocked

    readonly property var barDefs: Config.options?.bars ?? [{ "id": "main", "edge": "top" }]

    // ── Compositor outer-gap management ───────────────────────────────────────
    // In connected mode the frame paints the bezel, so the compositor's own outer
    // gap (the space between windows and the screen edge) would just be a second,
    // unpainted inset — windows should sit flush against the frame instead. Drop
    // gaps_out to 0 while connected (+ manageGaps), restore it otherwise. Global,
    // not per-screen, so it lives at the Scope root, driven off the config.
    readonly property bool _manageGaps: Config.options?.appearance?.connectedCorners?.manageGaps ?? true
    readonly property int _floatingGapsOut: Config.options?.appearance?.connectedCorners?.floatingGapsOut ?? 5
    readonly property int _targetGapsOut: (root.enabled && _manageGaps) ? 0 : _floatingGapsOut
    on_TargetGapsOutChanged: CompositorService.setOuterGaps(_targetGapsOut)

    // ── Frame blur ────────────────────────────────────────────────────────────
    // The frame is a FULL-SCREEN surface that is transparent everywhere except the
    // band + corners, so blurring it wholesale blurs the empty middle too and shows
    // up as a misplaced blur strip across the screen — which is why it ships
    // excluded from blur. `ignore_alpha` is what makes an opt-in safe: it is the
    // alpha threshold BELOW which a pixel is not blurred, so setting it just under
    // the frame's own opacity blurs the painted band/corners and nothing else.
    // Clamped to a floor so a fully-opaque frame (opacity 1.0) still gets a
    // threshold that excludes the transparent region.
    readonly property bool _frameBlur: root.enabled && (Config.options?.appearance?.connectedCorners?.blur ?? false)
    readonly property real _frameBlurIgnoreAlpha: Math.max(0.1, root.frameOpacity - 0.1)
    function _applyFrameBlur() {
        CompositorService.setLayerBlur("^quickshell:anoScreen$", root._frameBlur, root._frameBlurIgnoreAlpha)
    }
    on_FrameBlurChanged: _applyFrameBlur()
    on_FrameBlurIgnoreAlphaChanged: _applyFrameBlur()

    Component.onCompleted: {
        if (root.enabled && _manageGaps) CompositorService.setOuterGaps(0)
        root._applyFrameBlur()
    }
    Component.onDestruction: {
        if (_manageGaps) CompositorService.setOuterGaps(_floatingGapsOut)
        CompositorService.setLayerBlur("^quickshell:anoScreen$", false, 0)
    }

    // Whether a bar definition targets a given screen (per-bar screenList → global).
    function barOnScreen(def, screenName) {
        const list = def?.screenList ?? Config.options?.bar?.screenList ?? []
        return (!list || list.length === 0) || list.includes(screenName)
    }
    function barIsVertical(def) { return def?.edge === "left" || def?.edge === "right" }
    function barThickness(def) {
        return def?.height
            ?? Config.options?.bar?.layout?.height
            ?? (barIsVertical(def) ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight)
    }

    // Space-reservation companions: the full-screen AnoScreen window uses
    // ExclusionMode.Ignore (to reach the corners) so it reserves nothing — but
    // no separate BarExclusionZone is needed: BarManager's BarWindow loads in
    // connected mode too and reserves the bar's space itself. Adding a second
    // reservation here double-counted the space (an extra bar-height gap at the
    // top). AnoScreen is now purely decorative.

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:anoScreen"
            // The frame draws the rounded SCREEN corners, so it must sit ABOVE
            // windows or a maximized window covers the corners (Bottom put it below
            // windows → corners occluded). It stays on Top; the shell chrome (bar,
            // sidebars) is bumped to Overlay (above Top) so it always draws above
            // the frame — resolving the same-layer z-race that otherwise hid the
            // bar content until hover. Click-through mask keeps it non-interactive.
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }
            // Hide the whole frame while a window is fullscreen on this screen —
            // otherwise its (possibly blurred) surface leaves a strip over the
            // fullscreen app even though the bar has hidden. Reacts live via the
            // fullscreenRevision tick.
            readonly property bool screenFullscreen: {
                void CompositorService.fullscreenRevision
                return CompositorService.hasFullscreenOnScreen(screenName)
            }
            visible: root.enabled && !screenFullscreen

            readonly property real sw: width
            readonly property real sh: height
            readonly property string screenName: screen?.name ?? ""

            // Realization latch: flip `ready` one event-loop turn AFTER the
            // window is up and sized, so the heavy content subtree attaches to an
            // already-windowed, already-sized root (this is the property that
            // makes BarWindow crash-safe; `active: true` alone can fire mid-commit
            // and hit the QS 0.3.0 refWindow segfault).
            property bool ready: false
            onVisibleChanged: if (visible) Qt.callLater(() => { if (win) win.ready = true })
            Component.onCompleted: if (visible) Qt.callLater(() => { if (win) win.ready = true })


            // The bar definitions that actually render on THIS screen.
            readonly property var screenBars: root.barDefs.filter(d =>
                root.barOnScreen(d, screenName) && !(d?.morphingPanel ?? false))

            // Per-bar geometry helper (screen-space placeholder rect). Returns a
            // zero-size rect for an absent slot so unused mask/bar slots vanish.
            function barRect(i) {
                const def = win.screenBars[i]
                if (!def) return { x: 0, y: 0, w: 0, h: 0, vertical: false, edge: "top", present: false }
                const vertical = root.barIsVertical(def)
                const th = root.barThickness(def)
                const edge = def?.edge ?? "top"
                // Connected look: the bar is FLUSH to its screen edge and spans
                // the full length (no bezel margin → no floating pill). It fuses
                // into the frame; only the interior corners are rounded.
                const x = edge === "right" ? (sw - th) : 0
                const y = edge === "bottom" ? (sh - th) : 0
                const w = vertical ? th : sw
                const h = vertical ? sh : th
                return { x: x, y: y, w: w, h: h, vertical: vertical, edge: edge, present: true, def: def }
            }

            // Fully click-through: AnoScreen is purely decorative (screen
            // corners). An EMPTY `Region {}` is NOT click-through in Quickshell —
            // it defaults to the whole window being the input region, so this
            // full-screen Top-layer window would swallow EVERY click (bar buttons,
            // tray icons, the desktop). `Region { item: null }` = empty input
            // region = truly click-through (same pattern as PopupToolTip).
            mask: Region { item: null }

            // ── The connected silhouette's chrome surfaces ────────────────
            // The frame shader has four slots. Bars go in first (they're always
            // present and must never be evicted by a transient popout), then the
            // highest-priority registered panels fill whatever is left.
            //
            // Bars never omit a connector. Omitting is for a POPOUT whose end butts
            // against the bar's end, so that end gets no arc. A bar's own outer
            // corners must stay sharp (radius 0) so the union reaches the true
            // screen corner — the rounding there comes from the frame's cutout, and
            // the concave junction arc comes from the connector fillet `k`. Giving
            // them the bar's convex radius instead pulls the bar off the corner and
            // leaves a notch.
            readonly property var barSurfaces: {
                if (!root.barsShown) return []
                const out = []
                for (let i = 0; i < win.screenBars.length; i++) {
                    const b = win.barRect(i)
                    if (!b.present) continue
                    out.push({ "side": b.edge, "x": b.x, "y": b.y, "w": b.w, "h": b.h })
                }
                return out
            }
            readonly property var frameSurfaces: {
                const bars = win.barSurfaces
                const room = Math.max(0, 8 - bars.length)
                return bars.concat(PanelRegistry.surfacesForScreen(win.screenName, room))
            }

            // ── All visual content, attached ASYNCHRONOUSLY ───────────────
            // Attaching content synchronously while the layershell window is still
            // acquiring its surface drives the QS 0.3.0 refWindow recursion
            // segfault (the same bug BarWindow dodges). One async Loader defers the
            // subtree to a later event-loop turn, after the window is realised.
            //
            // The whole silhouette — rounded screen corners, the frame ring, and
            // every bar/panel fused into it with concave junction arcs, plus the M3
            // elevation shadow — is ONE ShaderEffect. It replaces the old stacked
            // opaque RoundCorner carve, which couldn't animate, z-fought panel
            // content, and only worked for horizontal bars.
            Loader {
                anchors.fill: parent
                asynchronous: true
                active: win.ready
                sourceComponent: ConnectedFrame {
                    anchors.fill: parent
                    cornerRadius: root.cornerRadius
                    frameThickness: root.frameThickness
                    connectedRadius: root.cornerRadius
                    surfaceRadius: Appearance?.rounding.normal ?? 12
                    surfaceColor: root.cornerColor
                    surfaceOpacity: root.frameOpacity
                    surfaces: win.frameSurfaces
                }
            }
        }
    }
}
