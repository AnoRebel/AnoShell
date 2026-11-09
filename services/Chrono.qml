pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Alarms and world clocks for the Clock panel (modules/clock). Always loaded
 * (shell.qml touches it), so alarms ring with the panel closed. The timer and
 * stopwatch are services/Pomodoro's countdown and stopwatch, shared with the
 * timer piece and the sidebar.
 *
 * State: $XDG_STATE_HOME/anoshell/clock.json
 *   { alarms: [{ id, label, h, m, days: [0-6, Sunday = 0; empty = once], on }],
 *     zones: ["Asia/Tokyo", …] }
 *
 * The check runs once a minute, aligned to the minute (no polling), over the
 * window since the last check, so an alarm due while suspended still fires on
 * resume (or is reported missed when more than 30 min late).
 *
 * IPC: qs -c ano ipc call clock toggle|open|close|dismiss|snooze|next
 */
Singleton {
    id: root

    readonly property var cfg: Config.options?.clock ?? ({})
    readonly property var alarms: store.alarms ?? []
    readonly property var zones: store.zones ?? []
    property real now: Date.now() // refreshed every minute

    // ── Alarms ────────────────────────────────────────────────────────
    function _save(): void { stateFile.writeAdapter() }
    function saveAlarm(a): void {
        const list = root.alarms.filter(x => x.id !== a.id)
        list.push({ id: a.id || Date.now().toString(36), label: String(a.label ?? "").trim(),
            h: Math.max(0, Math.min(23, a.h | 0)), m: Math.max(0, Math.min(59, a.m | 0)),
            days: (a.days ?? []).slice().sort(), on: a.on ?? true })
        list.sort((x, y) => x.h * 60 + x.m - (y.h * 60 + y.m))
        store.alarms = list
        root._save()
    }
    function deleteAlarm(id: string): void {
        store.alarms = root.alarms.filter(x => x.id !== id)
        const s = Object.assign({}, root.snoozes); delete s[id]; root.snoozes = s
        root._save()
    }
    function setAlarmOn(id: string, on: bool): void {
        store.alarms = root.alarms.map(x => x.id === id ? Object.assign({}, x, { on }) : x)
        if (!on) { const s = Object.assign({}, root.snoozes); delete s[id]; root.snoozes = s }
        root._save()
    }

    // Next time (ms) alarm a fires after t, or 0.
    function nextFire(a, t: real): real {
        if (!a.on) return 0
        const base = new Date(t)
        for (let d = 0; d <= 7; d++) {
            const c = new Date(base.getFullYear(), base.getMonth(), base.getDate() + d, a.h, a.m)
            if (c.getTime() > t && (!a.days?.length || a.days.includes(c.getDay()))) return c.getTime()
        }
        return 0
    }
    // { id, label, at } of the next alarm (snoozes included), or null.
    readonly property var nextAlarm: {
        let best = null
        for (const a of root.alarms) {
            const at = Math.min(...[root.nextFire(a, root.now), root.snoozes[a.id] ?? 0].filter(x => x > 0).concat([Infinity]))
            if (at < Infinity && (!best || at < best.at)) best = { id: a.id, label: a.label, at }
        }
        return best
    }
    function fmtTime(h: int, m: int): string {
        return Qt.locale().toString(new Date(2000, 0, 1, h, m), Config.options?.time?.format ?? "hh:mm")
    }
    // "Tue 07:30" (or "07:30" within a day) for the next alarm, "" when none.
    readonly property string nextAlarmText: {
        const n = root.nextAlarm
        if (!n) return ""
        const d = new Date(n.at)
        const t = root.fmtTime(d.getHours(), d.getMinutes())
        return n.at - root.now < 86400000 ? t : `${Qt.locale().toString(d, "ddd")} ${t}`
    }
    function daysText(days): string {
        if (!days?.length) return "Once"
        if (days.length === 7) return "Every day"
        const s = days.join()
        if (s === "1,2,3,4,5") return "Weekdays"
        if (s === "0,6") return "Weekends"
        return days.map(d => Qt.locale().dayName(d, Locale.ShortFormat)).join(" ")
    }

    // In memory: a restart drops a pending snooze.
    property var snoozes: ({}) // id -> ms epoch
    property real _lastCheck: Date.now()
    function _check(): void {
        const t = Date.now(), from = root._lastCheck
        root._lastCheck = t
        root.now = t
        const due = []
        const s = Object.assign({}, root.snoozes)
        for (const a of root.alarms) {
            const at = root.nextFire(a, from)
            const snz = s[a.id] ?? 0
            if (snz > from && snz <= t) { delete s[a.id]; due.push({ a, at: snz }) }
            else if (at > 0 && at <= t) due.push({ a, at })
        }
        root.snoozes = s
        if (!due.length) return
        // One-time alarms switch off once they've gone off.
        if (due.some(x => !x.a.days?.length)) {
            store.alarms = root.alarms.map(x => due.some(y => y.a.id === x.id) && !x.days?.length ? Object.assign({}, x, { on: false }) : x)
            root._save()
        }
        for (const x of due) {
            const late = t - x.at > 30 * 60000
            if (late) Quickshell.execDetached(["notify-send", "-a", "AnoShell", "-i", "alarm", "--", "Missed alarm",
                `${x.a.label || "Alarm"} · ${root.fmtTime(x.a.h, x.a.m)}`])
            else root._ring(x.a)
        }
    }
    function _start(): void {
        if (minuteTimer.running) return
        root._lastCheck = Date.now()
        minuteTimer.interval = 60000 - Date.now() % 60000 + 50
        minuteTimer.start()
    }
    Timer {
        id: minuteTimer
        interval: 60000 - Date.now() % 60000 + 50
        onTriggered: {
            root._check()
            if (new Date().getMinutes() === 0) root.refreshZones() // DST changes
            interval = 60000 - Date.now() % 60000 + 50
            restart()
        }
    }

    // ── Ringing ───────────────────────────────────────────────────────
    property var ringing: null // { ids, label, notifId, token }
    function _ring(a): void {
        const label = a.label || "Alarm"
        if (root.ringing) { // already ringing: one notification for both
            root.ringing = Object.assign({}, root.ringing, { ids: root.ringing.ids.concat([a.id]), label: `${root.ringing.label}, ${label}` })
            return
        }
        const token = Date.now()
        root.ringing = { ids: [a.id], label, notifId: -1, token }
        ringNotifier.token = token
        ringNotifier.exec(["notify-send", "-a", "AnoShell", "-u", "critical", "-t", "0", "-i", "alarm", "-p", "--wait",
            "-A", `snooze=Snooze ${root.snoozeMinutes} min`, "-A", "dismiss=Dismiss", "--",
            label, root.fmtTime(a.h, a.m)])
        root._beep()
    }
    readonly property int snoozeMinutes: Math.max(1, root.cfg.snoozeMinutes ?? 10)
    function _stopRinging(): void {
        const r = root.ringing
        root.ringing = null
        if (r && r.notifId >= 0) Notifications.discardNotification(r.notifId + Notifications.idOffset)
    }
    function dismiss(): void { root._stopRinging() }
    function snooze(): void {
        const r = root.ringing
        if (!r) return
        const s = Object.assign({}, root.snoozes)
        for (const id of r.ids) s[id] = Date.now() + root.snoozeMinutes * 60000
        root.snoozes = s
        root._stopRinging()
    }
    // notify-send -p prints the id, then (--wait) the chosen action.
    Process {
        id: ringNotifier
        property real token: 0
        stdout: SplitParser {
            onRead: line => {
                const r = root.ringing
                if (!r || r.token !== ringNotifier.token) return
                const s = line.trim()
                if (/^\d+$/.test(s)) root.ringing = Object.assign({}, r, { notifId: Number(s) })
                else if (s === "snooze") root.snooze()
                else if (s === "dismiss") root.dismiss()
            }
        }
        // Closed without an action: the alarm is dismissed.
        onExited: if (root.ringing && root.ringing.token === ringNotifier.token) root.dismiss()
    }
    // The alarm sound plays even though shell sounds are off by default
    // (clock.alarmSound); pw-play at sounds.volume.
    function _beep(): void { if (root.cfg.alarmSound ?? true) Audio.playSystemSound("alarm-clock-elapsed") }
    Timer {
        interval: 4000
        repeat: true
        running: root.ringing !== null
        onTriggered: root._beep()
    }
    // Rings at most clock.ringMinutes, then becomes a "Missed alarm" notice.
    Timer {
        interval: Math.max(1, root.cfg.ringMinutes ?? 5) * 60000
        running: root.ringing !== null
        onTriggered: {
            const label = root.ringing?.label ?? "Alarm"
            root.dismiss()
            Quickshell.execDetached(["notify-send", "-a", "AnoShell", "-i", "alarm", "--", "Missed alarm", label])
        }
    }

    // Countdown done (Pomodoro clears cdLeftMs to 0 when it ends): the same sound.
    Connections {
        target: Pomodoro
        function onCdLeftMsChanged() { if (Pomodoro.cdLeftMs === 0 && !Pomodoro.cdRunning) root._beep() }
    }
    // Pomodoro's timers only tick while held: hold it while the panel is
    // open or a countdown runs, so it ends on time with the panel closed.
    readonly property bool _wantPomodoro: GlobalStates.clockOpen || Pomodoro.cdRunning
    on_WantPomodoroChanged: Pomodoro.hold(root._wantPomodoro)

    // ── World clocks ──────────────────────────────────────────────────
    // QML's JS engine has no Intl/timeZone support, so each zone's UTC
    // offset comes from `date +%z` run with TZ=:<zone> (no shell).
    property var offsets: ({}) // zone -> minutes east of UTC
    property string zoneError: ""
    readonly property var _zoneRe: /^[A-Za-z0-9_+-]+(\/[A-Za-z0-9_+-]+)*$/
    function addZone(zone: string): void {
        const z = String(zone ?? "").trim()
        root.zoneError = ""
        if (!z || root.zones.includes(z)) return
        if (!root._zoneRe.test(z)) { root.zoneError = `“${z}” isn't a time zone name (like Europe/Paris)`; return }
        zoneCheck.zone = z
        zoneCheck.exec(["test", "-f", `/usr/share/zoneinfo/${z}`])
    }
    function removeZone(zone: string): void {
        store.zones = root.zones.filter(z => z !== zone)
        root._save()
    }
    Process {
        id: zoneCheck
        property string zone: ""
        onExited: code => {
            if (code !== 0) { root.zoneError = `Unknown time zone “${zoneCheck.zone}”`; return }
            if (root.zones.includes(zoneCheck.zone)) return
            store.zones = root.zones.concat([zoneCheck.zone])
            root._save()
            root.refreshZones()
        }
    }
    // Zones others show (the world clock piece) besides the panel's own:
    // resolved and kept fresh the same way. Unknown names land in badZones.
    property var extraZones: []
    property var badZones: ({}) // zone -> true
    function watchZones(list): void {
        const add = (list ?? []).filter(z => root._zoneRe.test(z) && !root.zones.includes(z) && !root.extraZones.includes(z))
        if (!add.length) return
        root.extraZones = root.extraZones.concat(add)
        root._queue = root._queue.concat(add)
        root._nextZone()
    }
    property var _queue: []
    function refreshZones(): void { root._queue = root.zones.concat(root.extraZones); root._nextZone() }
    function _nextZone(): void {
        if (!root._queue.length || tzProc.running) return
        tzProc.zone = root._queue[0]
        // glibc falls back to UTC for a name it doesn't know, so the zone file
        // is checked first (the zone is an argument, never part of the script).
        tzProc.exec({ command: ["sh", "-c", '[ -f "/usr/share/zoneinfo/$1" ] && exec date +%z', "sh", tzProc.zone],
                      environment: { TZ: `:${tzProc.zone}` } })
    }
    Process {
        id: tzProc
        property string zone: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /^([+-])(\d\d)(\d\d)/.exec(this.text.trim())
                if (m) {
                    const o = Object.assign({}, root.offsets)
                    o[tzProc.zone] = (m[1] === "-" ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3]))
                    root.offsets = o
                } else if (!root.badZones[tzProc.zone]) {
                    const b = Object.assign({}, root.badZones); b[tzProc.zone] = true; root.badZones = b
                }
                root._queue = root._queue.filter(z => z !== tzProc.zone)
                Qt.callLater(root._nextZone)
            }
        }
    }
    // The zone's wall time at `now`, as a local Date for formatting.
    function zoneDate(zone: string, t: real): var {
        const s = new Date(t + (root.offsets[zone] ?? 0) * 60000)
        return new Date(s.getUTCFullYear(), s.getUTCMonth(), s.getUTCDate(), s.getUTCHours(), s.getUTCMinutes(), s.getUTCSeconds())
    }
    function zoneName(zone: string): string { return zone.split("/").pop().replace(/_/g, " ") }

    // ── State ─────────────────────────────────────────────────────────
    FileView {
        id: stateFile
        path: `${FileUtils.trimFileProtocol(Directories.state)}/anoshell/clock.json`
        watchChanges: false
        printErrors: false
        onLoaded: { Qt.callLater(root.refreshZones); root._start() }
        onLoadFailed: root._start()
        JsonAdapter {
            id: store
            property var alarms: []
            property var zones: []
        }
    }

    IpcHandler {
        target: "clock"
        function toggle(): void { GlobalStates.clockOpen = !GlobalStates.clockOpen }
        function open(): void { GlobalStates.clockOpen = true }
        function close(): void { GlobalStates.clockOpen = false }
        function dismiss(): void { root.dismiss() }
        function snooze(): void { root.snooze() }
        function next(): string { return root.nextAlarmText }
        // Start a countdown of N seconds, or toggle the stopwatch (scripts, keybinds).
        function countdown(seconds: int): void { Pomodoro.cdSet(seconds); Pomodoro.cdToggle() }
        function stopwatch(): void { Pomodoro.swToggle() }
    }
}
