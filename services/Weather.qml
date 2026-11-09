pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Weather service using wttr.in API with optional GPS positioning.
 * Provides temperature, humidity, wind, UV, sunrise/sunset, and more.
 */
Singleton {
    id: root
    readonly property int fetchInterval: Config.options.bar.weather.fetchInterval * 60 * 1000
    readonly property string city: Config.options.bar.weather.city
    readonly property bool useUSCS: Config.options.bar.weather.useUSCS
    readonly property string timeFormat: Config.options.time.format
    // Where: services/Location (Settings → Services → Location) when it
    // knows, else its city (manual mode) or the city set here, else wttr.in's
    // guess from the IP address.
    readonly property bool located: Location.valid
    readonly property string place: root.located ? `${Location.latitude.toFixed(3)},${Location.longitude.toFixed(3)}`
        : root.formatCityName(Location.city || root.city)
    onPlaceChanged: root.getData()

    onUseUSCSChanged: root.getData()
    onCityChanged: root.getData()
    onTimeFormatChanged: root.getData()


    property var data: ({
        uv: 0, humidity: 0, sunrise: 0, sunset: 0,
        windDir: 0, wCode: 0, city: 0, wind: 0,
        precip: 0, visib: 0, press: 0, temp: 0,
        tempFeelsLike: 0, lastRefresh: 0,
    })

    property var days: []   // [{ date, max, min, code }]
    property string problem: ""  // why the last fetch failed ("" when it worked)
    readonly property bool fetching: fetcher.running
    property var hours: []  // today: [{ time, temp, code }]
    // A wttr.in weather code as a Material Symbol.
    function iconFor(code) {
        const c = +code
        if (c === 113) return "clear_day"
        if (c === 116) return "partly_cloudy_day"
        if (c === 119 || c === 122) return "cloud"
        if ([143, 248, 260].includes(c)) return "foggy"
        if ([200, 386, 389, 392, 395].includes(c)) return "thunderstorm"
        if ([179, 182, 185, 227, 230, 281, 284, 311, 314, 317, 320, 323, 326, 329, 332, 335, 338, 350, 362, 365, 368, 371, 374, 377].includes(c)) return "weather_snowy"
        return "rainy"
    }

    function convertTo24Hour(time12h) {
        if (!time12h || !time12h.includes(' ')) return "00:00"
        const [time, modifier] = time12h.split(' ')
        let [hours, minutes] = time.split(':')
        if (hours === '12') hours = '00'
        if (modifier.toUpperCase() === 'PM') hours = parseInt(hours, 10) + 12
        return `${String(hours).padStart(2, '0')}:${minutes}`
    }

    function convertTo12HourLowercase(time12h) {
        if (!time12h || !time12h.includes(' ')) return "00:00"
        let [time, modifier] = time12h.split(' ')
        modifier = modifier.toUpperCase() === 'PM' ? 'pm' : 'am'
        return `${time} ${modifier}`
    }

    function refineData(raw) {
        let temp = {}
        temp.uv = raw?.current?.uvIndex || 0
        temp.humidity = (raw?.current?.humidity || 0) + "%"
        temp.windDir = raw?.current?.winddir16Point || "N"
        temp.wCode = raw?.current?.weatherCode || "113"
        temp.city = raw?.location?.areaName[0]?.value || "City"
        temp.temp = ""; temp.tempFeelsLike = ""

        if (root.timeFormat === "hh:mm") {
            temp.sunrise = convertTo24Hour(raw?.astronomy?.sunrise)
            temp.sunset = convertTo24Hour(raw?.astronomy?.sunset)
        } else if (root.timeFormat === "h:mm ap") {
            temp.sunrise = convertTo12HourLowercase(raw?.astronomy?.sunrise)
            temp.sunset = convertTo12HourLowercase(raw?.astronomy?.sunset)
        } else {
            temp.sunrise = raw?.astronomy?.sunrise
            temp.sunset = raw?.astronomy?.sunset
        }

        if (root.useUSCS) {
            temp.wind = (raw?.current?.windspeedMiles || 0) + " mph"
            temp.precip = (raw?.current?.precipInches || 0) + " in"
            temp.visib = (raw?.current?.visibilityMiles || 0) + " m"
            temp.press = (raw?.current?.pressureInches || 0) + " psi"
            temp.temp = (raw?.current?.temp_F || 0) + "°F"
            temp.tempFeelsLike = (raw?.current?.FeelsLikeF || 0) + "°F"
        } else {
            temp.wind = (raw?.current?.windspeedKmph || 0) + " km/h"
            temp.precip = (raw?.current?.precipMM || 0) + " mm"
            temp.visib = (raw?.current?.visibility || 0) + " km"
            temp.press = (raw?.current?.pressure || 0) + " hPa"
            temp.temp = (raw?.current?.temp_C || 0) + "°C"
            temp.tempFeelsLike = (raw?.current?.FeelsLikeC || 0) + "°C"
        }
        temp.lastRefresh = DateTime.time + " • " + DateTime.date
        // The next days and today's 3-hourly forecast (wttr.in), for the
        // desktop weather widget.
        const unit = root.useUSCS ? "F" : "C"
        root.days = (raw?.days ?? []).map(d => ({ date: d.date, max: `${d[`maxtemp${unit}`]}°`, min: `${d[`mintemp${unit}`]}°`,
                                                  code: d.hourly?.[4]?.weatherCode ?? "113" }))
        root.hours = (raw?.days?.[0]?.hourly ?? []).map(h => ({ time: `${String(Math.floor((+h.time) / 100)).padStart(2, "0")}:00`,
                                                               temp: `${h[`temp${unit}`]}°`, code: h.weatherCode }))
        root.data = temp
        root.checkRain(raw?.days ?? [], new Date())
    }

    // ── Rain soon (bar.weather.alerts.rain): one notice when wttr.in's hourly
    // chance of rain reaches the threshold within the next hours; not again
    // until that rain's slot has passed.
    readonly property var alertCfg: Config.options?.bar?.weather?.alerts
    property real _rainQuietUntil: 0
    // The first 3-hour slot within `hours` from now with a chance ≥ threshold, or null.
    function rainSoon(days, now, threshold, hours) {
        for (const d of days) {
            for (const h of (d.hourly ?? [])) {
                const at = new Date(`${d.date}T${String(Math.floor((+h.time) / 100)).padStart(2, "0")}:00:00`)
                if (isNaN(at.getTime())) continue
                // a slot covers 3 h: the one under way counts
                if (at.getTime() + 3 * 3600000 <= now.getTime() || at.getTime() > now.getTime() + hours * 3600000) continue
                if ((+h.chanceofrain || 0) >= threshold) return { at: at, chance: +h.chanceofrain }
            }
        }
        return null
    }
    function checkRain(days, now) {
        if (!(root.alertCfg?.rain ?? false) || now.getTime() < root._rainQuietUntil) return
        const r = root.rainSoon(days, now, root.alertCfg?.rainThreshold ?? 60, root.alertCfg?.rainHours ?? 3)
        if (!r) return
        root._rainQuietUntil = r.at.getTime() + 3 * 3600000
        const when = r.at <= now ? "now" : `around ${Qt.formatTime(r.at, root.timeFormat)}`
        root.notifyQuietly("Rain soon", `${r.chance}% chance of rain ${when}`, "weather-showers")
    }
    // Quiet hours: "HH:MM"–"HH:MM", may wrap midnight (as anod's alerts.InQuiet).
    function inQuietHours(now) {
        if (!(root.alertCfg?.quiet ?? false)) return false
        const m = s => {
            const p = /^(\d{1,2}):(\d{2})$/.exec((s ?? "").trim())
            const h = p ? parseInt(p[1], 10) : 99, mm = p ? parseInt(p[2], 10) : 99
            return h < 24 && mm < 60 ? h * 60 + mm : -1
        }
        const f = m(root.alertCfg?.quietFrom), t = m(root.alertCfg?.quietTo), n = now.getHours() * 60 + now.getMinutes()
        if (f < 0 || t < 0 || f === t) return false
        return f < t ? (n >= f && n < t) : (n >= f || n < t)
    }
    // In quiet hours the notification goes to the history only (Notifications.ruleFor).
    function notifyQuietly(summary, body, icon) {
        Quickshell.execDetached(["notify-send", "-a", "Weather", "-i", icon]
            .concat(root.inQuietHours(new Date()) ? ["-h", "boolean:x-anoshell-silent:true"] : [])
            .concat(["--", summary, body]))
    }

    // ── Official warnings, from anod (anod/internal/alerts) ──
    // [{ id, source, event, headline, description, instruction, severity, area, onset, expires }]
    property var alerts: []
    readonly property bool alertsEnabled: root.alertCfg?.enable ?? true
    readonly property var shownAlerts: root.alertsEnabled ? root.alerts : []
    function alertColor(severity) {
        return severity === "extreme" || severity === "severe" ? Appearance.colors.colError
            : severity === "moderate" ? Appearance.colors.colWarning : Appearance.colors.colTertiary
    }
    // anod polls the feed for the place it was last told (kept across restarts).
    readonly property string _alertPlace: Location.valid ? `${Location.latitude.toFixed(2)},${Location.longitude.toFixed(2)}` : ""
    on_AlertPlaceChanged: root._sendPlace()
    onAlertsEnabledChanged: if (root.alertsEnabled) Anod.call("alerts.refresh", {})
    function _sendPlace() {
        if (!Anod.available) return
        if (Location.valid) Anod.call("alerts.where", { lat: Location.latitude, lon: Location.longitude })
        Anod.call("alerts.list", {}, (r, e) => { if (!e) root.alerts = r?.alerts ?? [] })
    }
    Connections {
        target: Anod
        function onEvent(name, data) { if (name === "weather_alerts") root.alerts = data?.alerts ?? [] }
        function onAvailableChanged() { if (Anod.available) root._sendPlace(); else root.alerts = [] }
    }
    Component.onCompleted: root._sendPlace()

    function getData() {
        // The place goes into the URL as one argv item: no shell.
        const where = root.place
        fetcher.command = ["curl", "-sf", "--max-time", "20", `https://wttr.in/${encodeURIComponent(where).replace(/%2B/g, "+").replace(/%2C/g, ",")}?format=j1`]
        fetcher.running = true
    }

    function formatCityName(cityName) {
        return cityName.trim().split(/\s+/).join('+')
    }

    Process {
        id: fetcher
        command: ["true"]
        onExited: code => {
            if (code !== 0) root.problem = `wttr.in: ${Format.curlReason(code)}`
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const j = JSON.parse(text)
                    root.refineData({ current: j.current_condition?.[0], location: j.nearest_area?.[0],
                                      astronomy: j.weather?.[0]?.astronomy?.[0], days: j.weather ?? [] })
                    root.problem = ""
                } catch (e) {
                    console.error(`[Weather] ${e.message}`)
                    root.problem = "wttr.in sent something that isn't a forecast"
                }
            }
        }
    }

    Timer {
        running: true
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: true
        onTriggered: root.getData()
    }
}
