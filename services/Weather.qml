pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import QtPositioning
import qs.modules.common
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
    property bool gpsActive: Config.options.bar.weather.enableGPS

    onUseUSCSChanged: root.getData()
    onCityChanged: root.getData()
    onTimeFormatChanged: root.getData()

    property var location: ({ valid: false, lat: 0, lon: 0 })

    property var data: ({
        uv: 0, humidity: 0, sunrise: 0, sunset: 0,
        windDir: 0, wCode: 0, city: 0, wind: 0,
        precip: 0, visib: 0, press: 0, temp: 0,
        tempFeelsLike: 0, lastRefresh: 0,
    })

    property var days: []   // [{ date, max, min, code }]
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
    }

    function getData() {
        // The place goes into the URL as one argv item: no shell.
        const where = (root.gpsActive && root.location.valid) ? `${root.location.lat},${root.location.lon}`
            : root.formatCityName(root.city)
        fetcher.command = ["curl", "-sf", "--max-time", "20", `https://wttr.in/${encodeURIComponent(where).replace(/%2B/g, "+").replace(/%2C/g, ",")}?format=j1`]
        fetcher.running = true
    }

    function formatCityName(cityName) {
        return cityName.trim().split(/\s+/).join('+')
    }

    Component.onCompleted: {
        if (!root.gpsActive) return
        positionSource.start()
    }

    Process {
        id: fetcher
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return
                try {
                    const j = JSON.parse(text)
                    root.refineData({ current: j.current_condition?.[0], location: j.nearest_area?.[0],
                                      astronomy: j.weather?.[0]?.astronomy?.[0], days: j.weather ?? [] })
                } catch (e) {
                    console.error(`[Weather] ${e.message}`)
                }
            }
        }
    }

    PositionSource {
        id: positionSource
        updateInterval: root.fetchInterval
        onPositionChanged: {
            if (position.latitudeValid && position.longitudeValid) {
                root.location.lat = position.coordinate.latitude
                root.location.lon = position.coordinate.longitude
                root.location.valid = true
                root.getData()
            } else {
                root.gpsActive = root.location.valid
                console.error("[Weather] Failed to get GPS location.")
            }
        }
        onValidityChanged: {
            if (!positionSource.valid) {
                positionSource.stop()
                root.location.valid = false
                root.gpsActive = false
                Quickshell.execDetached(["notify-send", "Weather Service",
                    "Cannot find a GPS service. Using fallback method.", "-a", "Ano Shell"])
            }
        }
    }

    Timer {
        running: !root.gpsActive
        repeat: true
        interval: root.fetchInterval
        triggeredOnStart: !root.gpsActive
        onTriggered: root.getData()
    }
}
