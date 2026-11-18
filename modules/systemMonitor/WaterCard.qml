import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * A card filled with water to `level` (level_wave.frag), its icon, name and value on top and, given `history`, a live
 * area graph along the bottom that slides left one step per sample.
 */
Item {
    id: root
    property string icon: ""
    property string label: ""
    property string valueText: ""
    property string detail: ""
    property real level: 0
    property color tone: Appearance.colors.colPrimary
    property var history: null
    property real radius: Appearance.rounding.small

    implicitHeight: 84

    property real _level: Math.max(0, Math.min(1, root.level))
    Behavior on _level { NumberAnimation { duration: AnimationConfig.scaledDuration(900); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Appearance.colors.colLayer2
    }
    ShaderEffect {
        anchors.fill: parent
        fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/level_wave.frag.qsb"))
        property real level: root._level
        property real phase: 0
        property real widthPx: width
        property real heightPx: height
        property real radiusPx: root.radius
        property real amp: 3.5
        property vector4d front: Qt.vector4d(root.tone.r, root.tone.g, root.tone.b, 0.32)
        property vector4d back: Qt.vector4d(root.tone.r, root.tone.g, root.tone.b, 0.16)
        NumberAnimation on phase {
            from: 0; to: Math.PI * 2; loops: Animation.Infinite
            duration: AnimationConfig.scaledDuration(3600)
            running: root.visible && AnimationConfig.continuous
        }
    }
    Graph {
        visible: !!root.history
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 1 }
        height: parent.height * 0.45
        values: root.history ?? []
        points: ResourceUsage.historyLength
        alignment: Graph.Alignment.Right
        slide: AnimationConfig.transitions
        color: root.tone
        fillOpacity: 0.8
        opacity: 0.7
    }

    ColumnLayout {
        anchors { fill: parent; margins: 10 }
        spacing: 0
        RowLayout {
            spacing: 6
            MaterialSymbol { text: root.icon; iconSize: 16; color: root.tone }
            StyledText { text: root.label; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer2 }
        }
        StyledText {
            text: root.valueText
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.DemiBold
            font.family: Appearance.font.family.mono
            color: Appearance.colors.colOnLayer2
        }
        StyledText {
            visible: text !== ""
            text: root.detail
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colOnLayer2
            opacity: 0.75
        }
        Item { Layout.fillHeight: true }
    }
}
