// AnoShell's own face (inspired by Anserin's wavy clock).
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.modules.common

// Wavy face: a scalloped dial in the palette's container colour, rounded hands that turn with a short eased step and,
// with `seconds` on, a seconds arc whose head jumps ahead each second and whose tail catches up, so it stretches.
Item {
    id: root

    property date now: new Date()
    property bool seconds: true

    implicitWidth: 320
    implicitHeight: 320
    readonly property real r: 150
    readonly property real cx: width / 2
    readonly property real cy: height / 2

    // Angles keep growing (minutes and seconds since the epoch, local time) so a hand never turns back at 12.
    readonly property real localMs: root.now.getTime() - root.now.getTimezoneOffset() * 60000
    readonly property real minuteTurn: Math.floor(root.localMs / 60000) * 6
    readonly property real hourTurn: Math.floor(root.localMs / 60000) * 0.5
    readonly property real secondTurn: Math.floor(root.localMs / 1000) * 6

    function scallop(n, amp, rad) {
        const pts = []
        for (let i = 0; i <= 360; i++) {
            const t = i / 360 * Math.PI * 2
            const rr = rad + amp * Math.cos(t * n)
            pts.push(Qt.point(root.cx + rr * Math.sin(t), root.cy - rr * Math.cos(t)))
        }
        return pts
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 0; strokeColor: "transparent"
            fillColor: Appearance.m3colors.m3primaryContainer
            PathPolyline { path: root.scallop(12, 7, root.r - 7) }
        }
    }
    // Four marks.
    Repeater {
        model: 4
        Rectangle {
            required property int index
            width: 10; height: 10; radius: 5
            color: Qt.alpha(Appearance.m3colors.m3onPrimaryContainer, 0.45)
            x: root.cx + Math.sin(index * Math.PI / 2) * (root.r - 34) - 5
            y: root.cy - Math.cos(index * Math.PI / 2) * (root.r - 34) - 5
        }
    }

    // Seconds arc.
    property real head: root.secondTurn
    property real tail: root.secondTurn - 30
    Behavior on head { enabled: root.seconds; NumberAnimation { duration: AnimationConfig.scaledDuration(320); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
    Behavior on tail { enabled: root.seconds; NumberAnimation { duration: AnimationConfig.scaledDuration(780); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard } }
    Shape {
        anchors.fill: parent
        visible: root.seconds
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Appearance.m3colors.m3tertiary; strokeWidth: 6
            fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.cx; centerY: root.cy
                radiusX: root.r - 18; radiusY: root.r - 18
                startAngle: (root.tail % 360) - 90
                sweepAngle: Math.max(2, root.head - root.tail)
            }
        }
    }

    Hand { length: root.r * 0.5; thickness: 16; angle: root.hourTurn; color: Appearance.m3colors.m3onPrimaryContainer }
    Hand { length: root.r * 0.74; thickness: 11; angle: root.minuteTurn; color: Appearance.m3colors.m3primary }
    Rectangle {
        width: 14; height: 14; radius: 7
        x: root.cx - 7; y: root.cy - 7
        color: Appearance.m3colors.m3primaryContainer
        border.width: 3; border.color: Appearance.m3colors.m3primary
    }

    component Hand: Rectangle {
        id: hand
        property real length: 60
        property real thickness: 10
        property real angle: 0
        width: hand.thickness
        height: hand.length + hand.thickness / 2
        radius: hand.thickness / 2
        x: root.cx - hand.thickness / 2
        y: root.cy - hand.length
        // Turns about the dial's centre, half a thickness above its rounded end.
        transform: Rotation { origin.x: hand.thickness / 2; origin.y: hand.length; angle: hand.shown }
        property real shown: hand.angle
        Behavior on shown { NumberAnimation { duration: AnimationConfig.scaledDuration(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
    }
}
