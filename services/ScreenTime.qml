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
 * screenTime.idleSeconds and nothing playing: a video you watch still
 * counts) or locked. Idle inhibitors are ignored, so a forgotten
 * "keep awake" toggle doesn't count the whole night. Credits go to anod once a minute
 * (screentime.add), which keeps them in local day files.
 */
Singleton {
    id: root
    readonly property bool enabled: Config.options?.screenTime?.enable ?? false
    readonly property bool idle: root._noInput && !MprisController.isPlaying
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
        for (const key in p) {
            const [app, title] = key.split("\u0000")
            // anod takes at most 120 s per report (time saved up while it was away goes in parts)
            for (let left = p[key]; left > 0; left -= 120)
                Anod.call("screentime.add", { app: app, title: title, seconds: Math.min(120, left) }, () => {})
        }
        root.updated()
    }
    signal updated()
}
