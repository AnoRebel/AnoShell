import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * ConnectedBackground — seamless "flows from one shell" frame.
 *
 * One full-screen, click-through, bottom-layer window per screen. It draws, in a
 * single Shape (unified GPU pass), the shell's connected surface:
 *
 *   1. Rounded OUTER screen corners — 4 filled wedges that carve the screen's
 *      corners into a rounded frame, so the desktop reads as living inside a
 *      rounded window rather than a hard rectangle.
 *   2. Each configured bar as a strip fused to its screen edge, with CONCAVE
 *      interior corners so it flows out of the frame edge.
 *
 * Panels (sidebars/popups) connecting into the same frame is the next layer.
 *
 * Opt-in via appearance.connectedCorners.enable. Excluded from compositor blur
 * (see the connectedBg layer rule) so only the drawn shapes show — no ghost
 * blur strip. When enabled, the bars' own backgrounds are turned off (global
 * bar.showBackground=false, handled by the settings toggle) to avoid doubling.
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.appearance?.connectedCorners?.enable ?? false
    readonly property real radius: Config.options?.appearance?.connectedCorners?.radius ?? 18
    readonly property var barDefs: Config.options?.bars ?? []
    readonly property bool barShown: GlobalStates.barOpen && !GlobalStates.screenLocked
    readonly property color fill: Appearance?.colors.colLayer0 ?? "#1C1B1F"

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
            visible: root.enabled

            readonly property real sw: screen?.width ?? 0
            readonly property real sh: screen?.height ?? 0
            readonly property real r: Math.max(0.5, root.radius)

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                asynchronous: true

                // ── Rounded outer screen corners ──────────────────────────
                // Four filled "wedges" (square minus a quarter-circle) that sit
                // in each screen corner, coloured as the frame, so the desktop
                // appears clipped to a rounded rectangle. Concave arcs.
                Repeater {
                    model: [
                        { cx: 0,        cy: 0,        sx: 1,  sy: 1  }, // top-left
                        { cx: win.sw,   cy: 0,        sx: -1, sy: 1  }, // top-right
                        { cx: win.sw,   cy: win.sh,   sx: -1, sy: -1 }, // bottom-right
                        { cx: 0,        cy: win.sh,   sx: 1,  sy: -1 }  // bottom-left
                    ]
                    Shape {
                        id: cornerShape
                        required property var modelData
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        asynchronous: true
                        readonly property real cx: modelData.cx
                        readonly property real cy: modelData.cy
                        readonly property real sx: modelData.sx // +1 grows right, -1 left
                        readonly property real sy: modelData.sy // +1 grows down, -1 up
                        readonly property real rr: win.r

                        ShapePath {
                            strokeWidth: -1
                            fillColor: root.fill
                            // Corner square from (cx,cy) extending by rr in sx/sy,
                            // with the inner quarter carved by a concave arc.
                            startX: cornerShape.cx
                            startY: cornerShape.cy
                            PathLine { x: cornerShape.cx + cornerShape.sx * cornerShape.rr; y: cornerShape.cy }
                            PathArc {
                                x: cornerShape.cx
                                y: cornerShape.cy + cornerShape.sy * cornerShape.rr
                                radiusX: cornerShape.rr; radiusY: cornerShape.rr
                                // XOR of the two sign flips → concave (counter-clockwise)
                                direction: ((cornerShape.sx < 0) !== (cornerShape.sy < 0))
                                    ? PathArc.Clockwise : PathArc.Counterclockwise
                            }
                            PathLine { x: cornerShape.cx; y: cornerShape.cy }
                        }
                    }
                }

                // ── Bars fused to their screen edge (concave interior corners) ──
                Repeater {
                    model: root.barShown ? root.barDefs : []

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
                        readonly property real cr: Math.max(0.5, Math.min(root.radius, th))
                        readonly property real yEdge: active ? (edge === "top" ? 0 : win.sh) : -2
                        readonly property real yIn: active ? (edge === "top" ? th : (win.sh - th)) : -1
                        readonly property real dir: edge === "top" ? 1 : -1

                        ShapePath {
                            strokeWidth: -1
                            fillColor: barShape.active ? root.fill : "transparent"
                            startX: 0
                            startY: barShape.yEdge
                            PathLine { x: barShape.active ? win.sw : 0; y: barShape.yEdge }
                            PathLine { x: barShape.active ? win.sw : 0; y: barShape.yIn - barShape.dir * barShape.cr }
                            PathArc {
                                x: barShape.active ? (win.sw - barShape.cr) : -0.5
                                y: barShape.yIn
                                radiusX: barShape.cr; radiusY: barShape.cr
                                direction: PathArc.Counterclockwise
                            }
                            PathLine { x: barShape.active ? barShape.cr : -0.5; y: barShape.yIn }
                            PathArc {
                                x: 0
                                y: barShape.yIn - barShape.dir * barShape.cr
                                radiusX: barShape.cr; radiusY: barShape.cr
                                direction: PathArc.Counterclockwise
                            }
                            PathLine { x: 0; y: barShape.yEdge }
                        }
                    }
                }
            }
        }
    }
}
