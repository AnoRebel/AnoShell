// Ported from Bioma (GPL-3.0), services/Weather.qml.
pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services as AnoServices

// The weather where the user is.
//
// From Open-Meteo: no key, metric units. The place is a city typed in the
// settings (`weather.city`), geocoded once by Open-Meteo's own geocoder; the
// answer — the place's name as the geocoder spells it, and its coordinates —
// is kept for the session (AnoShell: the city is bar.weather.city, shared
// with the bar's own weather; Akusen's choice, 2026-10-04: the city in Settings, not a
// position guessed from the address, which the company proxy would put
// somewhere else).
//
// It asks only while something holds it — a weather organism on screen — and
// then every thirty minutes, through the proxy when one is on. A reading is
// trusted for two hours; past that, with the network gone, it is not shown
// rather than shown wrong.
Singleton {
    id: root

    // ---- Who wants it -------------------------------------------------------------

    property var holders: []
    readonly property bool active: root.holders.length > 0

    function hold(owner, wanted) {
        const held = root.holders.indexOf(owner) >= 0;
        if (wanted && !held)
            root.holders = root.holders.concat([owner]);
        else if (!wanted && held)
            root.holders = root.holders.filter(h => h !== owner);
    }

    // ---- Where ------------------------------------------------------------------------

    readonly property string city: (Config.get("weather.city", "") || "").trim()
    // AnoShell adaptation: the geocoder's answer is kept in memory (Bioma
    // wrote it back to its config), so each shell start geocodes once.
    property var latitude: null
    property var longitude: null
    property string foundName: ""
    readonly property string place: root.foundName || root.city
    property string locatedFor: ""
    readonly property bool located: root.latitude !== null && root.longitude !== null
                                    && root.locatedFor === root.city

    // Why there is nothing to show, in a sentence, for the settings to say
    // under the field. Empty while all is well.
    property string problem: ""

    // ---- What -------------------------------------------------------------------------

    // { "temperature", "code", "day", "high", "low", "time" } — `time` is when
    // it was read, in milliseconds.
    property var current: null

    // The next hours: [{ "hour", "temperature", "code", "day" }].
    property var hours: []

    readonly property int freshFor: 2 * 3600 * 1000
    property double now: Date.now()

    readonly property bool fresh: root.current !== null && root.now - root.current.time < root.freshFor

    // ---- Asking -----------------------------------------------------------------------

    readonly property int every: Math.max(5, Config.get("weather.minutes", 30)) * 60 * 1000

    Timer {
        interval: root.every
        repeat: true
        running: root.active && root.city.length > 0
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // The clock the freshness is judged by: once a minute is enough to say a
    // two-hour-old reading is two hours old.
    Timer {
        interval: 60 * 1000
        repeat: true
        running: root.active
        onTriggered: root.now = Date.now()
    }

    onCityChanged: {
        root.current = null;
        root.hours = [];
        root.problem = "";
        root.foundName = "";
        if (root.active)
            root.refresh();
    }

    Connections {
        target: AnoServices.Location
        function onValidChanged() { if (root.active) root.refresh(); }
        function onLatitudeChanged() { if (root.active && AnoServices.Location.valid) root.refresh(); }
    }

    function refresh() {
        root.now = Date.now();
        // AnoShell: where you are, when Settings → Services → Location knows.
        if (AnoServices.Location.valid) {
            root.latitude = AnoServices.Location.latitude;
            root.longitude = AnoServices.Location.longitude;
            root.locatedFor = root.city;
            root.foundName = AnoServices.Location.city || root.city;
            root.forecast(root.latitude, root.longitude);
            return;
        }
        if (root.city.length === 0) {
            root.problem = "No city is set.";
            return;
        }
        if (!root.located)
            root.locate();
        else
            root.forecast(root.latitude, root.longitude);
    }

    function locate() {
        if (geocoder.running)
            return;
        geocoder.asked = root.city;
        geocoder.command = root.fetch("https://geocoding-api.open-meteo.com/v1/search?count=1&language=en&format=json&name="
                                      + encodeURIComponent(root.city));
        geocoder.running = true;
    }

    function forecast(latitude, longitude) {
        if (reader.running)
            return;
        reader.command = root.fetch("https://api.open-meteo.com/v1/forecast"
            + `?latitude=${latitude}&longitude=${longitude}`
            + (Config.get("weather.fahrenheit", false) ? "&temperature_unit=fahrenheit" : "")
            + "&current=temperature_2m,weather_code,is_day"
            + "&hourly=temperature_2m,weather_code,is_day"
            + "&daily=temperature_2m_max,temperature_2m_min"
            + "&forecast_days=2&timezone=auto");
        reader.running = true;
    }

    // curl rather than anything of Qt's own: it honours the proxy variables
    // the shell was started with. The URL is one argv entry, never a shell
    // string; the city goes in through encodeURIComponent.
    function fetch(url) {
        return ["curl", "--silent", "--show-error", "--fail", "--max-time", "20", url];
    }

    Process {
        id: geocoder

        property string asked: ""

        stdout: StdioCollector {
            onStreamFinished: root.located_(geocoder.asked, text)
        }

        onExited: code => {
            if (code !== 0)
                root.problem = "The weather service could not be reached.";
        }
    }

    function located_(asked, text) {
        if (asked !== root.city || text.length === 0)
            return;
        let answer = null;
        try {
            answer = JSON.parse(text);
        } catch (e) {
            root.problem = "The weather service answered with something unreadable.";
            return;
        }
        const found = answer.results && answer.results.length > 0 ? answer.results[0] : null;
        if (!found) {
            root.problem = `No place called “${asked}” was found.`;
            return;
        }
        root.problem = "";
        root.latitude = found.latitude;
        root.longitude = found.longitude;
        root.foundName = found.name;
        root.locatedFor = asked;
        root.forecast(found.latitude, found.longitude);
    }

    Process {
        id: reader

        stdout: StdioCollector {
            onStreamFinished: root.read(text)
        }

        onExited: code => {
            if (code !== 0)
                root.problem = "The weather service could not be reached.";
        }
    }

    function read(text) {
        if (text.length === 0)
            return;
        let answer = null;
        try {
            answer = JSON.parse(text);
        } catch (e) {
            root.problem = "The weather service answered with something unreadable.";
            return;
        }
        const current = answer.current;
        const hourly = answer.hourly;
        const daily = answer.daily;
        if (!current || !hourly || !daily) {
            root.problem = "The weather service answered without a forecast.";
            return;
        }

        // The hours from the next whole one, in the place's own time — the
        // service was asked for `timezone=auto`, so its times are local.
        const next = [];
        const start = hourly.time.findIndex(t => t > current.time);
        for (let i = Math.max(0, start); i < hourly.time.length && next.length < 5; i++)
            next.push({
                "hour": parseInt(hourly.time[i].slice(11, 13), 10),
                "temperature": hourly.temperature_2m[i],
                "code": hourly.weather_code[i],
                "day": hourly.is_day[i] === 1
            });

        root.problem = "";
        root.hours = next;
        root.current = {
            "temperature": current.temperature_2m,
            "code": current.weather_code,
            "day": current.is_day === 1,
            "high": daily.temperature_2m_max[0],
            "low": daily.temperature_2m_min[0],
            "time": Date.now()
        };
        root.now = Date.now();
    }

    // ---- Words and glyphs -----------------------------------------------------------

    // WMO weather codes, as Open-Meteo reports them, onto the eight glyphs and
    // a sentence each.
    function glyphFor(code, day) {
        if (code === 0 || code === 1)
            return day ? "weather-clear" : "weather-clear-night";
        if (code === 2)
            return "weather-partly";
        if (code === 3)
            return "weather-cloudy";
        if (code === 45 || code === 48)
            return "weather-fog";
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82))
            return "weather-rain";
        if ((code >= 71 && code <= 77) || code === 85 || code === 86)
            return "weather-snow";
        if (code >= 95)
            return "weather-storm";
        return "weather-cloudy";
    }

    function wordsFor(code) {
        const words = {
            0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
            45: "Fog", 48: "Rime fog",
            51: "Light drizzle", 53: "Drizzle", 55: "Heavy drizzle",
            56: "Freezing drizzle", 57: "Freezing drizzle",
            61: "Light rain", 63: "Rain", 65: "Heavy rain",
            66: "Freezing rain", 67: "Freezing rain",
            71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow grains",
            80: "Light showers", 81: "Showers", 82: "Violent showers",
            85: "Snow showers", 86: "Heavy snow showers",
            95: "Thunderstorm", 96: "Thunderstorm with hail", 99: "Thunderstorm with hail"
        };
        return words[code] ?? "";
    }
}
