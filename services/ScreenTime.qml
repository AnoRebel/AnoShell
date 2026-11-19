pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Screen time (screenTime.enable): every 15 s the focused window's app and
 * title get 15 s, unless the session is idle (no input for
 * screenTime.idleSeconds, unless the focused app is the one playing media:
 * a video you watch counts, music in the background while you're away
 * doesn't) or locked. Idle inhibitors are ignored, so a forgotten
 * "keep awake" toggle doesn't count the whole night. Credits go to anod once a minute
 * (screentime.add), which keeps them in local day files.
 *
 * FocusTime (focusTime.enable, default on) takes the same ticks, minus the
 * apps in focusTime.excludeApps, into anod's own FocusTime store
 * (focustime.add, kept for good); the FocusTime panel reads it back.
 *
 * Daily limits (idea from ilyamiro-new's wellbeing): screenTime.dailyLimitMinutes
 * for everything and screenTime.appLimits { appId: minutes } per app. After
 * each report the day's totals are checked; reaching a limit gives one
 * critical notification per day (remembered across restarts). Nothing is
 * blocked or closed.
 */
Singleton {
    id: root
    readonly property bool enabled: Config.options?.screenTime?.enable ?? false
    readonly property bool idle: root._noInput && !root._focusedIsPlaying
    readonly property bool _focusedIsPlaying: {
        const p = MprisController.activePlayer
        const app = String(ToplevelManager.activeToplevel?.appId ?? "").toLowerCase()
        if (!MprisController.isPlaying || !p || !app) return false
        const names = [p.desktopEntry, p.identity].map(n => String(n ?? "").toLowerCase()).filter(n => n.length > 1)
        const base = app.split(".").pop()
        return names.some(n => n === app || n.includes(base) || base.includes(n))
    }
    readonly property bool counting: root.enabled && !root.idle && !GlobalStates.screenLocked && !!ToplevelManager.activeToplevel

    property var _pending: ({})        // "app\u0000title" → seconds not sent yet
    property var _focusPending: ({})   // the same, for FocusTime
    readonly property bool focusEnabled: Config.ready && (Config.options?.focusTime?.enable ?? true)
    readonly property var _focusExclude: (Config.options?.focusTime?.excludeApps ?? []).map(a => String(a).toLowerCase())
    readonly property bool _anyEnabled: root.enabled || root.focusEnabled
    // Focused, not idle, not locked: the tick counts (for whichever is on).
    readonly property bool _active: !root.idle && !GlobalStates.screenLocked && !!ToplevelManager.activeToplevel

    // Created once the config is known, with its final values: an IdleMonitor
    // made before (disabled, then enabled by a binding) never reported idle.
    readonly property int _idleTimeout: Math.max(30, Config.options?.screenTime?.idleSeconds ?? 120)
    Loader {
        id: idleLoader
        active: root._anyEnabled && Config.ready
        // a new monitor when the timeout changes
        sourceComponent: IdleMonitor {
            enabled: true
            timeout: root._idleTimeout
            respectInhibitors: false
        }
    }
    on_IdleTimeoutChanged: if (idleLoader.active) { idleLoader.active = false; Qt.callLater(() => idleLoader.active = Qt.binding(() => root._anyEnabled && Config.ready)) }
    readonly property bool _noInput: idleLoader.item?.isIdle ?? false

    Timer {
        interval: 15000
        repeat: true
        running: root._anyEnabled
        onTriggered: {
            if (!root._active) return
            const t = ToplevelManager.activeToplevel
            const key = `${t?.appId || "unknown"}\u0000${t?.title ?? ""}`
            if (root.enabled) {
                const p = Object.assign({}, root._pending)
                p[key] = (p[key] ?? 0) + 15
                root._pending = p
            }
            if (root.focusEnabled && !root._focusExclude.includes(String(t?.appId ?? "").toLowerCase())) {
                const f = Object.assign({}, root._focusPending)
                f[key] = (f[key] ?? 0) + 15
                root._focusPending = f
            }
        }
    }
    Timer {
        interval: 60000
        repeat: true
        running: root._anyEnabled
        onTriggered: root.flush()
    }
    function flush() {
        if (!Anod.available) return // kept until anod is back
        let left = 1
        const done = () => { if (--left === 0) root.updated() } // refresh once they've landed
        for (const [prop, method] of [["_pending", "screentime.add"], ["_focusPending", "focustime.add"]]) {
            const p = root[prop]
            root[prop] = {}
            for (const key in p) {
                const [app, title] = key.split("\u0000")
                // anod takes at most 120 s per report (time saved up while it was away goes in parts)
                for (let rest = p[key]; rest > 0; rest -= 120) {
                    const secs = Math.min(120, rest)
                    left++
                    Anod.call(method, { app: app, title: title, seconds: secs }, (r, e) => {
                        if (e) { const q = Object.assign({}, root[prop]); q[key] = (q[key] ?? 0) + secs; root[prop] = q } // try again next minute
                        done()
                    })
                }
            }
        }
        if (left > 1) done() // nothing sent: no refresh
    }
    signal updated()

    // ── Daily limits ─────────────────────────────────────────────────────
    readonly property int dailyLimit: Math.max(0, Config.options?.screenTime?.dailyLimitMinutes ?? 0)
    readonly property var appLimits: Config.options?.screenTime?.appLimits ?? ({})
    readonly property bool _hasLimits: root.dailyLimit > 0 || Object.keys(root.appLimits).some(k => (root.appLimits[k] ?? 0) > 0)
    onUpdated: if (root._hasLimits) root.checkLimits()
    // and once anod is there (a restart after the limit was reached today
    // stays quiet: the notified list is kept).
    Connections {
        target: Anod
        function onAvailableChanged() { if (Anod.available && root.enabled && root._hasLimits) root.checkLimits() }
    }
    function _today() { return Qt.formatDate(new Date(), "yyyy-MM-dd") }
    // The day's "already told you" list is read first (else a restart could
    // tell you again); a missing file counts as read.
    property bool _limitsRead: false
    function checkLimits() {
        if (!root._limitsRead) { Qt.callLater(() => { if (root._limitsRead) root.checkLimits() }); return }
        Anod.call("screentime.day", {}, (r, e) => {
            if (!r) return
            const today = root._today()
            const done = limitState.date === today ? limitState.notified.slice() : []
            const hit = []
            if (root.dailyLimit > 0 && r.total >= root.dailyLimit * 60 && !done.includes("*"))
                hit.push({ key: "*", text: `You've reached your daily screen time (${root.dailyLimit} min).` })
            for (const app in root.appLimits) {
                const min = root.appLimits[app] ?? 0
                // app ids match whatever their case (Firefox / firefox)
                const used = Object.keys(r.perApp ?? {}).filter(k => k.toLowerCase() === app.toLowerCase()).reduce((n, k) => n + r.perApp[k], 0)
                if (min > 0 && used >= min * 60 && !done.includes(app))
                    hit.push({ key: app, text: `You've reached today's limit for ${app} (${min} min).` })
            }
            if (!hit.length) return
            for (const h of hit) {
                Quickshell.execDetached(["notify-send", "-u", "critical", "-a", "AnoShell", "-i", "hourglass", "--", "Screen time", h.text])
                done.push(h.key)
            }
            limitState.date = today
            limitState.notified = done
            limitFile.writeAdapter()
        })
    }
    FileView {
        id: limitFile
        path: `${FileUtils.trimFileProtocol(Directories.state)}/anoshell/screentime-limits.json`
        watchChanges: false
        printErrors: false
        onLoaded: { root._limitsRead = true; if (Anod.available && root.enabled && root._hasLimits) root.checkLimits() }
        onLoadFailed: { root._limitsRead = true; if (Anod.available && root.enabled && root._hasLimits) root.checkLimits() }
        JsonAdapter {
            id: limitState
            property string date: ""
            property var notified: []
        }
    }
}
