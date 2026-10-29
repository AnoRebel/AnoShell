// Bioma's Calendar API (GPL-3.0) over AnoShell's calendar services.
pragma Singleton

import QtQuick
import Quickshell
import qs.services as Ano

// What is on the calendar, in Bioma's shape, read from AnoShell's three
// feeds: the local events (CalendarEvents, recurrence expanded per day), the
// ICS feeds (CalendarSync) and the public holidays (Holidays). Nothing is
// fetched here; those services do their own reading.
//
// events: [{ uid, calendar, title, location, start, end, allDay }], in
// milliseconds, `end` exclusive, sorted by start, from today for `days` days
// (plus what began before today and is still on).
Singleton {
    id: root

    // Local events are always there to be added, so the agenda is never
    // "no calendar" while they are on.
    readonly property bool active: Ano.CalendarEvents.enabled || Ano.CalendarSync.enabled || Ano.Holidays.enabled

    // How far ahead, from today.
    readonly property int days: Math.max(1, Config.get("calendar.days", 62))

    function hold(owner, wanted) {}

    // The minute the answers below are judged by.
    property double now: Date.now()

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        onDateChanged: root.now = clock.date.getTime()
    }

    readonly property double todayStart: root.dayStart(root.now)
    readonly property double todayEnd: root.dayStart(root.todayStart, 1)

    // Midnight of the day `ms` falls in, moved by `offset` days.
    function dayStart(ms, offset) {
        const date = new Date(ms);
        return new Date(date.getFullYear(), date.getMonth(), date.getDate() + (offset || 0)).getTime();
    }

    // Sources that could not be read, in words.
    readonly property string problem: {
        const statuses = Ano.CalendarSync.sourceStatuses || {};
        return Object.keys(statuses).map(k => statuses[k]?.error || "").filter(e => e.length > 0).join(" ");
    }

    // Bumped whenever a feed changes, so `events` is rebuilt.
    property int revision: 0
    Connections { target: Ano.CalendarEvents; function onChanged() { root.revision++; } }
    Connections { target: Ano.Holidays; function onChanged() { root.revision++; } }

    readonly property var events: {
        void root.revision;
        const from = root.todayStart;
        const to = root.dayStart(from, root.days);
        const out = [];

        // ICS: already expanded. An all-day event's end is DTEND, exclusive;
        // without one it is the one day.
        for (const e of (Ano.CalendarSync.events || [])) {
            const start = new Date(e.startDate).getTime();
            let end = e.endDate ? new Date(e.endDate).getTime() : start;
            if (e.allDay && end <= start)
                end = root.dayStart(start, 1);
            if (isNaN(start) || start >= to || (end <= from && !(end === start && start >= from)))
                continue;
            out.push({ "uid": e.uid || `${e.sourceId}:${start}`, "calendar": e.sourceName || "",
                       "title": e.title || "", "location": e.location || "",
                       "start": start, "end": end, "allDay": !!e.allDay });
        }

        // Local events and holidays are asked per day: that is where their
        // recurrence and per-year data live. A local event has a time but no
        // length, so it ends when it starts.
        for (let day = from; day < to; day = root.dayStart(day, 1)) {
            const date = new Date(day);
            for (const e of (Ano.CalendarEvents.getEventsForDate(date) || [])) {
                const at = new Date(e.dateTime);
                const start = new Date(date.getFullYear(), date.getMonth(), date.getDate(),
                                       at.getHours(), at.getMinutes()).getTime();
                out.push({ "uid": `event:${e.id}`, "calendar": e.category || "Events",
                           "title": e.title || "", "location": e.description || "",
                           "start": start, "end": start, "allDay": false });
            }
            for (const h of (Ano.Holidays.getEventsForDate(date) || []))
                out.push({ "uid": `holiday:${day}:${h.title}`, "calendar": "Holidays",
                           "title": h.title || "", "location": "",
                           "start": day, "end": root.dayStart(day, 1), "allDay": true });
        }

        // All-day first within a day, then by start.
        return out.sort((a, b) => a.start - b.start || (b.allDay - a.allDay));
    }

    // Timed events going on right now.
    readonly property var ongoing: root.events.filter(e => !e.allDay && e.start <= root.now && root.now < e.end)

    // The next timed event to begin, or null.
    readonly property var next: root.events.find(e => !e.allDay && e.start > root.now) ?? null

    // Today, all-day first.
    readonly property var today: root.between(root.todayStart, root.todayEnd)

    // Events that overlap [from, to).
    function between(from, to) {
        return root.events.filter(e => e.start < to && (e.end > from || (e.end === e.start && e.start >= from)));
    }

    // The timed events that begin within the next `minutes`.
    function startingWithin(minutes) {
        const limit = root.now + minutes * 60000;
        return root.events.filter(e => !e.allDay && e.start > root.now && e.start <= limit);
    }
}
