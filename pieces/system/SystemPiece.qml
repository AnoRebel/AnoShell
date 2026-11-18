import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Bundled piece: tiles for CPU, memory and battery (ResourceUsage, Battery),
// optional CPU temperature and disk use of / (also ResourceUsage).
// Sampling runs only while ctx.live.
Item {
    id: root
    property var ctx
    property var settings: ({})
    readonly property bool live: root.ctx?.live ?? false
    readonly property bool wantTemp: root.settings?.temperature ?? false
    readonly property bool wantDisk: root.settings?.disk ?? false

    // ResourceUsage polls only while leased.
    property bool _leased: false
    onLiveChanged: root._lease(root.live)
    Component.onCompleted: root._lease(root.live)
    Component.onDestruction: root._lease(false)
    function _lease(on) {
        if (on === root._leased) return
        root._leased = on
        if (on) ResourceUsage.acquire("desktopPiece"); else ResourceUsage.release("desktopPiece")
    }

    // Temperature and disk come from ResourceUsage (sampled while leased).
    readonly property real tempC: ResourceUsage.temperature
    readonly property real diskUsed: ResourceUsage.diskUsed
    readonly property real diskSize: ResourceUsage.diskSize

    readonly property var tiles: {
        const t = [
            { icon: "memory", label: "CPU", value: ResourceUsage.cpuUsage, text: `${Math.round(ResourceUsage.cpuUsage * 100)}%` },
            { icon: "memory_alt", label: "Memory", value: ResourceUsage.memoryUsedPercentage, text: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%` }
        ]
        if (Battery.available)
            t.push({ icon: Battery.isCharging ? "battery_charging_full" : "battery_full", label: "Battery", value: Battery.percentage, text: `${Math.round(Battery.percentage * 100)}%` })
        if (root.wantTemp)
            t.push({ icon: "device_thermostat", label: "CPU temp", value: isNaN(root.tempC) ? 0 : Math.min(1, root.tempC / 100), text: isNaN(root.tempC) ? "--" : `${Math.round(root.tempC)}°` })
        if (root.wantDisk)
            t.push({ icon: "hard_drive", label: "Disk", value: isNaN(root.diskSize) ? 0 : root.diskUsed / root.diskSize, text: isNaN(root.diskSize) ? "--" : `${Math.round(root.diskUsed / root.diskSize * 100)}%` })
        return t
    }

    GridLayout {
        anchors.fill: parent
        columns: Math.max(1, Math.floor(root.width / 90))
        rowSpacing: 8; columnSpacing: 8
        Repeater {
            model: root.tiles
            ColumnLayout {
                required property var modelData
                Layout.fillWidth: true; Layout.fillHeight: true
                spacing: 4
                CircularProgress {
                    Layout.alignment: Qt.AlignHCenter
                    implicitSize: Math.min(64, Math.max(36, root.height / 2.2))
                    value: modelData.value
                    MaterialSymbol { anchors.centerIn: parent; text: modelData.icon; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                }
                StyledText { Layout.alignment: Qt.AlignHCenter; text: modelData.text; font.pixelSize: Appearance.font.pixelSize.small }
                StyledText { Layout.alignment: Qt.AlignHCenter; text: modelData.label; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest }
            }
        }
    }
}
