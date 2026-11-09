import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// The count of QML warnings/errors the shell logged (ShellErrors), on About
// in the Settings rail; red when one is an error.
Rectangle {
    id: root
    readonly property int count: ShellErrors.count
    implicitWidth: Math.max(implicitHeight, label.implicitWidth + 10)
    implicitHeight: label.implicitHeight + 2
    radius: height / 2
    color: ShellErrors.errors > 0 ? Appearance.m3colors.m3error : Appearance.colors.colWarning
    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.count > 99 ? "99+" : String(root.count)
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: ShellErrors.errors > 0 ? Appearance.m3colors.m3onError : Appearance.m3colors.m3surface
    }
}
