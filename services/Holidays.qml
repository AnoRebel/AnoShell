pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Holidays — public holidays for the calendar, per country + year, cached.
 *
 * Sources (in order):
 *   1. Nager.Date  — https://date.nager.at/api/v3/PublicHolidays/{year}/{CC}
 *      Free, no API key, ~110 countries, localised names. PRIMARY.
 *   2. AbstractAPI — https://holidays.abstractapi.com/v1/  (needs an API key)
 *      FALLBACK, only used when a key is set AND Nager returned nothing/errored.
 *
 * Country resolution: explicit `country` if set; else IP auto-detect via
 * ip-api.com (no key); else `fallbackCountry` (default TZ / Tanzania).
 *
 * A year's data is fetched on demand (when the calendar shows a month in that
 * year) and cached to disk, so navigating is instant after the first fetch and
 * the shell works offline once warmed. Exposes the CalendarSync-compatible
 * getEventsForDate / getSourceColorsForDate so CalendarView renders holiday dots
 * and labels alongside ICS events and user events.
 */
Singleton {
    id: root

    readonly property var _cfg: Config.options?.calendar?.holidays
    readonly property bool enabled: root._cfg?.enable ?? false
    readonly property bool autoDetect: root._cfg?.autoDetect ?? true
    readonly property string configuredCountry: root._cfg?.country ?? ""
    readonly property string fallbackCountry: root._cfg?.fallbackCountry ?? "TZ"
    readonly property string abstractApiKey: root._cfg?.abstractApiKey ?? ""
    readonly property color holidayColor: root._cfg?.color ?? "#E06C75"

    // The resolved country actually in use (may come from IP detection).
    property string country: ""
    // year(number) -> [ {date:"YYYY-MM-DD", name, localName} ]
    property var _byYear: ({})
    // Set of "year" strings already fetched or in-flight, to dedupe.
    property var _fetchedYears: ({})

    readonly property string cachePath: Directories.genericCache + "/anoshell/holidays.json"

    signal changed()

    Component.onCompleted: {
        if (root.enabled) {
            _cache.reload()
            _resolveCountry()
        }
    }

    onEnabledChanged: if (enabled) { _cache.reload(); _resolveCountry() }
    // If the user changes country/detection, drop cached data and refetch.
    onConfiguredCountryChanged: root._resolveCountry()
    onAutoDetectChanged: root._resolveCountry()

    // ── Country resolution ────────────────────────────────────────────────────
    function _resolveCountry() {
        if (!root.enabled) return
        if (!root.autoDetect && root.configuredCountry.length === 2) {
            root._setCountry(root.configuredCountry.toUpperCase())
            return
        }
        // Explicit country wins even in auto mode if the user typed one.
        if (root.configuredCountry.length === 2) {
            root._setCountry(root.configuredCountry.toUpperCase())
            return
        }
        _geoProc.running = true   // IP detect; falls back on failure
    }

    function _setCountry(cc) {
        if (cc === root.country) return
        root.country = cc
        // Country changed → invalidate per-year data and refetch what's visible.
        root._byYear = ({})
        root._fetchedYears = ({})
        root.changed()
        // Warm the current year immediately.
        const now = new Date()
        root.ensureYear(now.getFullYear())
    }

    Process {
        id: _geoProc
        command: ["curl", "-s", "--max-time", "8", "http://ip-api.com/json/?fields=countryCode"]
        stdout: StdioCollector {
            onStreamFinished: {
                let cc = ""
                try { cc = (JSON.parse(this.text)?.countryCode ?? "").toUpperCase() } catch (e) {}
                root._setCountry(cc.length === 2 ? cc : root.fallbackCountry.toUpperCase())
            }
        }
        onExited: (code) => {
            if (code !== 0 && root.country === "")
                root._setCountry(root.fallbackCountry.toUpperCase())
        }
    }

    // ── Per-year fetch ────────────────────────────────────────────────────────
    // Called by the calendar when it displays a month; fetches that year once.
    function ensureYear(year) {
        if (!root.enabled || root.country === "") return
        const key = `${root.country}:${year}`
        if (root._fetchedYears[key]) return
        if (root._byYear[year] !== undefined) { root._fetchedYears[key] = true; return }
        root._fetchedYears[key] = true
        _nager.fetch(year)
    }

    Process {
        id: _nager
        property int year: 0
        function fetch(y) {
            _nager.year = y
            _nager.command = ["curl", "-s", "--max-time", "12",
                `https://date.nager.at/api/v3/PublicHolidays/${y}/${root.country}`]
            _nager.running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let ok = false
                try {
                    const arr = JSON.parse(this.text)
                    if (Array.isArray(arr) && arr.length > 0) {
                        root._storeYear(_nager.year, arr.map(h => ({
                            date: h.date, name: h.name, localName: h.localName || h.name
                        })))
                        ok = true
                    }
                } catch (e) {}
                if (!ok) root._tryFallback(_nager.year)
            }
        }
        onExited: (code) => { if (code !== 0) root._tryFallback(_nager.year) }
    }

    // AbstractAPI fallback — one call per date is wasteful, so it only fetches
    // the whole year via its year endpoint. Only runs when a key is present.
    function _tryFallback(year) {
        if (root.abstractApiKey.length === 0) {
            // No fallback available; cache an empty year so we don't retry loop.
            if (root._byYear[year] === undefined) root._storeYear(year, [])
            return
        }
        _abstract.fetch(year)
    }

    Process {
        id: _abstract
        property int year: 0
        function fetch(y) {
            _abstract.year = y
            // AbstractAPI needs a specific date; request Jan 1 with year param —
            // its holidays endpoint returns the full year for the country.
            _abstract.command = ["curl", "-s", "--max-time", "12",
                `https://holidays.abstractapi.com/v1/?api_key=${root.abstractApiKey}&country=${root.country}&year=${y}`]
            _abstract.running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(this.text)
                    if (Array.isArray(arr))
                        root._storeYear(_abstract.year, arr.map(h => ({
                            date: h.date_year_agnostic ? `${_abstract.year}-${h.date}` : (h.date || ""),
                            name: h.name, localName: h.name_local || h.name
                        })).filter(h => h.date))
                    else root._storeYear(_abstract.year, [])
                } catch (e) { root._storeYear(_abstract.year, []) }
            }
        }
        onExited: (code) => { if (code !== 0 && root._byYear[_abstract.year] === undefined) root._storeYear(_abstract.year, []) }
    }

    function _storeYear(year, holidays) {
        const m = Object.assign({}, root._byYear)
        m[year] = holidays
        root._byYear = m
        root._saveCache()
        root.changed()
    }

    // ── Cache ─────────────────────────────────────────────────────────────────
    FileView {
        id: _cache
        path: Qt.resolvedUrl(root.cachePath)
        printErrors: false // no cache yet on a first start: not an error
        onLoaded: {
            try {
                const data = JSON.parse(_cache.text())
                if (data.country) root.country = data.country
                root._byYear = data.byYear || ({})
                root.changed()
            } catch (e) {}
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                const dir = root.cachePath.substring(0, root.cachePath.lastIndexOf('/'))
                Quickshell.execDetached(["/usr/bin/mkdir", "-p", dir])
            }
        }
    }
    function _saveCache() {
        _cache.setText(JSON.stringify({ country: root.country, byYear: root._byYear }, null, 2))
    }

    // ── Queries (CalendarSync-compatible) ─────────────────────────────────────
    function _isoOf(date) {
        const d = new Date(date)
        const y = d.getFullYear()
        const m = String(d.getMonth() + 1).padStart(2, "0")
        const day = String(d.getDate()).padStart(2, "0")
        return `${y}-${m}-${day}`
    }

    function getEventsForDate(date) {
        if (!root.enabled) return []
        const d = new Date(date)
        root.ensureYear(d.getFullYear())
        const iso = root._isoOf(d)
        const list = root._byYear[d.getFullYear()] || []
        return list.filter(h => h.date === iso).map(h => ({
            title: h.localName || h.name,
            startDate: new Date(iso + "T00:00:00").toISOString(),
            allDay: true,
            sourceId: "holidays",
            sourceColor: root.holidayColor.toString(),
            isHoliday: true
        }))
    }

    function getSourceColorsForDate(date) {
        return root.getEventsForDate(date).length > 0 ? [root.holidayColor.toString()] : []
    }

    // Human-readable holiday names for a date (for tooltips / labels).
    function getHolidayNames(date) {
        return root.getEventsForDate(date).map(h => h.title)
    }
}
