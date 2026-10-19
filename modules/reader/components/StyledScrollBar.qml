import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions

// The thin translucent scrollbar used by every list and grid in the shell.
ScrollBar {
    id: root

    property real thickness: 3
    property real handleRadius: 2
    property color handleColor: Appearance.m3colors.m3primary
    property real handleOpacity: 0.45

    policy: ScrollBar.AsNeeded

    contentItem: Rectangle {
        implicitWidth: root.thickness
        radius: root.handleRadius
        color: root.handleColor
        opacity: root.handleOpacity
    }
}
