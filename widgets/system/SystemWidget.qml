import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Bundled widget: tiles for CPU, memory and battery (ResourceUsage, Battery),
// optional CPU temperature (the x86_pkg_temp thermal zone, else the first)
// and disk use of /. Sampling runs only while ctx.live.
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
        if (on) ResourceUsage.acquire("desktopWidget"); else ResourceUsage.release("desktopWidget")
    }

    // Temperature: pick the zone once, then read it every 5 s.
    property string tempPath: ""
    property real tempC: NaN
    Process {
        running: root.wantTemp && !root.tempPath
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do printf '%s %s\\n' \"$z\" \"$(cat \"$z/type\")\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const zones = text.trim().split("\n").map(l => l.split(" "))
                const pkg = zones.find(z => z[1] === "x86_pkg_temp") ?? zones[0]
                if (pkg?.[0]) root.tempPath = `${pkg[0]}/temp`
            }
        }
    }
    FileView { id: tempFile; path: root.wantTemp ? root.tempPath : ""; onLoaded: root.tempC = parseInt(text()) / 1000 }
    // Disk: df every minute.
    property real diskUsed: NaN
    property real diskSize: NaN
    Process {
        id: df
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().split("\n").pop().trim().split(/\s+/).map(Number)
                if (n.length === 2) { root.diskSize = n[0]; root.diskUsed = n[1] }
            }
        }
    }
    Timer {
        running: root.live && (root.wantTemp || root.wantDisk)
        interval: 5000; repeat: true; triggeredOnStart: true
        property int n: 0
        onTriggered: {
            if (root.wantTemp && root.tempPath) tempFile.reload()
            if (root.wantDisk && n++ % 12 === 0) df.running = true
        }
    }

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
