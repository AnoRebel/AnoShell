pragma Singleton

import QtQuick
import QtPositioning
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Location: where you are, for the weather, night light's sunset-to-sunrise
 * schedule and the sun-and-moon widgets (Settings → Services → Location).
 *
 *   location.enable  off: nothing is looked up; weather falls back to its
 *                    city setting (or wttr.in's own guess), sun schedules wait.
 *   location.mode    "auto": GeoClue (Qt Positioning's geoclue2 plugin; Wi-Fi
 *                    or GPS, as GeoClue is set up), and if it gives nothing
 *                    within 20 s or is refused, the IP address (ip-api.com,
 *                    city level). "manual": location.latitude/longitude and
 *                    location.city as you set them.
 *
 * Exposes valid, latitude, longitude, city, source ("geoclue" | "ip" |
 * "manual") and problem.
 */
Singleton {
    id: root

    readonly property var cfg: Config.options?.location
    readonly property bool enabled: root.cfg?.enable ?? true
    readonly property string mode: root.cfg?.mode ?? "auto"
    readonly property bool manual: root.mode === "manual"

    // Manual: what you typed (0,0 counts as unset).
    readonly property real manualLat: root.cfg?.latitude ?? 0
    readonly property real manualLon: root.cfg?.longitude ?? 0
    readonly property bool manualValid: root.manualLat !== 0 || root.manualLon !== 0

    // Auto: the last fix.
    property real autoLat: 0
    property real autoLon: 0
    property string autoCity: ""
    property string autoSource: ""
    property bool autoValid: false

    readonly property bool valid: root.enabled && (root.manual ? root.manualValid : root.autoValid)
    readonly property real latitude: !root.valid ? 0 : root.manual ? root.manualLat : root.autoLat
    readonly property real longitude: !root.valid ? 0 : root.manual ? root.manualLon : root.autoLon
    readonly property string city: !root.enabled ? "" : root.manual ? (root.cfg?.city ?? "").trim() : root.autoCity
    readonly property string source: !root.valid ? "" : root.manual ? "manual" : root.autoSource
    readonly property string problem: !root.enabled ? "Location is off"
        : root.manual ? (root.manualValid ? "" : "Set a latitude and longitude")
        : root.autoValid ? "" : root.looking ? "Looking…" : "Couldn't find where you are"
    property bool looking: false

    function refresh(): void {
        if (!root.enabled || root.manual) return
        root.looking = true
        geo.update()
        geoTimeout.restart()
    }
    onEnabledChanged: root.refresh()
    onManualChanged: root.refresh()
    Component.onCompleted: root.refresh()

    // ── GeoClue ──
    PositionSource {
        id: geo
        name: "geoclue2"
        active: false
        updateInterval: 30 * 60 * 1000
        preferredPositioningMethods: PositionSource.AllPositioningMethods
        onPositionChanged: {
            const c = geo.position.coordinate
            if (!geo.position.latitudeValid || !geo.position.longitudeValid) return
            geoTimeout.stop()
            root.autoLat = c.latitude
            root.autoLon = c.longitude
            root.autoSource = "geoclue"
            root.autoValid = true
            root.looking = false
            if (!root.autoCity) ipLookup.running = true // a city name for display
        }
        onSourceErrorChanged: if (geo.sourceError !== PositionSource.NoError && root.looking) root._fallBack()
    }
    Timer { id: geoTimeout; interval: 20000; onTriggered: if (root.looking) root._fallBack() }
    function _fallBack(): void {
        geoTimeout.stop()
        if (!ipLookup.running) ipLookup.running = true
    }

    // ── IP address (fallback, and the city name) ──
    Process {
        id: ipLookup
        command: ["curl", "-sf", "--max-time", "10", "http://ip-api.com/json/?fields=status,lat,lon,city"]
        stdout: StdioCollector {
            onStreamFinished: {
                let j = null
                try { j = JSON.parse(text) } catch (e) {}
                if (j?.status !== "success") return
                if (j.city) root.autoCity = j.city
                if (root.autoSource !== "geoclue") {
                    root.autoLat = j.lat
                    root.autoLon = j.lon
                    root.autoSource = "ip"
                    root.autoValid = true
                }
            }
        }
        onExited: root.looking = false
    }
    // An IP fix is coarse and can change (VPN, travel): look again every 2 h.
    Timer {
        running: root.enabled && !root.manual && root.autoSource === "ip"
        interval: 2 * 60 * 60 * 1000
        repeat: true
        onTriggered: root.refresh()
    }

    IpcHandler {
        target: "location"
        function get(): string {
            return JSON.stringify({ valid: root.valid, latitude: root.latitude, longitude: root.longitude, city: root.city, source: root.source, problem: root.problem })
        }
        function refresh(): void { root.refresh() }
    }
}
