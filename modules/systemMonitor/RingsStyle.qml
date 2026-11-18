import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The system section's Rings style: nested rings for battery (outermost, left out without one), CPU and memory, a
 * legend beside them, a light running round the battery ring while charging, and pills for temperature, disk, uptime
 * and power draw.
 */
ColumnLayout {
    id: root
    spacing: 10

    // Keyed by name so a new sample updates the rings in place (their arcs glide) instead of rebuilding them.
    readonly property var keys: Battery.available ? ["battery", "cpu", "mem"] : ["cpu", "mem"]
    function ring(key) {
        switch (key) {
        case "battery":
            return { name: Battery.isCharging ? "Charging" : "Battery", value: Battery.percentage,
                text: `${Math.round(Battery.percentage * 100)}%`, detail: Battery.isPluggedIn ? "plugged in" : "on battery",
                tone: Battery.isCharging ? Appearance.colors.colSuccess : Battery.isLow ? Appearance.colors.colError : Appearance.colors.colSecondary }
        case "cpu":
            return { name: "CPU", value: ResourceUsage.cpuUsage, text: `${Math.round(ResourceUsage.cpuUsage * 100)}%`,
                detail: ResourceUsage.maxAvailableCpuString, tone: Appearance.colors.colPrimary }
        default:
            return { name: "Memory", value: ResourceUsage.memoryUsedPercentage, text: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`,
                detail: `${ResourceUsage.kbToGbString(ResourceUsage.memoryUsed)} of ${ResourceUsage.maxAvailableMemoryString}`, tone: Appearance.colors.colTertiary }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 14

        Item {
            id: dial
            implicitWidth: 112; implicitHeight: 112
            readonly property real stroke: 9
            readonly property real gap: 4
            Repeater {
                model: root.keys
                Item {
                    id: ring
                    required property string modelData
                    required property int index
                    readonly property var d: root.ring(ring.modelData)
                    anchors.fill: parent
                    readonly property real radius: dial.width / 2 - dial.stroke / 2 - ring.index * (dial.stroke + dial.gap)
                    property real shown: ring.d.value
                    Behavior on shown { NumberAnimation { duration: AnimationConfig.scaledDuration(800); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Appearance.colors.colLayer2; strokeWidth: dial.stroke
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: dial.width / 2; centerY: dial.height / 2; radiusX: ring.radius; radiusY: ring.radius; startAngle: 0; sweepAngle: 360 }
                        }
                        ShapePath {
                            strokeColor: ring.d.tone; strokeWidth: dial.stroke
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: dial.width / 2; centerY: dial.height / 2; radiusX: ring.radius; radiusY: ring.radius; startAngle: -90; sweepAngle: Math.max(0.5, 360 * Math.min(1, ring.shown)) }
                        }
                    }
                    // The light running round the battery ring while charging.
                    Shape {
                        anchors.fill: parent
                        visible: ring.modelData === "battery" && Battery.isCharging && AnimationConfig.continuous
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeColor: Qt.rgba(1, 1, 1, 0.7); strokeWidth: dial.stroke - 3
                            fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            PathAngleArc { centerX: dial.width / 2; centerY: dial.height / 2; radiusX: ring.radius; radiusY: ring.radius; startAngle: -90; sweepAngle: 18 }
                        }
                        RotationAnimation on rotation {
                            from: 0; to: 360; loops: Animation.Infinite
                            duration: AnimationConfig.scaledDuration(2400)
                            running: parent.visible
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: root.keys
                RowLayout {
                    id: legend
                    required property string modelData
                    readonly property var d: root.ring(legend.modelData)
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle { implicitWidth: 10; implicitHeight: 10; radius: 5; color: legend.d.tone }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            StyledText { text: legend.d.name; font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colOnLayer1; Layout.fillWidth: true }
                            StyledText { text: legend.d.text; font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold; font.family: Appearance.font.family.mono }
                        }
                        StyledText { text: legend.d.detail; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext; elide: Text.ElideRight; Layout.fillWidth: true }
                    }
                }
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: [
                { icon: "device_thermostat", text: isNaN(ResourceUsage.temperature) ? "" : `${Math.round(ResourceUsage.temperature)}°C` },
                { icon: "hard_drive", text: isNaN(ResourceUsage.diskSize) ? "" : `${Math.round(ResourceUsage.diskUsedPercentage * 100)}% disk` },
                { icon: "schedule", text: `up ${DateTime.uptime}` },
                { icon: "bolt", text: Battery.available && Math.abs(Battery.energyRate) > 0.05 ? `${Math.abs(Battery.energyRate).toFixed(1)} W` : "" }
            ].filter(p => p.text)
            Rectangle {
                required property var modelData
                implicitHeight: 26
                implicitWidth: pillRow.implicitWidth + 16
                radius: 13
                color: Appearance.colors.colLayer2
                RowLayout {
                    id: pillRow
                    anchors.centerIn: parent
                    spacing: 4
                    MaterialSymbol { text: modelData.icon; iconSize: 14; color: Appearance.colors.colSubtext }
                    StyledText { text: modelData.text; font.pixelSize: Appearance.font.pixelSize.smaller }
                }
            }
        }
    }
}
