import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * AnoScreen — one unified full-screen surface per screen (noctalia MainScreen /
 * caelestia ContentWindow model).
 *
 * A single WlrLayer.Top PanelWindow spanning the whole output (ExclusionMode
 * Ignore + all-4 anchors), so ALL bars, panels, screen-corner rounding and the
 * connected background live in ONE coordinate space and can join seamlessly.
 *
 * Multi-monitor + multi-bar aware: renders every configured bar (Config.bars)
 * on every screen that bar targets (per-bar geometry, edge, thickness, modules).
 * Input is click-through by default; each visible bar adds its own rectangle to
 * the window mask (fixed slots — Region can't take a Repeater) so only the bars
 * (and, later, open panels) are interactive.
 *
 * NOTE: the bar content is attached AFTER the window is up (delayedActive) to
 * dodge the QS 0.3.0 refWindow/derefWindow recursion segfault that a deep tree
 * attaching synchronously into a fresh window triggers.
 *
 * Opt-in via appearance.connectedCorners.enable. Phase 1: screen corners + all
 * bars. Sidebars/panels move in next.
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.appearance?.connectedCorners?.enable ?? false
    readonly property int cornerRadius: Math.max(1, Config.options?.appearance?.connectedCorners?.radius ?? 18)
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
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.enabled

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

            // ── All visual content, attached ASYNCHRONOUSLY ───────────────
            // The corner Shapes + bar content are a deep item tree; attaching it
            // synchronously while the layershell window is still acquiring its
            // surface drives the QS 0.3.0 refWindow recursion segfault (same bug
            // BarWindow dodges). One async Loader defers the whole subtree to a
            // later event-loop turn, after the window is realised.
            Loader {
                anchors.fill: parent
                asynchronous: true
                active: win.ready
                sourceComponent: Item {
                    anchors.fill: parent

                    // Rounded outer screen corners
                    RoundCorner {
                        anchors.top: parent.top; anchors.left: parent.left
                        implicitSize: root.cornerRadius; color: root.cornerColor
                        corner: RoundCorner.CornerEnum.TopLeft
                    }
                    RoundCorner {
                        anchors.top: parent.top; anchors.right: parent.right
                        implicitSize: root.cornerRadius; color: root.cornerColor
                        corner: RoundCorner.CornerEnum.TopRight
                    }
                    RoundCorner {
                        anchors.bottom: parent.bottom; anchors.left: parent.left
                        implicitSize: root.cornerRadius; color: root.cornerColor
                        corner: RoundCorner.CornerEnum.BottomLeft
                    }
                    RoundCorner {
                        anchors.bottom: parent.bottom; anchors.right: parent.right
                        implicitSize: root.cornerRadius; color: root.cornerColor
                        corner: RoundCorner.CornerEnum.BottomRight
                    }

                    // ── Bar → frame concave joins ──────────────────────────
                    // AnoScreen never hosts bar content/background (that lives in
                    // BarWindow; hosting it here crashes QS 0.3.0, and AnoScreen is
                    // stacked ABOVE the bar so it would occlude it). But we CAN
                    // draw small concave carves in the GAP between the bar's outer
                    // corners and the screen edge — that space has no bar content,
                    // so it doesn't occlude, and it makes the bar read as fused
                    // into the frame instead of a floating pill.
                    Repeater {
                        model: win.screenBars
                        Item {
                            id: barJoin
                            required property var modelData
                            anchors.fill: parent
                            readonly property real m: root.globalMargin
                            readonly property real th: root.barThickness(modelData)
                            readonly property real br: root.cornerRadius
                            readonly property string edge: modelData?.edge ?? "top"
                            readonly property bool isTop: edge === "top"
                            readonly property bool isBottom: edge === "bottom"
                            // Only horizontal (top/bottom) bars fused for now.
                            visible: (isTop || isBottom) && root.barsShown

                            // The bar band's inner edge (toward the desktop).
                            readonly property real yInner: isTop ? (m + th) : (win.sh - m - th)

                            // Concave carves in the frame colour, tucked at the two
                            // interior corners of the bar so it flows into the
                            // frame. A TopLeft RoundCorner placed just below the bar
                            // rounds the gap between the bar's left underside and
                            // the desktop; mirror for the right.
                            RoundCorner {
                                implicitSize: barJoin.br
                                color: root.cornerColor
                                x: barJoin.m
                                y: barJoin.isTop ? barJoin.yInner : (barJoin.yInner - barJoin.br)
                                corner: barJoin.isTop ? RoundCorner.CornerEnum.TopLeft
                                                      : RoundCorner.CornerEnum.BottomLeft
                            }
                            RoundCorner {
                                implicitSize: barJoin.br
                                color: root.cornerColor
                                x: win.sw - barJoin.m - barJoin.br
                                y: barJoin.isTop ? barJoin.yInner : (barJoin.yInner - barJoin.br)
                                corner: barJoin.isTop ? RoundCorner.CornerEnum.TopRight
                                                      : RoundCorner.CornerEnum.BottomRight
                            }
                        }
                    }

                    // ── Registered-panel → frame concave joins ─────────────
                    // Sidebars/popups/trays publish their content rect + edge to
                    // PanelRegistry; draw concave carves at the panel's two corners
                    // that face the desktop, so the panel fuses into the frame.
                    Repeater {
                        model: PanelRegistry.panelsForScreen(win.screenName)
                        Item {
                            id: panelJoin
                            required property var modelData
                            anchors.fill: parent
                            readonly property real r: root.cornerRadius
                            readonly property string edge: modelData?.edge ?? "right"
                            readonly property bool vertical: edge === "left" || edge === "right"
                            readonly property real px: modelData?.x ?? 0
                            readonly property real py: modelData?.y ?? 0
                            readonly property real pw: modelData?.w ?? 0
                            readonly property real ph: modelData?.h ?? 0
                            // Interior x (desktop-facing edge of the panel).
                            readonly property real inX: edge === "right" ? px : (px + pw)
                            visible: vertical && root.enabled

                            // For a right sidebar (edge="right"), the desktop-facing
                            // edge is its LEFT side (inX = px). Concave carves at the
                            // top and bottom of that edge fuse it into the frame.
                            RoundCorner {
                                implicitSize: panelJoin.r
                                color: root.cornerColor
                                x: panelJoin.edge === "right" ? (panelJoin.inX - panelJoin.r) : panelJoin.inX
                                y: panelJoin.py
                                corner: panelJoin.edge === "right" ? RoundCorner.CornerEnum.TopRight
                                                                   : RoundCorner.CornerEnum.TopLeft
                            }
                            RoundCorner {
                                implicitSize: panelJoin.r
                                color: root.cornerColor
                                x: panelJoin.edge === "right" ? (panelJoin.inX - panelJoin.r) : panelJoin.inX
                                y: panelJoin.py + panelJoin.ph - panelJoin.r
                                corner: panelJoin.edge === "right" ? RoundCorner.CornerEnum.BottomRight
                                                                   : RoundCorner.CornerEnum.BottomLeft
                            }
                        }
                    }
                }
            }
        }
    }
}
