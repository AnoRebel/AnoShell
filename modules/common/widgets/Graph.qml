import QtQuick
import qs.modules.common
import qs.modules.common.functions

/**
 * Simple one-value line graph with fill.
 */
Canvas {
    id: root

    enum Alignment { Left, Right }

    required property list<real> values
    property int points: values.length
    property color color: Appearance.colors.colPrimary
    property real fillOpacity: 0.5
    property var alignment: Graph.Alignment.Left
    // slide: each new value slides the graph left one step instead of jumping (newest at the right edge).
    property bool slide: false
    property real _shift: 0
    on_ShiftChanged: root.requestPaint()
    NumberAnimation on _shift { id: shiftAnim; running: false; from: 1; to: 0; duration: AnimationConfig.scaledDuration(450); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }

    onValuesChanged: { if (root.slide) shiftAnim.restart(); root.requestPaint() }
    onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        if (!root.values || root.values.length < 2) return

        var n = root.points
        var dx = width / (n - 1)
        ctx.strokeStyle = root.color
        ctx.fillStyle = ColorUtils.transparentize(root.color, root.fillOpacity) // sets alpha
        ctx.lineWidth = 2
        ctx.beginPath()
        var started = false
        for (var i = 0; i < n; ++i) {
            var valueIndex = (root.alignment === Graph.Alignment.Right) ? root.values.length - n + i : i
            if (valueIndex < 0 || valueIndex >= root.values.length) continue
            var x = (i + root._shift) * dx
            var y = height - root.values[valueIndex] * height
            if (!started) { ctx.moveTo(x, height); ctx.lineTo(x, y); started = true }
            else ctx.lineTo(x, y)
        }
        ctx.stroke()
        ctx.lineTo(width, height)
        ctx.fill()
    }
}
