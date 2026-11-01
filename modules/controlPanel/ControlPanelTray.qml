import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.bar.modules

/**
 * The control panel's tray row (controlPanel.tray): the bar tray's items and
 * menus, while an app has one. Its own file: importing the bar modules into
 * ControlPanelContent stops its inline components resolving.
 */
Rectangle {
    visible: (Config.options?.controlPanel?.tray ?? true) && SystemTray.items.values.length > 0
    implicitHeight: 36
    radius: Appearance?.rounding.normal ?? 12
    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
    RowLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
        spacing: 6
        StyledText { text: "System tray"; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.6; Layout.fillWidth: true }
        TrayModule { showAll: true; Layout.preferredHeight: 28 }
    }
}
