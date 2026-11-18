import QtQuick
import QtQuick.Shapes

// One filled (and optionally stroked) SVG path in the rig's 100 × 100 space; curve-rendered, so sharp at any size.
Shape {
    id: root
    property string d
    property color fill: "transparent"
    property color stroke: "transparent"
    property real strokeW: -1
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        fillColor: root.fill
        strokeColor: root.stroke
        strokeWidth: root.strokeW
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: root.d }
    }
}
