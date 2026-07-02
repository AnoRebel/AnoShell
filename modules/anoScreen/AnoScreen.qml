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
 * the window mask so only the bars (and, later, open panels) are interactive.
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

            // Per-bar geometry helper (screen-space placeholder rect).
            function barRect(def) {
                const m = root.globalMargin
                const vertical = root.barIsVertical(def)
                const th = root.barThickness(def)
                const edge = def?.edge ?? "top"
                const x = edge === "right" ? (sw - th - m) : m
                const y = edge === "bottom" ? (sh - th - m) : m
                const w = vertical ? th : (sw - m * 2)
                const h = vertical ? (sh - m * 2) : th
                return { x: x, y: y, w: w, h: h, vertical: vertical, edge: edge }
            }

            // ── Input mask: click-through everywhere except each visible bar ──
            mask: Region {
                Repeater {
                    model: root.barsShown ? win.screenBars : []
                    Region {
                        required property var modelData
                        readonly property var g: win.barRect(modelData)
                        x: g.x; y: g.y; width: g.w; height: g.h
                    }
                }
            }

            // ── Rounded outer screen corners ──────────────────────────────
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

            // ── Each bar, rendered in-window ──────────────────────────────
            Repeater {
                model: win.screenBars
                Item {
                    id: barItem
                    required property var modelData
                    readonly property var g: win.barRect(modelData)
                    x: g.x; y: g.y; width: g.w; height: g.h
                    visible: root.barsShown

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
                        active: true
                        sourceComponent: BarContent {
                            barConfig: barItem.modelData
                            isVertical: barItem.g.vertical
                            edge: barItem.g.edge
                        }
                    }
                }
            }
        }
    }
}
