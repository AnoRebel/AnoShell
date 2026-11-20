import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * System resources bar module with rich hover popup showing
 * CPU/RAM/Swap gauges, CPU history graph, and system details.
 */
Item {
    id: root
    // ResourceUsage polls only while a visible consumer holds a lease.
    ServiceLease { service: ResourceUsage; name: "barResources"; active: true }

    implicitWidth: row.implicitWidth + 12
    implicitHeight: Appearance.sizes.barHeight
    property bool hovered: resMA.containsMouse

    RowLayout {
        id: row; anchors.centerIn: parent; spacing: 4
        CombinedCircularProgress { implicitSize: 22; outerLineWidth: 2; innerLineWidth: 2; outerValue: ResourceUsage.cpuUsage; innerValue: ResourceUsage.memoryUsedPercentage; Layout.alignment: Qt.AlignVCenter }
        StyledText { text: `${Math.round(ResourceUsage.cpuUsage * 100)}%`; font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5" }
    }

    MouseArea { id: resMA; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton; onClicked: GlobalStates.hudVisible = !GlobalStates.hudVisible }

    BarModulePopout {
        shown: root.hovered
        popupWidth: 280; popupHeight: resPopupCol.implicitHeight + 24

        ColumnLayout {
            id: resPopupCol; anchors.fill: parent; spacing: 10

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                // Fixed keys, values bound in the delegate: a model built from the values was a
                // new array each sample, and the Repeater rebuilt its delegates (hidden or not).
                Repeater {
                    model: ["CPU", "RAM"]
                    ColumnLayout {
                        id: gauge
                        required property string modelData
                        readonly property bool cpu: modelData === "CPU"
                        // Equal columns (fillWidth alone shares by content width: uneven rings).
                        Layout.fillWidth: true; Layout.preferredWidth: 1; spacing: 4
                        CircularProgress { implicitSize: 48; lineWidth: 3; value: gauge.cpu ? ResourceUsage.cpuUsage : ResourceUsage.memoryUsedPercentage; colPrimary: gauge.cpu ? (Appearance?.colors.colPrimary ?? "#65558F") : Appearance.colors.colInfo; Layout.alignment: Qt.AlignHCenter }
                        StyledText { text: gauge.cpu ? `${Math.round(ResourceUsage.cpuUsage * 100)}%` : ResourceUsage.kbToGbString(ResourceUsage.memoryUsed); font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Bold; font.family: Appearance?.font.family.numbers ?? "monospace"; Layout.alignment: Qt.AlignHCenter }
                        StyledText { text: gauge.modelData; font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
                    }
                }
                Loader {
                    Layout.fillWidth: true; Layout.preferredWidth: 1; active: ResourceUsage.swapTotal > 1024; visible: active
                    sourceComponent: ColumnLayout {
                        spacing: 4
                        CircularProgress { implicitSize: 48; lineWidth: 3; value: ResourceUsage.swapUsedPercentage; colPrimary: Appearance.colors.colTertiary; Layout.alignment: Qt.AlignHCenter }
                        StyledText { text: ResourceUsage.kbToGbString(ResourceUsage.swapUsed); font.pixelSize: Appearance.font.pixelSize.small; font.weight: Font.Bold; font.family: Appearance?.font.family.numbers ?? "monospace"; Layout.alignment: Qt.AlignHCenter }
                        StyledText { text: "Swap"; font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; implicitHeight: 32; radius: 6
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                Graph {
                    anchors { fill: parent; margins: 2 }
                    values: ResourceUsage.cpuUsageHistory
                    color: Appearance?.colors.colPrimary ?? "#65558F"
                    fillOpacity: 0.3
                    alignment: Graph.Alignment.Right
                }
            }

            Repeater {
                model: ["CPU max", "RAM total", "Uptime"]
                RowLayout {
                    id: detail
                    required property string modelData
                    Layout.fillWidth: true; spacing: 8
                    StyledText { text: detail.modelData; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4; Layout.fillWidth: true }
                    StyledText { text: detail.modelData === "CPU max" ? ResourceUsage.maxAvailableCpuString : detail.modelData === "RAM total" ? ResourceUsage.maxAvailableMemoryString : DateTime.uptime; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" }
                }
            }

            StyledText { text: "Click to open HUD"; font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.3; Layout.alignment: Qt.AlignHCenter }
        }
    }
}
