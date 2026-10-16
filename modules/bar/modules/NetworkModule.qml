import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Network status icon with rich hover popup showing connection details,
 * signal strength, network speed, and WiFi toggle.
 */
Item {
    id: root
    // ResourceUsage polls only while a visible consumer holds a lease.
    ServiceLease { service: ResourceUsage; name: "barNetworkPopup"; active: root.hovered }

    property bool vertical: false
    implicitWidth: icon.implicitWidth + 8
    implicitHeight: vertical ? icon.implicitHeight + 8 : Appearance.sizes.barHeight
    property bool hovered: netMA.containsMouse

    MaterialSymbol {
        id: icon
        anchors.centerIn: parent
        text: Network.materialSymbol
        iconSize: Appearance?.font.pixelSize.larger ?? 20
        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
    }

    // Left-click pins the popout open so the network picker is usable (hover
    // alone would dismiss it as you move to the popup). Click again to unpin.
    property bool pinned: false

    MouseArea {
        id: netMA
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pinned = !root.pinned
    }

    BarModulePopout {
        shown: root.hovered || root.pinned
        popupWidth: 280; popupHeight: netPopupCol.implicitHeight + 24

        ColumnLayout {
            id: netPopupCol
            anchors.fill: parent; spacing: 8

            RowLayout {
                Layout.fillWidth: true; spacing: 10
                MaterialSymbol { text: Network.materialSymbol; iconSize: 28; color: Appearance?.colors.colPrimary ?? "#65558F"; fill: 1 }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    StyledText { text: Network.ethernet ? "Ethernet" : (Network.wifi ? Network.networkName : "Disconnected"); font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                    StyledText { text: Network.wifiStatus; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.5 }
                }
            }

            Loader {
                Layout.fillWidth: true; active: Network.wifi; visible: active
                sourceComponent: ColumnLayout {
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { text: "Signal"; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.5; Layout.fillWidth: true }
                        StyledText { text: `${Network.networkStrength}%`; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" }
                    }
                    StyledProgressBar { Layout.fillWidth: true; valueBarHeight: 4; value: Network.networkStrength / 100 }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 12
                RowLayout {
                    spacing: 4
                    MaterialSymbol { text: "arrow_downward"; iconSize: 14; color: Appearance.colors.colSuccess }
                    StyledText { text: formatSpeed(ResourceUsage.networkDownloadSpeed); font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" }
                }
                RowLayout {
                    spacing: 4
                    MaterialSymbol { text: "arrow_upward"; iconSize: 14; color: Appearance.colors.colError }
                    StyledText { text: formatSpeed(ResourceUsage.networkUploadSpeed); font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                StyledText { text: "WiFi"; font.pixelSize: Appearance.font.pixelSize.smaller; Layout.fillWidth: true }
                StyledSwitch { checked: Network.wifiEnabled; onCheckedChanged: Network.enableWifi(checked) }
            }

            // Network picker — only when the popout is pinned (left-clicked), so
            // the hover preview stays a lightweight status glance. Shared with
            // the right-sidebar Wi-Fi expander (one component, two homes).
            Loader {
                Layout.fillWidth: true
                active: root.pinned
                visible: active
                sourceComponent: WifiNetworkPicker {}
            }
        }
    }

    function formatSpeed(bps) { return bps < 1024 ? `${Math.round(bps)} B/s` : bps < 1048576 ? `${(bps / 1024).toFixed(1)} KB/s` : `${(bps / 1048576).toFixed(1)} MB/s` }
}
