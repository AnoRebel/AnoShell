import QtQuick
import qs.modules.common
import qs.modules.common.functions

// A full-area "working on it" overlay: the spinner with a small caption and an
// optional detail line (which chapter, which episode). Fades in and out with
// `active`; set `color` for the backdrop (transparent-ish to keep what's
// behind in view).
Rectangle {
    id: root

    property bool active: false
    property string label: "loading"
    property string detail: ""
    property string bodyFont: Appearance.font.family.main
    property int spinnerSize: 34
    property color textColor: Appearance.m3colors.m3onSurfaceVariant
    property color arcColor: Appearance.m3colors.m3primary

    color: Appearance.colors.colLayer0Base
    opacity: root.active ? 1 : 0
    visible: root.opacity > 0
    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(220); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

    // Swallow clicks so nothing behind reacts while this is up.
    MouseArea { anchors.fill: parent; enabled: root.active }

    Column {
        anchors.centerIn: parent
        spacing: 14

        Spinner {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.spinnerSize
            border.width: 2.5
            arcColor: root.arcColor
            period: 1000
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 5

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.label
                color: root.textColor
                font.family: root.bodyFont
                font.pixelSize: 11
                font.letterSpacing: 2.5
                opacity: 0.75
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.detail.length > 0
                width: Math.min(implicitWidth, 280)
                horizontalAlignment: Text.AlignHCenter
                text: root.detail
                color: root.textColor
                font.family: root.bodyFont
                font.pixelSize: 11
                elide: Text.ElideRight
                opacity: 0.45
            }
        }
    }
}
