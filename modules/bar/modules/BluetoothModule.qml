import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Bluetooth status icon with morph-capable popout showing device list.
 */
Item {
    id: root
    visible: BluetoothStatus.available
    property bool vertical: false
    implicitWidth: icon.implicitWidth + 8
    implicitHeight: vertical ? icon.implicitHeight + 8 : Appearance.sizes.barHeight
    property bool hovered: btMA.containsMouse
    // Left-click pins the popout so the device picker is usable.
    property bool pinned: false

    MaterialSymbol {
        id: icon; anchors.centerIn: parent
        text: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
        iconSize: Appearance?.font.pixelSize.larger ?? 20
        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
    }

    MouseArea {
        id: btMA; anchors.fill: parent; hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pinned = !root.pinned
    }

    BarModulePopout {
        shown: root.hovered || root.pinned
        popupWidth: 280; popupHeight: btPopupCol.implicitHeight + 24

        ColumnLayout {
            id: btPopupCol; anchors.fill: parent; spacing: 8

            RowLayout {
                spacing: 10
                MaterialSymbol { text: "bluetooth"; iconSize: 24; fill: 1; color: Appearance?.colors.colPrimary ?? "#65558F" }
                StyledText { text: "Bluetooth"; font.pixelSize: 16; font.weight: Font.DemiBold; Layout.fillWidth: true }
                StyledText { text: BluetoothStatus.enabled ? "On" : "Off"; font.pixelSize: 12; opacity: 0.4 }
            }

            // Connected devices
            Repeater {
                model: BluetoothStatus.connectedDevices
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 8
                    MaterialSymbol { text: "devices"; iconSize: 16; color: "#81C784" }
                    StyledText { text: modelData.name ?? "Unknown"; font.pixelSize: 13; Layout.fillWidth: true }
                    StyledText { text: "Connected"; font.pixelSize: 10; opacity: 0.4; color: "#81C784" }
                }
            }

            // Paired but not connected
            Repeater {
                model: BluetoothStatus.pairedButNotConnectedDevices.slice(0, 5)
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 8
                    MaterialSymbol { text: "devices"; iconSize: 16; opacity: 0.3 }
                    StyledText { text: modelData.name ?? "Unknown"; font.pixelSize: 13; opacity: 0.5; Layout.fillWidth: true }
                    StyledText { text: "Paired"; font.pixelSize: 10; opacity: 0.3 }
                }
            }

            StyledText {
                visible: BluetoothStatus.friendlyDeviceList.length === 0 && !root.pinned
                text: "No devices"; font.pixelSize: 12; opacity: 0.4; Layout.alignment: Qt.AlignHCenter
            }

            // Interactive device picker (connect/disconnect/scan) — only when
            // pinned (left-clicked). Shared with the right-sidebar BT expander.
            Loader {
                Layout.fillWidth: true
                active: root.pinned
                visible: active
                sourceComponent: BluetoothDevicePicker {}
            }
        }
    }
}
