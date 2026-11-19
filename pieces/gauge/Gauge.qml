import QtQuick
import QtQuick.Shapes
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "gauge.js" as G

// Bundled piece: one reading as a ring whose edge is a sine wave (or plain), the value, a label and an icon inside
// as far as they fit. Battery: green while charging, red at 20% or less unplugged. Samples only while ctx.live.
Item {
    id: root
    property var ctx
    property var settings: ({})
    readonly property bool live: root.ctx?.live ?? false
    readonly property string metric: ["CPU", "GPU", "Memory", "Temperature", "Disk", "Battery"].includes(root.settings?.metric) ? root.settings.metric : "CPU"
    readonly property bool wave: root.settings?.style !== "Plain"
    readonly property real thickness: Math.max(2, Math.min(24, Number(root.settings?.thickness ?? 8)))

    // ResourceUsage polls only while leased; the battery needs no lease.
    property bool _leased: false
    property string _leaseName: ""
    readonly property string _wantName: root.metric === "GPU" ? "gaugePieceGpu" : "gaugePiece"
    on_WantNameChanged: if (root._leased) { root._lease(false); root._lease(root._want) }
    readonly property bool _want: root.live && root.metric !== "Battery"
    on_WantChanged: root._lease(root._want)
    Component.onCompleted: root._lease(root._want)
    Component.onDestruction: root._lease(false)
    function _lease(on) {
        if (on === root._leased) return
        root._leased = on
        if (on) root._leaseName = root._wantName
        if (on) ResourceUsage.acquire(root._leaseName); else ResourceUsage.release(root._leaseName)
    }

    readonly property var reading: {
        switch (root.metric) {
        case "GPU": {
            const g = ResourceUsage.gpuUsage
            return { icon: "developer_board", label: "GPU", value: isNaN(g) ? 0 : g, text: isNaN(g) ? "--" : `${Math.round(g * 100)}%` }
        }
        case "Memory": return { icon: "memory_alt", label: "Memory", value: ResourceUsage.memoryUsedPercentage, text: `${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%` }
        case "Temperature": {
            const t = ResourceUsage.temperature
            return { icon: "device_thermostat", label: "CPU temp", value: isNaN(t) ? 0 : Math.min(1, t / 100), text: isNaN(t) ? "--" : `${Math.round(t)}°` }
        }
        case "Disk": return { icon: "hard_drive", label: "Disk", value: ResourceUsage.diskUsedPercentage, text: isNaN(ResourceUsage.diskSize) ? "--" : `${Math.round(ResourceUsage.diskUsedPercentage * 100)}%` }
        case "Battery": return { icon: Battery.isCharging ? "battery_charging_full" : "battery_full", label: Battery.isCharging ? "Charging" : "Battery",
            value: Battery.available ? Battery.percentage : 0, text: Battery.available ? `${Math.round(Battery.percentage * 100)}%` : "--" }
        default: return { icon: "memory", label: "CPU", value: ResourceUsage.cpuUsage, text: `${Math.round(ResourceUsage.cpuUsage * 100)}%` }
        }
    }
    readonly property string batteryState: root.metric === "Battery" ? G.batteryState(Battery.percentage, Battery.isCharging, Battery.isPluggedIn) : ""
    readonly property color tone: root.batteryState === "charging" ? Appearance.colors.colSuccess
        : root.batteryState === "low" ? Appearance.colors.colError : Appearance.colors.colPrimary

    property real shown: root.reading.value
    Behavior on shown { NumberAnimation { duration: AnimationConfig.scaledDuration(900); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

    readonly property var fit: G.parts(root.width, root.height)
    readonly property real size: Math.min(root.width, root.height) - 8
    readonly property real amp: root.wave ? Math.max(1.5, root.thickness * 0.35) : 0
    readonly property real radius: root.size / 2 - root.thickness / 2 - root.amp
    readonly property int waves: Math.max(6, Math.round(root.radius / 6))

    // Wave
    Shape {
        anchors.fill: parent
        visible: root.wave
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.alpha(root.tone, 0.18); strokeWidth: root.thickness
            fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.wave ? G.wavePoints(root.width / 2, root.height / 2, root.radius, root.amp, root.waves, 1, 240) : [] }
        }
        ShapePath {
            strokeColor: root.tone; strokeWidth: root.thickness
            fillColor: "transparent"; capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root.wave ? G.wavePoints(root.width / 2, root.height / 2, root.radius, root.amp, root.waves, root.shown, 240) : [] }
        }
    }
    // Plain
    Shape {
        anchors.fill: parent
        visible: !root.wave
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Qt.alpha(root.tone, 0.18); strokeWidth: root.thickness
            fillColor: "transparent"
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.radius; radiusY: root.radius; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: root.tone; strokeWidth: root.thickness
            fillColor: "transparent"; capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.radius; radiusY: root.radius; startAngle: -90; sweepAngle: 360 * Math.max(0.001, Math.min(1, root.shown)) }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 0
        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.fit.icon
            text: root.reading.icon
            iconSize: Math.round(root.size * 0.14)
            color: root.tone
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.fit.value
            text: root.reading.text
            font.pixelSize: Math.max(11, Math.round(root.radius * 0.42))
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.fit.label
            text: root.reading.label
            font.pixelSize: Math.max(10, Math.round(root.radius * 0.17))
            color: Appearance.colors.colSubtext
        }
    }
}
