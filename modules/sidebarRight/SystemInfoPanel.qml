import QtQuick
import qs
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * System info panel — CPU, RAM, swap usage with circular indicators and graphs.
 * Inspired by ilyamiro's battery popup stats and inir's sysmon widget.
 */
Rectangle {
    id: root
    // ResourceUsage polls only while a visible consumer holds a lease.
    ServiceLease { service: ResourceUsage; name: "sidebarSystemInfo"; active: GlobalStates.sidebarRightOpen }

    implicitHeight: infoCol.implicitHeight + 20
    radius: Appearance?.rounding.normal ?? 12
    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
    border.width: 1
    border.color: Appearance?.colors.colLayer0Border ?? "#44444488"

    ColumnLayout {
        id: infoCol
        anchors { fill: parent; margins: 10 }
        spacing: 10

        StyledText {
            text: "System"
            font.pixelSize: Appearance?.font.pixelSize.small ?? 14
            font.weight: Font.DemiBold
        }

        // CPU + RAM + Swap + Battery gauges — each claims an equal share of the
        // row (fillWidth + equal preferredWidth) and centres its content.
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // CPU
            GaugeItem {
                label: "CPU"
                value: ResourceUsage.cpuUsage
                valueText: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }

            // RAM
            GaugeItem {
                label: "RAM"
                value: ResourceUsage.memoryUsedPercentage
                valueText: ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)
                Layout.fillWidth: true
                Layout.preferredWidth: 1
            }

            // Swap (only when present)
            GaugeItem {
                label: "Swap"
                value: ResourceUsage.swapUsedPercentage
                valueText: ResourceUsage.kbToGbString(ResourceUsage.swapUsed)
                visible: ResourceUsage.swapTotal > 0
                Layout.fillWidth: visible
                Layout.preferredWidth: visible ? 1 : 0
            }

            // Battery (if laptop)
            Loader {
                id: batteryLoader
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                active: Battery.available
                visible: active
                sourceComponent: GaugeItem {
                    anchors.fill: parent ? parent : undefined
                    label: Battery.isCharging ? "Charging" : "Battery"
                    value: Battery.percentage
                    valueText: `${Math.round(Battery.percentage * 100)}%`
                    gaugeColor: Battery.isLow && !Battery.isCharging
                        ? Appearance?.m3colors.m3error ?? "#BA1A1A"
                        : Battery.isCharging
                            ? "#81C784"
                            : Appearance?.colors.colPrimary ?? "#65558F"
                }
            }
        }

        // Network speed
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            MaterialSymbol { text: "arrow_downward"; iconSize: 16; color: "#81C784" }
            StyledText {
                text: formatSpeed(ResourceUsage.networkDownloadSpeed)
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
            MaterialSymbol { text: "arrow_upward"; iconSize: 16; color: "#E57373" }
            StyledText {
                text: formatSpeed(ResourceUsage.networkUploadSpeed)
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: `Up ${DateTime.uptime}`
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                opacity: 0.5
            }
        }
    }

    function formatSpeed(bytesPerSec) {
        if (bytesPerSec < 1024) return `${Math.round(bytesPerSec)} B/s`
        if (bytesPerSec < 1024 * 1024) return `${(bytesPerSec / 1024).toFixed(1)} KB/s`
        return `${(bytesPerSec / 1024 / 1024).toFixed(1)} MB/s`
    }

    // Circular gauge component. References are qualified via `gauge` (the
    // component root) — bare `parent.value`/`gaugeColor` from nested children
    // don't reliably resolve to the component instance and left the rings
    // unfilled / default-coloured.
    //
    // Do NOT put Layout.* on this component definition — Layout attached props
    // belong on the INSTANCE in its parent layout. Putting fillWidth +
    // preferredWidth:0 here collapsed every gauge to 0 width so the rings piled
    // up on top of each other. Equal spacing is achieved on the instances below.
    // A gauge is an Item that fills its row slot and CENTRES a column of
    // ring+value+label inside it. Being a plain Item (not a ColumnLayout) it
    // centres identically whether it's a direct RowLayout child or nested in a
    // Loader (the Battery case) — fixing the "3 bunched left, battery far right"
    // clustering. Its implicit size comes from the inner column so the row can
    // still size itself when not given extra width.
    component GaugeItem: Item {
        id: gauge
        property string label: ""
        property real value: 0
        property string valueText: ""
        property color gaugeColor: Appearance?.colors.colPrimary ?? "#65558F"
        implicitWidth: gaugeCol.implicitWidth
        implicitHeight: gaugeCol.implicitHeight

        ColumnLayout {
            id: gaugeCol
            anchors.centerIn: parent
            spacing: 4

            CircularProgress {
                Layout.alignment: Qt.AlignHCenter
                implicitSize: 48; lineWidth: 4
                value: gauge.value
                colPrimary: gauge.gaugeColor
                colSecondary: Appearance?.colors.colLayer2 ?? "#2B2930"
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: gauge.valueText
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                font.weight: Font.DemiBold
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: gauge.label
                font.pixelSize: Appearance?.font.pixelSize.smallest ?? 10
                opacity: 0.5
            }
        }
    }
}
