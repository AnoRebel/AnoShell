import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.bar

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
    readonly property color frameColor: Appearance?.colors.colLayer0 ?? "#1C1B1F"
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

            // The bar definitions that actually render on THIS screen.
            readonly property var screenBars: root.barDefs.filter(d =>
                root.barOnScreen(d, screenName) && !(d?.morphingPanel ?? false))

            // Per-bar geometry helper (screen-space placeholder rect). Returns a
            // zero-size rect for an absent slot so unused mask/bar slots vanish.
            function barRect(i) {
                const def = win.screenBars[i]
                if (!def) return { x: 0, y: 0, w: 0, h: 0, vertical: false, edge: "top", present: false }
                const m = root.globalMargin
                const vertical = root.barIsVertical(def)
                const th = root.barThickness(def)
                const edge = def?.edge ?? "top"
                const x = edge === "right" ? (sw - th - m) : m
                const y = edge === "bottom" ? (sh - th - m) : m
                const w = vertical ? th : (sw - m * 2)
                const h = vertical ? (sh - m * 2) : th
                return { x: x, y: y, w: w, h: h, vertical: vertical, edge: edge, present: true, def: def }
            }

            // ── Input mask: click-through except each visible bar. FIXED slots
            // (Region.regions can't be populated by a Repeater). 4 bars is plenty.
            mask: Region {
                Region { readonly property var g: win.barShownRect(0); x: g.x; y: g.y; width: g.w; height: g.h }
                Region { readonly property var g: win.barShownRect(1); x: g.x; y: g.y; width: g.w; height: g.h }
                Region { readonly property var g: win.barShownRect(2); x: g.x; y: g.y; width: g.w; height: g.h }
                Region { readonly property var g: win.barShownRect(3); x: g.x; y: g.y; width: g.w; height: g.h }
            }
            // barRect gated by barsShown (mask must collapse when bars hidden).
            function barShownRect(i) {
                return root.barsShown ? win.barRect(i) : { x: 0, y: 0, w: 0, h: 0 }
            }

            // ── All visual content, attached ASYNCHRONOUSLY ───────────────
            // The corner Shapes + bar content are a deep item tree; attaching it
            // synchronously while the layershell window is still acquiring its
            // surface drives the QS 0.3.0 refWindow recursion segfault (same bug
            // BarWindow dodges). One async Loader defers the whole subtree to a
            // later event-loop turn, after the window is realised.
            Loader {
                anchors.fill: parent
                asynchronous: true
                active: true
                sourceComponent: Item {
                    anchors.fill: parent

                    // Rounded outer screen corners
                    RoundCorner {
                        anchors.top: parent.top; anchors.left: parent.left
                        implicitSize: root.cornerRadius; color: root.frameColor
                        corner: RoundCorner.CornerEnum.TopLeft
                    }
                    RoundCorner {
                        anchors.top: parent.top; anchors.right: parent.right
                        implicitSize: root.cornerRadius; color: root.frameColor
                        corner: RoundCorner.CornerEnum.TopRight
                    }
                    RoundCorner {
                        anchors.bottom: parent.bottom; anchors.left: parent.left
                        implicitSize: root.cornerRadius; color: root.frameColor
                        corner: RoundCorner.CornerEnum.BottomLeft
                    }
                    RoundCorner {
                        anchors.bottom: parent.bottom; anchors.right: parent.right
                        implicitSize: root.cornerRadius; color: root.frameColor
                        corner: RoundCorner.CornerEnum.BottomRight
                    }

                    // Each bar, rendered in-window (fixed 4 slots)
                    Repeater {
                        model: 4
                        Item {
                            id: barItem
                            required property int index
                            readonly property var g: win.barRect(index)
                            x: g.x; y: g.y; width: g.w; height: g.h
                            visible: root.barsShown && g.present

                            Rectangle {
                                anchors.fill: parent
                                radius: root.cornerRadius
                                color: root.frameColor
                                border.width: 1
                                border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
                            }

                            Loader {
                                anchors.fill: parent
                                asynchronous: true
                                active: barItem.visible
                                sourceComponent: BarContent {
                                    barConfig: barItem.g.def
                                    isVertical: barItem.g.vertical
                                    edge: barItem.g.edge
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
