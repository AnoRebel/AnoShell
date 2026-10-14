import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * BluetoothDevicePicker — inline list of Bluetooth devices with connect/disconnect.
 *
 * Revealed by the Bluetooth quick-toggle chevron. Lists connected, then paired,
 * then discovered devices (BluetoothStatus.friendlyDeviceList). Clicking a device
 * connects or disconnects it. A scan toggle discovers new devices.
 */
Rectangle {
    id: root

    radius: Appearance?.rounding.normal ?? 12
    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
    implicitHeight: col.implicitHeight + 20

    readonly property var adapter: Bluetooth.defaultAdapter

    function deviceIcon(dev) {
        const n = (dev?.name ?? "").toLowerCase()
        if (n.includes("head") || n.includes("buds") || n.includes("air") || n.includes("pod")) return "headphones"
        if (n.includes("speaker")) return "speaker"
        if (n.includes("mouse")) return "mouse"
        if (n.includes("key")) return "keyboard"
        if (n.includes("phone")) return "smartphone"
        if (n.includes("watch")) return "watch"
        return "bluetooth"
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 10 }
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: "Bluetooth devices"
                font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                font.weight: Font.DemiBold
                color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                Layout.fillWidth: true
            }
            RippleButton {
                implicitWidth: 28; implicitHeight: 28
                buttonRadius: Appearance?.rounding.full ?? 9999
                colBackground: "transparent"
                colBackgroundHover: Appearance?.colors.colLayer2 ?? "#2B2930"
                enabled: root.adapter?.enabled ?? false
                releaseAction: () => { if (root.adapter) root.adapter.discovering = !(root.adapter.discovering ?? false) }
                contentItem: MaterialSymbol {
                    text: (root.adapter?.discovering ?? false) ? "bluetooth_searching" : "search"
                    iconSize: 18
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                }
                StyledToolTip { text: (root.adapter?.discovering ?? false) ? "Stop scanning" : "Scan for devices" }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: !(root.adapter?.enabled ?? false)
            text: "Bluetooth is off"
            opacity: 0.6
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
            color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
        }
        StyledText {
            Layout.fillWidth: true
            visible: (root.adapter?.enabled ?? false) && BluetoothStatus.friendlyDeviceList.length === 0
            text: (root.adapter?.discovering ?? false) ? "Scanning…" : "No devices — tap scan"
            opacity: 0.6
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
            color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
        }

        Repeater {
            model: (root.adapter?.enabled ?? false) ? BluetoothStatus.friendlyDeviceList : []
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance?.rounding.small ?? 8
                color: modelData.connected
                    ? Qt.rgba(0.70, 0.53, 1.0, 0.18)
                    : (devMouse.containsMouse ? (Appearance?.colors.colLayer2 ?? "#2B2930") : "transparent")
                Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(150) } }

                RowLayout {
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    spacing: 8
                    MaterialSymbol {
                        text: root.deviceIcon(modelData); iconSize: 20
                        fill: modelData.connected ? 1 : 0
                        color: modelData.connected ? "#B388FF" : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
                    }
                    ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        StyledText {
                            text: modelData.name || modelData.address || "Device"
                            font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                            font.weight: modelData.connected ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            color: modelData.connected ? "#B388FF" : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
                        }
                        StyledText {
                            visible: modelData.connected || modelData.paired
                            text: modelData.connected ? "Connected" : "Paired"
                            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                            opacity: 0.6
                            color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                        }
                    }
                    MaterialSymbol {
                        visible: modelData.connected
                        text: "check"; iconSize: 16
                        color: "#B388FF"
                    }
                }

                MouseArea {
                    id: devMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Quickshell.Bluetooth BluetoothDevice: `connected` is a
                        // settable property (setting it triggers connect/disconnect).
                        modelData.connected = !modelData.connected
                    }
                }
            }
        }
    }
}
