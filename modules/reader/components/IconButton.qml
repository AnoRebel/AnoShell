import QtQuick
import qs.modules.common.widgets
import qs.modules.common
import qs.modules.common.functions

// Round icon-only button that tints its background on hover.
ClickableRect {
    id: root

    property alias icon: glyph.text
    property int iconSize: 16
    property color iconColor: Appearance.m3colors.m3onSurfaceVariant
    property color hoverColor: Appearance.colors.colLayer4
    property color idleColor: "transparent"

    implicitWidth: 30
    implicitHeight: 30
    radius: root.width / 2
    color: root.hovered ? root.hoverColor : root.idleColor

    MaterialSymbol {
        id: glyph
        anchors.centerIn: parent
        iconSize: root.iconSize
        color: root.iconColor
    }
}
