pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * CalendarEvents — user-created calendar events with recurrence and reminders.
 *
 * Ported and enhanced from inir's Events.qml. Differences from the source:
 *   - Uses ano's Directories.eventsPath + notify-send for reminders.
 *   - RECURRENCE IS EXPANDED FOR DISPLAY: inir only materialised the next
 *     occurrence when the current one fired, so future recurring dates showed no
 *     dot in the calendar until they had passed. `getEventsForDate` here also
 *     matches an event's recurrence rule against the queried date, so a weekly
 *     event dots every matching future day without pre-creating rows.
 *   - Exposes `getSourceColorsForDate()` so CalendarView renders event dots the
 *     same way it renders ICS (CalendarSync) and holiday dots.
 *
 * This is the ONLY user-event store; it is separate from CalendarSync, which is
 * read-only external ICS. The calendar UI merges all three feeds.
 *
 * Stored object: { id, title, description, dateTime(ISO), category, priority,
 *   reminderMinutes, recurrence, recurrenceEnd(ISO|""), notified,
 *   reminderNotified, createdAt }.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.calendar?.events?.enable ?? true
    readonly property color eventColor: Appearance?.colors.colPrimary ?? "#65558F"

    property string filePath: Directories.eventsPath
    property var list: []
    property int nextId: 1

    signal eventAdded(var event)
    signal eventRemoved(int id)
    signal eventUpdated(var event)
    signal eventTriggered(var event)
    signal reminderTriggered(var event, int minutesBefore)
    signal changed()   // any add/remove/update — the calendar re-reads on this

    Component.onCompleted: {
        loadFromFile()
        checkTimer.start()
    }

    FileView {
        id: eventsFileView
        path: Qt.resolvedUrl(root.filePath)
        watchChanges: true
        onLoaded: {
            const txt = eventsFileView.text()
            if (!txt || txt.trim() === "") {
                root.list = []; root.nextId = 1; root.changed(); return
            }
            try {
                const data = JSON.parse(txt)
                root.list = data.events || []
                root.nextId = data.nextId || 1
                root.changed()
            } catch (e) {
                console.warn("[CalendarEvents] parse failed:", e)
                root.list = []; root.nextId = 1
            }
        }
        onLoadFailed: (error) => {
            if (error === FileViewError.FileNotFound) {
                const dir = root.filePath.substring(0, root.filePath.lastIndexOf('/'))
                Quickshell.execDetached(["/usr/bin/mkdir", "-p", dir])
                root.list = []; root.nextId = 1
                Qt.callLater(root.saveToFile) // a write from inside the load handler is dropped
            } else {
                console.warn("[CalendarEvents] load error:", error)
                root.list = []; root.nextId = 1
            }
        }
    }

    // Fire reminders / event-time notifications once a minute.
    Timer {
        id: checkTimer
        interval: 60000
        repeat: true
        onTriggered: root.checkDueEvents()
    }

    function checkDueEvents() {
        if (!root.enabled) return
        const currentTime = Date.now()
        let needsSave = false

        for (let i = 0; i < root.list.length; i++) {
            const event = root.list[i]
            if (!event.dateTime) continue
            const eventTime = new Date(event.dateTime).getTime()
            const reminderMinutes = event.reminderMinutes ?? 0
            const reminderTime = eventTime - reminderMinutes * 60000

            if (reminderMinutes > 0 && !event.reminderNotified
                    && currentTime >= reminderTime && currentTime < eventTime) {
                root.list[i].reminderNotified = true
                root._notify(event, `in ${root._humanMinutes(reminderMinutes)}`)
                root.reminderTriggered(event, reminderMinutes)
                needsSave = true
            }

            if (!event.notified && currentTime >= eventTime) {
                root.list[i].notified = true
                root._notify(event, "now")
                root.eventTriggered(event)
                needsSave = true
                // Materialise the next occurrence so its own reminder/notify fire.
                // (Display already handles future occurrences via getEventsForDate.)
                if (event.recurrence && event.recurrence !== "none") {
                    const next = root._nextOccurrence(new Date(event.dateTime), event.recurrence)
                    if (next && root._withinRecurrenceEnd(next, event))
                        root.addEvent(event.title, event.description, next.toISOString(),
                            event.category, event.priority, event.reminderMinutes,
                            event.recurrence, event.recurrenceEnd)
                }
            }
        }
        if (needsSave) root.saveToFile()
    }

    function _notify(event, whenStr) {
        const urgency = event.priority === "high" ? "critical" : "normal"
        Quickshell.execDetached(["notify-send", event.title || "Event",
            (event.description ? event.description + "\n" : "") + `Event ${whenStr}`,
            "-u", urgency, "-a", "Ano Calendar", "-i", root.getCategoryIcon(event.category)])
    }

    function _humanMinutes(m) {
        if (m >= 1440) return `${Math.round(m / 1440)} day(s)`
        if (m >= 60) return `${Math.round(m / 60)} hour(s)`
        return `${m} min`
    }

    // ── Recurrence helpers ────────────────────────────────────────────────────
    function _nextOccurrence(fromDate, recurrence) {
        const d = new Date(fromDate)
        switch (recurrence) {
            case "daily": d.setDate(d.getDate() + 1); return d
            case "weekly": d.setDate(d.getDate() + 7); return d
            case "monthly": d.setMonth(d.getMonth() + 1); return d
            case "yearly": d.setFullYear(d.getFullYear() + 1); return d
            default: return null
        }
    }

    function _withinRecurrenceEnd(date, event) {
        if (!event.recurrenceEnd) return true
        return date.getTime() <= new Date(event.recurrenceEnd).getTime()
    }

    // Does `event` (with its recurrence rule) fall on `targetMidnight`?
    // Matches the original date OR any recurrence up to the target, without
    // pre-creating rows — so future recurring days dot correctly.
    function _recursOn(event, targetMidnight) {
        const start = new Date(event.dateTime); start.setHours(0, 0, 0, 0)
        const t = targetMidnight.getTime()
        if (start.getTime() === t) return true
        if (!event.recurrence || event.recurrence === "none") return false
        if (t < start.getTime()) return false
        if (event.recurrenceEnd && t > new Date(event.recurrenceEnd).getTime()) return false

        switch (event.recurrence) {
            case "daily":
                return true   // every day on/after start (within end)
            case "weekly":
                return start.getDay() === targetMidnight.getDay()
            case "monthly":
                return start.getDate() === targetMidnight.getDate()
            case "yearly":
                return start.getDate() === targetMidnight.getDate()
                    && start.getMonth() === targetMidnight.getMonth()
            default:
                return false
        }
    }

    // ── Queries ───────────────────────────────────────────────────────────────
    function getEventsForDate(date) {
        const target = new Date(date); target.setHours(0, 0, 0, 0)
        return root.list
            .filter(e => root._recursOn(e, target))
            .sort((a, b) => new Date(a.dateTime).getHours() - new Date(b.dateTime).getHours())
    }

    function getUpcomingEvents(days) {
        const now = new Date()
        const out = []
        const horizon = days || 7
        for (let i = 0; i < horizon; i++) {
            const day = new Date(now); day.setDate(now.getDate() + i)
            for (const e of root.getEventsForDate(day)) {
                const occ = new Date(day)
                const orig = new Date(e.dateTime)
                occ.setHours(orig.getHours(), orig.getMinutes(), 0, 0)
                if (occ >= now) out.push(Object.assign({}, e, { occurrence: occ.toISOString() }))
            }
        }
        return out.sort((a, b) => new Date(a.occurrence) - new Date(b.occurrence))
    }

    // Colour feed for CalendarView (mirrors CalendarSync.getSourceColorsForDate).
    function getSourceColorsForDate(date) {
        return root.getEventsForDate(date).length > 0 ? [root.eventColor.toString()] : []
    }

    // ── Mutations ─────────────────────────────────────────────────────────────
    function addEvent(title, description, dateTime, category, priority, reminderMinutes, recurrence, recurrenceEnd) {
        const event = {
            id: root.nextId++,
            title: title || "",
            description: description || "",
            dateTime: dateTime || new Date().toISOString(),
            category: category || "general",       // general, birthday, meeting, deadline, reminder
            priority: priority || "normal",         // low, normal, high
            reminderMinutes: reminderMinutes ?? 15, // 0, 5, 15, 30, 60, 1440
            recurrence: recurrence || "none",       // none, daily, weekly, monthly, yearly
            recurrenceEnd: recurrenceEnd || "",     // ISO date; "" = no end
            notified: false,
            reminderNotified: false,
            createdAt: new Date().toISOString()
        }
        root.list.push(event)
        root.list = root.list
        root.eventAdded(event); root.changed(); root.saveToFile()
        return event
    }

    function removeEvent(id) {
        const i = root.list.findIndex(e => e.id === id)
        if (i === -1) return false
        root.list.splice(i, 1)
        root.list = root.list
        root.eventRemoved(id); root.changed(); root.saveToFile()
        return true
    }

    function updateEvent(id, updates) {
        const i = root.list.findIndex(e => e.id === id)
        if (i === -1) return false
        root.list[i] = Object.assign({}, root.list[i], updates)
        root.list = root.list
        root.eventUpdated(root.list[i]); root.changed(); root.saveToFile()
        return true
    }

    function saveToFile() {
        eventsFileView.setText(JSON.stringify({ nextId: root.nextId, events: root.list }, null, 2))
    }

    function loadFromFile() { eventsFileView.reload() }

    function getCategoryIcon(category) {
        switch (category) {
            case "birthday": return "cake"
            case "meeting": return "groups"
            case "deadline": return "flag"
            case "reminder": return "notifications"
            default: return "event"
        }
    }
}
