pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * GameMode state and the performance mode it drives.
 *
 * gamemoded is watched over D-Bus (`gdbus monitor`: GameRegistered /
 * ClientCount changes), never polled, and never started by us: its client
 * count is only read once the name already has an owner (a call to an
 * unowned name would D-Bus-activate it).
 *
 *   active       — at least one game holds gamemode
 *   clientCount  — gamemoded's ClientCount
 *   performance  — performance mode is on: while a game holds gamemode
 *                  (performance.onGameMode), optionally while any window is
 *                  fullscreen (performance.onFullscreen), or by hand
 *                  (IPC `performance toggle`, the quick toggle)
 *   stopAnimations / stopBlur / stopVisualizers / holdPopups — what it
 *                  stops, each switchable (performance.*)
 *
 * gameMode.enable only shows the bar indicator.
 */
Singleton {
    id: root

    readonly property bool serviceEnabled: Config.options?.gameMode?.enable ?? false
    readonly property var perf: Config.options?.performance ?? ({})

    property bool active: false
    property int clientCount: 0

    // ─── Performance mode ─────────────────────────────────────────────────
    property bool manual: false
    readonly property bool _anyFullscreen: {
        void CompositorService.fullscreenRevision
        return Object.keys(CompositorService.fullscreenScreens ?? {}).some(k => !!CompositorService.fullscreenScreens[k])
    }
    readonly property bool performance: root.manual
        || ((root.perf.onGameMode ?? true) && root.active)
        || ((root.perf.onFullscreen ?? false) && root._anyFullscreen)
    readonly property string performanceReason: root.manual ? "turned on by hand"
        : ((root.perf.onGameMode ?? true) && root.active) ? "a game holds GameMode"
        : root.performance ? "a window is fullscreen" : ""
    readonly property bool stopAnimations: root.performance && (root.perf.stopAnimations ?? true)
    readonly property bool stopBlur: root.performance && (root.perf.stopBlur ?? true)
    readonly property bool stopVisualizers: root.performance && (root.perf.stopVisualizers ?? true)
    readonly property bool holdPopups: root.performance && (root.perf.holdPopups ?? true)

    function toggle() { root.manual = !root.manual }

    // ─── gamemoded watch ──────────────────────────────────────────────────
    property bool _installed: false
    readonly property bool _wanted: Config.ready && root._installed
        && (root.serviceEnabled || (root.perf.onGameMode ?? true))

    Process {
        id: probe
        running: Config.ready
        command: ["sh", "-c", "command -v gamemoded"]
        onExited: code => root._installed = code === 0
    }

    function _onLine(line) {
        const m = line.match(/'ClientCount': <(\d+)>/)
        if (m) { root._setCount(parseInt(m[1], 10)); return }
        if (line.includes("is owned by")) { countProc.running = true; return }
        // "does not have an owner", or the owner went away
        if (line.includes("owner")) root._setCount(0)
    }
    function _setCount(n) {
        root.clientCount = n
        root.active = n > 0
    }

    Process {
        id: monitor
        running: root._wanted
        command: ["setpriv", "--pdeathsig", "TERM", "--",
            "gdbus", "monitor", "--session", "--dest", "com.feralinteractive.GameMode"]
        stdout: SplitParser { onRead: line => root._onLine(line) }
        onRunningChanged: {
            if (running) return
            root._setCount(0)
            if (root._wanted) restart.start()
        }
    }
    Timer { id: restart; interval: 5000; onTriggered: if (root._wanted) monitor.running = true }
    // The restart above replaces the binding, so follow _wanted by hand too.
    on_WantedChanged: { restart.stop(); monitor.running = root._wanted }

    Process {
        id: countProc
        command: ["gdbus", "call", "--session", "--dest", "com.feralinteractive.GameMode",
            "--object-path", "/com/feralinteractive/GameMode",
            "--method", "org.freedesktop.DBus.Properties.Get", "com.feralinteractive.GameMode", "ClientCount"]
        stdout: StdioCollector {
            // "(<1>,)"
            onStreamFinished: {
                const m = (this.text || "").match(/<(\d+)>/)
                if (m) root._setCount(parseInt(m[1], 10))
            }
        }
    }

    IpcHandler {
        target: "performance"
        function toggle(): void { root.toggle() }
        function on(): void { root.manual = true }
        function off(): void { root.manual = false }
        function status(): string {
            return JSON.stringify({ performance: root.performance, reason: root.performanceReason,
                gameMode: root.active, clients: root.clientCount, manual: root.manual })
        }
    }
}
