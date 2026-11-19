import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The system section's Graphs style: a battery card (or uptime alone without a battery) over water-filled cards for
 * CPU, memory, temperature, disk and the GPU (when anod reads one); CPU, memory, temperature and GPU carry a sliding
 * graph of their history.
 */
ColumnLayout {
    id: root
    spacing: 8

    function hours(sec) {
        if (!(sec > 0)) return ""
        const h = Math.floor(sec / 3600), m = Math.round(sec % 3600 / 60)
        return h > 0 ? `${h} h ${m} min` : `${m} min`
    }
    readonly property color batteryTone: Battery.isCharging ? Appearance.colors.colSuccess
        : Battery.isLow ? Appearance.colors.colError : Appearance.colors.colPrimary

    // Battery
    Rectangle {
        Layout.fillWidth: true
        visible: Battery.available
        implicitHeight: 64
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2

        RowLayout {
            anchors { fill: parent; margins: 10 }
            spacing: 12
            // The outline, filled to the charge; a sheen runs across it while charging.
            Item {
                implicitWidth: 64; implicitHeight: 30
                Rectangle {
                    id: shell
                    width: parent.width - 4; height: parent.height
                    radius: 6; color: "transparent"
                    border.width: 2; border.color: Appearance.colors.colOnLayer2
                    Rectangle {
                        id: charge
                        x: 3; y: 3; height: parent.height - 6
                        width: Math.max(0, (parent.width - 6) * Battery.percentage)
                        radius: 3; color: root.batteryTone; clip: true
                        Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(700); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                        Rectangle {
                            visible: Battery.isCharging && AnimationConfig.continuous
                            width: 18; height: parent.height
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: "transparent" }
                                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.45) }
                                GradientStop { position: 1; color: "transparent" }
                            }
                            NumberAnimation on x {
                                from: -18; to: charge.width; loops: Animation.Infinite
                                duration: AnimationConfig.scaledDuration(1600)
                                running: Battery.isCharging && AnimationConfig.continuous
                            }
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: Battery.isCharging
                        text: "bolt"; iconSize: 18; fill: 1
                        color: Appearance.colors.colOnLayer2
                    }
                }
                Rectangle { x: shell.width; y: parent.height / 2 - 5; width: 4; height: 10; radius: 2; color: Appearance.colors.colOnLayer2 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: `${Math.round(Battery.percentage * 100)}% · ${Battery.isCharging ? "Charging" : Battery.isPluggedIn ? "Plugged in" : "On battery"}`
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: [
                        Battery.isCharging ? (root.hours(Battery.timeToFull) && `${root.hours(Battery.timeToFull)} to full`)
                            : (root.hours(Battery.timeToEmpty) && `${root.hours(Battery.timeToEmpty)} left`),
                        Math.abs(Battery.energyRate) > 0.05 ? `${Math.abs(Battery.energyRate).toFixed(1)} W` : "",
                        `up ${DateTime.uptime}`
                    ].filter(t => t).join(" · ")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
    StyledText {
        visible: !Battery.available
        text: `Up ${DateTime.uptime}`
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2; rowSpacing: 8; columnSpacing: 8
        WaterCard {
            Layout.fillWidth: true; Layout.preferredWidth: 1
            icon: "memory"; label: "CPU"
            level: ResourceUsage.cpuUsage
            valueText: `${Math.round(ResourceUsage.cpuUsage * 100)}%`
            detail: ResourceUsage.maxAvailableCpuString
            history: ResourceUsage.cpuUsageHistory
        }
        WaterCard {
            Layout.fillWidth: true; Layout.preferredWidth: 1
            icon: "memory_alt"; label: "Memory"
            tone: Appearance.colors.colTertiary
            level: ResourceUsage.memoryUsedPercentage
            valueText: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`
            detail: `${ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)} of ${ResourceUsage.maxAvailableMemoryString}`
            history: ResourceUsage.memoryUsageHistory
        }
        WaterCard {
            Layout.fillWidth: true; Layout.preferredWidth: 1
            icon: "device_thermostat"; label: "Temperature"
            tone: ResourceUsage.temperature >= 85 ? Appearance.colors.colError : Appearance.colors.colWarning
            level: isNaN(ResourceUsage.temperature) ? 0 : ResourceUsage.temperature / 100
            valueText: isNaN(ResourceUsage.temperature) ? "--" : `${Math.round(ResourceUsage.temperature)}°C`
            history: ResourceUsage.temperatureHistory.map(t => Math.min(1, t / 100))
        }
        WaterCard {
            Layout.fillWidth: true; Layout.preferredWidth: 1
            icon: "hard_drive"; label: "Disk"
            tone: Appearance.colors.colInfo
            level: ResourceUsage.diskUsedPercentage
            valueText: isNaN(ResourceUsage.diskSize) ? "--" : `${Math.round(ResourceUsage.diskUsedPercentage * 100)}%`
            detail: isNaN(ResourceUsage.diskSize) ? "" : `${(ResourceUsage.diskUsed / 1e9).toFixed(0)} of ${(ResourceUsage.diskSize / 1e9).toFixed(0)} GB`
        }
        WaterCard {
            visible: ResourceUsage.gpuPresent && !ResourceUsage.gpuNote
            Layout.fillWidth: true; Layout.columnSpan: 2
            icon: "developer_board"; label: "GPU"
            tone: Appearance.colors.colSecondary
            level: isNaN(ResourceUsage.gpuUsage) ? 0 : ResourceUsage.gpuUsage
            valueText: isNaN(ResourceUsage.gpuUsage) ? "--" : `${Math.round(ResourceUsage.gpuUsage * 100)}%`
            detail: [ResourceUsage.gpuName,
                     !(ResourceUsage.gpuMHz > 0) ? "" : `${Math.round(ResourceUsage.gpuMHz)} MHz`,
                     isNaN(ResourceUsage.gpuMemTotal) ? "" : `${(ResourceUsage.gpuMemUsed / 1073741824).toFixed(1)} of ${(ResourceUsage.gpuMemTotal / 1073741824).toFixed(0)} GB`,
                     isNaN(ResourceUsage.gpuTemperature) ? "" : `${Math.round(ResourceUsage.gpuTemperature)}°C`].filter(t => t).join(" · ")
            history: ResourceUsage.gpuUsageHistory
        }
    }
}
