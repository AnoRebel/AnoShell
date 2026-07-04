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
    readonly property color cornerColor: Appearance?.colors.colShadow ?? "#000000"
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

            // Fully click-through: AnoScreen is purely decorative now (corners +
            // bar background). Bar input is handled by the separate BarWindow that
            // sits over the bar area, so this window needs no interactive regions.
            mask: Region {}

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

                    // Each bar, rendered in-window (fixed 4 slots)
                    Repeater {
                        model: 4
                        Item {
                            id: barItem
                            required property int index
                            readonly property var g: win.barRect(index)
                            // Constant thickness axis: derive the bar's thickness
                            // from config (NOT the growing window), so BarContent's
                            // Layout.fillHeight/Width resolves against a fixed size
                            // and never re-lays-out chasing a 0→fullscreen parent
                            // (the structural difference that crashes vs BarWindow).
                            readonly property real th: g.present ? root.barThickness(g.def) : 0
                            x: g.x; y: g.y
                            width: g.vertical ? th : g.w
                            height: g.vertical ? g.h : th
                            visible: root.barsShown && g.present
                            readonly property bool isTop: g.edge === "top"
                            readonly property bool isBottom: g.edge === "bottom"

                            // Flush bar background (no rounding on the edge side).
                            Rectangle {
                                anchors.fill: parent
                                color: root.frameColor
                            }

                            // Concave carves at the bar's INTERIOR corners so the
                            // bar fuses into the screen edge (the connected look)
                            // instead of reading as a floating rounded pill. For a
                            // top bar these sit at the two bottom corners and curve
                            // the frame colour outward into the edge.
                            RoundCorner {
                                visible: barItem.isTop || barItem.isBottom
                                anchors.left: parent.left
                                anchors.top: barItem.isBottom ? parent.top : undefined
                                anchors.bottom: barItem.isTop ? parent.bottom : undefined
                                // sit just OUTSIDE the bar's interior edge
                                anchors.topMargin: barItem.isBottom ? -root.cornerRadius : 0
                                anchors.bottomMargin: barItem.isTop ? -root.cornerRadius : 0
                                implicitSize: root.cornerRadius
                                color: root.frameColor
                                corner: barItem.isTop ? RoundCorner.CornerEnum.TopLeft : RoundCorner.CornerEnum.BottomLeft
                            }
                            RoundCorner {
                                visible: barItem.isTop || barItem.isBottom
                                anchors.right: parent.right
                                anchors.bottom: barItem.isTop ? parent.bottom : undefined
                                anchors.top: barItem.isBottom ? parent.top : undefined
                                anchors.topMargin: barItem.isBottom ? -root.cornerRadius : 0
                                anchors.bottomMargin: barItem.isTop ? -root.cornerRadius : 0
                                implicitSize: root.cornerRadius
                                color: root.frameColor
                                corner: barItem.isTop ? RoundCorner.CornerEnum.TopRight : RoundCorner.CornerEnum.BottomRight
                            }

                            // NOTE: the bar CONTENT (widgets) is NOT hosted here.
                            // Attaching that deep tree into this full-screen window
                            // triggers the QS 0.3.0 refWindow segfault (~50% cold
                            // starts). Noctalia hit the same wall and solved it by
                            // keeping bar content in a SEPARATE thin window
                            // (BarContentWindow) — so ano keeps its stable BarWindow
                            // (loaded by BarManager) and AnoScreen draws only the
                            // corners + bar background/frame beneath it.
                        }
                    }
                }
            }
        }
    }
}
