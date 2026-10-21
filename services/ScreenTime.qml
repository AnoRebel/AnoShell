pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.services

/**
 * Screen time (screenTime.enable): every 15 s the focused window's app and
 * title get 15 s, unless the session is idle (no input for
 * screenTime.idleSeconds, unless the focused app is the one playing media:
 * a video you watch counts, music in the background while you're away
 * doesn't) or locked. Idle inhibitors are ignored, so a forgotten
 * "keep awake" toggle doesn't count the whole night. Credits go to anod once a minute
 * (screentime.add), which keeps them in local day files.
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

    // Created once the config is known, with its final values: an IdleMonitor
    // made before (disabled, then enabled by a binding) never reported idle.
    readonly property int _idleTimeout: Math.max(30, Config.options?.screenTime?.idleSeconds ?? 120)
    Loader {
        id: idleLoader
        active: root.enabled && Config.ready
        // a new monitor when the timeout changes
        sourceComponent: IdleMonitor {
            enabled: true
            timeout: root._idleTimeout
            respectInhibitors: false
        }
    }
    on_IdleTimeoutChanged: if (idleLoader.active) { idleLoader.active = false; Qt.callLater(() => idleLoader.active = Qt.binding(() => root.enabled && Config.ready)) }
    readonly property bool _noInput: idleLoader.item?.isIdle ?? false

    Timer {
        interval: 15000
        repeat: true
        running: root.enabled
        onTriggered: {
            if (!root.counting) return
            const t = ToplevelManager.activeToplevel
            const key = `${t?.appId || "unknown"}\u0000${t?.title ?? ""}`
            const p = Object.assign({}, root._pending)
            p[key] = (p[key] ?? 0) + 15
            root._pending = p
        }
    }
    Timer {
        interval: 60000
        repeat: true
        running: root.enabled
        onTriggered: root.flush()
    }
    function flush() {
        if (!Anod.available) return // kept until anod is back
        const p = root._pending
        root._pending = {}
        let left = 0
        const done = () => { if (--left === 0) root.updated() } // refresh once they've landed
        for (const key in p) {
            const [app, title] = key.split("\u0000")
            // anod takes at most 120 s per report (time saved up while it was away goes in parts)
            for (let rest = p[key]; rest > 0; rest -= 120) {
                const secs = Math.min(120, rest)
                left++
                Anod.call("screentime.add", { app: app, title: title, seconds: secs }, (r, e) => {
                    if (e) { const q = Object.assign({}, root._pending); q[key] = (q[key] ?? 0) + secs; root._pending = q } // try again next minute
                    done()
                })
            }
        }
    }
    signal updated()
}
