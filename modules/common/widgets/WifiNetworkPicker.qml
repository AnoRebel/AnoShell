import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * WifiNetworkPicker — inline list of nearby Wi-Fi networks with click-to-connect.
 *
 * Revealed by the Wi-Fi quick-toggle chevron. Lists Network.friendlyWifiNetworks
 * (active first, then by signal strength), shows a lock badge for secured APs,
 * and a rescan button. Clicking a network connects to it (open networks connect
 * immediately; secured ones use nmcli which prompts via the agent if needed).
 */
Rectangle {
    id: root

    radius: Appearance?.rounding.normal ?? 12
    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
    implicitHeight: col.implicitHeight + 20

    function strengthIcon(s) {
        return s > 83 ? "signal_wifi_4_bar"
            : s > 67 ? "network_wifi"
            : s > 50 ? "network_wifi_3_bar"
            : s > 33 ? "network_wifi_2_bar"
            : s > 17 ? "network_wifi_1_bar"
            : "signal_wifi_0_bar"
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 10 }
        spacing: 6

        // Header: title + rescan
        RowLayout {
            Layout.fillWidth: true
            StyledText {
                text: "Wi-Fi networks"
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
                releaseAction: () => Network.rescanWifi()
                contentItem: MaterialSymbol {
                    text: "refresh"; iconSize: 18
                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                    color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                    rotation: Network.wifiScanning ? 360 : 0
                    Behavior on rotation { enabled: Network.wifiScanning; RotationAnimation { duration: 900; loops: Animation.Infinite } }
                }
                StyledToolTip { text: "Rescan" }
            }
        }

        // Empty / disabled states
        StyledText {
            Layout.fillWidth: true
            visible: !Network.wifiEnabled
            text: "Wi-Fi is off"
            opacity: 0.6
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
            color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
        }
        StyledText {
            Layout.fillWidth: true
            visible: Network.wifiEnabled && Network.friendlyWifiNetworks.length === 0
            text: Network.wifiScanning ? "Scanning…" : "No networks found"
            opacity: 0.6
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
            color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
        }

        // Network list
        Repeater {
            model: Network.wifiEnabled ? Network.friendlyWifiNetworks : []
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: 40
                radius: Appearance?.rounding.small ?? 8
                color: modelData.active
                    ? Qt.rgba((Appearance?.colors.colPrimary?.r ?? 0.4), (Appearance?.colors.colPrimary?.g ?? 0.33), (Appearance?.colors.colPrimary?.b ?? 0.56), 0.18)
                    : (netMouse.containsMouse ? (Appearance?.colors.colLayer2 ?? "#2B2930") : "transparent")
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                    spacing: 8

                    MaterialSymbol {
                        text: root.strengthIcon(modelData.strength); iconSize: 20
                        fill: modelData.active ? 1 : 0
                        color: modelData.active ? (Appearance?.colors.colPrimary ?? "#65558F") : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
                    }
                    StyledText {
                        text: modelData.ssid || "(hidden)"
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        font.weight: modelData.active ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        color: modelData.active ? (Appearance?.colors.colPrimary ?? "#65558F") : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
                    }
                    MaterialSymbol {
                        visible: modelData.isSecure
                        text: "lock"; iconSize: 14
                        color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                    }
                    MaterialSymbol {
                        visible: modelData.active
                        text: "check"; iconSize: 16
                        color: Appearance?.colors.colPrimary ?? "#65558F"
                    }
                }

                MouseArea {
                    id: netMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.active) Network.disconnectWifiNetwork()
                        else Network.connectToWifiNetwork(modelData)
                    }
                }
            }
        }
    }
}
