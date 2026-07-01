import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * ConnectedBackground — seamless "flows from the shell" bar background.
 *
 * One full-screen, click-through, bottom-layer window per screen. Inside a
 * single Shape it draws EACH configured bar (Config.options.bars) as a strip
 * whose two INTERIOR corners are CONCAVE (outer-curved), so every bar reads as
 * carved out of the screen edge — the noctalia/caelestia look. Multiple bars are
 * handled by a Repeater of ShapePaths in the one Shape (unified GPU pass).
 *
 * Opt-in via appearance.connectedCorners.enable. When enabled, turn the bars'
 * own background off (global bar.showBackground=false) so only this draws.
 *
 * Horizontal (top/bottom) bars get concave corners; vertical (left/right) bars
 * fall back to a plain rounded strip until their per-edge paths are added.
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.appearance?.connectedCorners?.enable ?? false
    readonly property real radius: Config.options?.appearance?.connectedCorners?.radius ?? 18
    readonly property var barDefs: Config.options?.bars ?? []
    readonly property bool barShown: GlobalStates.barOpen && !GlobalStates.screenLocked
    readonly property color fill: Appearance?.colors.colLayer0 ?? "#1C1B1F"

    // Resolve a bar definition's thickness (per-bar → global → Appearance).
    function barThickness(def) {
        const vertical = (def?.edge === "left" || def?.edge === "right")
        return def?.height
            ?? Config.options?.bar?.layout?.height
            ?? (vertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight)
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:connectedBg"
            WlrLayershell.layer: WlrLayer.Bottom
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {} // fully click-through — purely decorative

            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.enabled && root.barShown

            readonly property real sw: screen?.width ?? 0
            readonly property real sh: screen?.height ?? 0

            // One Shape per bar (a Shape IS an Item, so it's a valid Repeater
            // delegate — a ShapePath is not, which is why we don't Repeater
            // ShapePaths directly). Each draws a concave HORIZONTAL (top/bottom)
            // bar; vertical/morphing bars draw nothing (their own bg stays on).
            Repeater {
                model: root.barDefs

                Shape {
                    id: barShape
                    required property var modelData
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    asynchronous: true

                    readonly property string edge: modelData?.edge ?? "top"
                    readonly property bool horizontal: edge === "top" || edge === "bottom"
                    readonly property bool active: horizontal && !(modelData?.morphingPanel ?? false)
                    readonly property real th: root.barThickness(modelData)
                    readonly property real r: Math.max(0.5, Math.min(root.radius, th))
                    // Strip edges: screen-edge side vs interior side. When
                    // inactive, collapse to an off-screen degenerate point.
                    readonly property real yEdge: active ? (edge === "top" ? 0 : win.sh) : -2
                    readonly property real yIn: active ? (edge === "top" ? th : (win.sh - th)) : -1
                    readonly property real dir: edge === "top" ? 1 : -1

                    ShapePath {
                        strokeWidth: -1
                        fillColor: barShape.active ? root.fill : "transparent"
                        startX: 0
                        startY: barShape.yEdge

                        PathLine { x: barShape.active ? win.sw : 0; y: barShape.yEdge }
                        PathLine { x: barShape.active ? win.sw : 0; y: barShape.yIn - barShape.dir * barShape.r }
                        PathArc {
                            x: barShape.active ? (win.sw - barShape.r) : -0.5
                            y: barShape.yIn
                            radiusX: barShape.r; radiusY: barShape.r
                            direction: PathArc.Counterclockwise
                        }
                        PathLine { x: barShape.active ? barShape.r : -0.5; y: barShape.yIn }
                        PathArc {
                            x: 0
                            y: barShape.yIn - barShape.dir * barShape.r
                            radiusX: barShape.r; radiusY: barShape.r
                            direction: PathArc.Counterclockwise
                        }
                        PathLine { x: 0; y: barShape.yEdge }
                    }
                }
            }
        }
    }
}
