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
 * A full-screen, click-through layer-shell window (one per screen, on the
 * bottom layer) that draws the bar as a single Shape whose two interior corners
 * are CONCAVE (outer-curved), so the bar reads as carved out of the screen edge
 * rather than a floating strip — the noctalia/caelestia look.
 *
 * Opt-in via appearance.connectedCorners.enable. When enabled, turn the bar's
 * own background off (bars[].showBackground=false) so only this draws, else you
 * get a double background.
 *
 * First increment: horizontal TOP/BOTTOM bars (the common case). Vertical bars
 * fall back to a plain strip until the per-edge paths are extended.
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.appearance?.connectedCorners?.enable ?? false
    readonly property real radius: Config.options?.appearance?.connectedCorners?.radius ?? 18

    readonly property var barDef: (Config.options?.bars ?? [])[0] ?? ({})
    readonly property string barEdge: barDef?.edge ?? "top"
    readonly property bool barVertical: barEdge === "left" || barEdge === "right"
    readonly property real barThickness: barDef?.height
        ?? Config.options?.bar?.layout?.height
        ?? (barVertical ? Appearance.sizes.verticalBarWidth : Appearance.sizes.barHeight)
    readonly property bool barShown: GlobalStates.barOpen && !GlobalStates.screenLocked

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
            readonly property real th: root.barThickness
            readonly property real r: Math.max(0.5, Math.min(root.radius, th))
            readonly property bool isTop: root.barEdge === "top"
            readonly property color fill: Appearance?.colors.colLayer0 ?? "#1C1B1F"

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                asynchronous: true

                // ── Horizontal bar (top or bottom): strip spanning full width
                // with the two INTERIOR corners concave. For a top bar the
                // interior edge is the bottom of the strip; the concave arcs
                // sweep from the interior edge back up toward the screen edge.
                ShapePath {
                    id: barPath
                    strokeWidth: -1
                    fillColor: win.fill
                    // yEdge = the screen-edge side of the strip (0 for top bar,
                    //         sh for bottom); yIn = the interior side.
                    readonly property real yEdge: win.isTop ? 0 : (win.screen?.height ?? 0)
                    readonly property real yIn: win.isTop ? win.th : ((win.screen?.height ?? 0) - win.th)
                    readonly property real dir: win.isTop ? 1 : -1 // interior grows downward for top

                    startX: 0
                    startY: barPath.yEdge

                    // across the screen edge
                    PathLine { x: win.sw; y: barPath.yEdge }
                    // down/up to just before the interior corner
                    PathLine { x: win.sw; y: barPath.yIn - barPath.dir * win.r }
                    // concave arc: curve inward toward the screen (right corner)
                    PathArc {
                        x: win.sw - win.r
                        y: barPath.yIn
                        radiusX: win.r; radiusY: win.r
                        direction: PathArc.Counterclockwise
                    }
                    // across the interior edge
                    PathLine { x: win.r; y: barPath.yIn }
                    // concave arc back to the edge (left corner)
                    PathArc {
                        x: 0
                        y: barPath.yIn - barPath.dir * win.r
                        radiusX: win.r; radiusY: win.r
                        direction: PathArc.Counterclockwise
                    }
                    // back up/down to the screen edge, closing the path
                    PathLine { x: 0; y: barPath.yEdge }
                }
            }
        }
    }
}
