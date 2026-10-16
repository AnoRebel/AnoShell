import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
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
 * Geometry comes from PanelRegistry: the bars, sidebars, popouts and other fused
 * surfaces publish their current screen-space body through a
 * ConnectedSurfaceLease, and the frame packs them into the shader's 8 slots —
 * see ConnectedFrame / ConnectedSurfaceGeometry.js.
 *
 * Multi-monitor + multi-bar aware. Opt-in via appearance.connectedCorners.enable.
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.appearance?.connectedCorners?.enable ?? false
    // Your radius if you set one, else the active look's.
    readonly property int cornerRadius: { void Config.deltaRevision; return Math.max(1, Config.originOf("appearance.connectedCorners.radius") === "user"
        ? (Config.options?.appearance?.connectedCorners?.radius ?? 18)
        : (Looks.current.shape?.connectedRadius ?? Config.options?.appearance?.connectedCorners?.radius ?? 18)) }
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
    // Where ext-background-effect-v1 exists (Hyprland, niri) the frame window
    // sets a blur region shaped like the silhouette instead, and the
    // rectangular layer-rule blur stays off.
    readonly property bool _shapedBlur: CompositorService.supports.blurProtocol ?? false
    // Hyprland applies a layer's ignore_alpha to protocol blur too, so with the
    // shaped region the threshold must be 0 or transparent-ish parts of the
    // region (a translucent frame) are skipped.
    function _applyFrameBlur() {
        if (root._shapedBlur) CompositorService.setLayerBlur("^quickshell:anoScreen$", false, 0)
        else CompositorService.setLayerBlur("^quickshell:anoScreen$", root._frameBlur, root._frameBlurIgnoreAlpha)
    }
    on_FrameBlurChanged: _applyFrameBlur()
    on_ShapedBlurChanged: _applyFrameBlur()
    on_FrameBlurIgnoreAlphaChanged: _applyFrameBlur()

    // Applied on start in both modes: a killed/crashed connected shell never
    // ran onDestruction, so the compositor may still hold gaps_out 0.
    Component.onCompleted: {
        if (_manageGaps) CompositorService.setOuterGaps(_targetGapsOut)
        root._applyFrameBlur()
    }
    Component.onDestruction: {
        if (_manageGaps) CompositorService.setOuterGaps(_floatingGapsOut)
        CompositorService.setLayerBlur("^quickshell:anoScreen$", false, 0)
    }

    // ── Space reservation (FrameExclusions) ───────────────────────────────────
    // The frame window reserves nothing (ExclusionMode.Ignore, click-through).
    // A painted band would cover the edges of windows, so one thin, empty,
    // click-through window per edge reserves the band's thickness, except on
    // edges a bar already reserves (no double gap).
    // Until the bars have mapped and published their reserves, an edge band
    // follows the config (is a reserving bar declared on that edge?) so the
    // bands are right from the first frame; after that, the live registry.
    property bool reservesArmed: false
    // After the pill has revealed and published its reserve (600 ms + its
    // own settle), so the band on its edge never maps and unmaps at start.
    Timer { running: GlobalStates.shellSettled; interval: 2000; onTriggered: root.reservesArmed = true }
    function _barDeclared(screenName, edge) {
        if (BarStyle.pillBar) return edge === BarStyle.pillEdge
        const list = Config.options?.bar?.screenList ?? []
        if (list.length > 0 && !list.includes(screenName)) return false
        const bars = Config.options?.bars ?? [{ edge: "top" }]
        for (let i = 0; i < bars.length; i++) {
            const b = bars[i]
            if ((b?.edge ?? "top") === edge && !b?.morphingPanel && !b?.autoHide) return true
        }
        return false
    }

    Variants {
        // After the config is ready, so the bands map at your thickness.
        model: Config.ready && root.enabled && root.frameThickness > 0 ? Quickshell.screens : []
        Scope {
            id: excl
            required property var modelData
            Variants {
                model: ["top", "bottom", "left", "right"]
                PanelWindow {
                    required property string modelData
                    readonly property string edge: modelData
                    screen: excl.modelData
                    visible: root.reservesArmed
                        ? PanelRegistry.reserved(excl.modelData?.name ?? "", edge) <= 0
                        : !root._barDeclared(excl.modelData?.name ?? "", edge)
                    WlrLayershell.namespace: "quickshell:frameExclusion"
                    WlrLayershell.layer: WlrLayer.Bottom
                    color: "transparent"
                    mask: Region { item: null }
                    exclusiveZone: root.frameThickness
                    anchors {
                        top: edge !== "bottom"
                        bottom: edge !== "top"
                        left: edge !== "right"
                        right: edge !== "left"
                    }
                    implicitWidth: edge === "left" || edge === "right" ? root.frameThickness : 0
                    implicitHeight: edge === "top" || edge === "bottom" ? root.frameThickness : 0
                }
            }
        }
    }

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
            // The band and corners retract on a spring rather than vanishing;
            // the window unmaps once fully retracted.
            property real shown: screenFullscreen ? 0 : 1
            Behavior on shown { MotionSpring { token: win.screenFullscreen ? "settle" : "liquid" } }
            visible: GlobalStates.shellSettled && root.enabled && (!screenFullscreen || shown > 0.001)

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


            // Fully click-through: AnoScreen is purely decorative (screen
            // corners). An EMPTY `Region {}` is NOT click-through in Quickshell —
            // it defaults to the whole window being the input region, so this
            // full-screen Top-layer window would swallow EVERY click (bar buttons,
            // tray icons, the desktop). `Region { item: null }` = empty input
            // region = truly click-through (same pattern as PopupToolTip).
            mask: Region { item: null }

            // ── The connected silhouette's chrome surfaces ────────────────
            // Every fused surface (bars included) publishes its current body
            // through a ConnectedSurfaceLease; the highest priorities fill the
            // shader's 8 slots (bars rank highest, so a popout never evicts one).
            readonly property var frameSurfaces: PanelRegistry.surfacesForScreen(win.screenName, 8)

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
            BackgroundEffect.blurRegion: !win.ready ? null : root._frameBlur && root._shapedBlur ? (frameLoader.item?.blurShape ?? null) : null

            Loader {
                id: frameLoader
                anchors.fill: parent
                asynchronous: true
                active: win.ready
                sourceComponent: ConnectedFrame {
                    anchors.fill: parent
                    cornerRadius: root.cornerRadius * Math.max(0, win.shown)
                    frameThickness: root.frameThickness * Math.max(0, win.shown)
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
