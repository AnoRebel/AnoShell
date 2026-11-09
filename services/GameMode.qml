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
 *                  fullscreen (performance.onFullscreen) or a listed app is
 *                  open (performance.apps), or by hand (IPC `performance
 *                  toggle`, the quick toggle; kept in performance.manual)
 *   stopAnimations / stopBlur / stopVisualizers / holdPopups / stopShadows /
 *   hidePieces / slowPolling — what it stops, each switchable (performance.*)
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
    // On by hand (performance.manual, kept across restarts) or while a
    // trigger holds it: a game holding GameMode, a fullscreen window, or an
    // open window whose app id matches performance.apps (globs, any case).
    // Turned off by hand while a trigger holds it, it stays off until every
    // trigger has gone (Bioma's rule: a game still running is no reason to
    // turn it back on under the hand that just refused it).
    readonly property bool manual: root.perf.manual === true
    readonly property bool _anyFullscreen: {
        void CompositorService.fullscreenRevision
        return Object.keys(CompositorService.fullscreenScreens ?? {}).some(k => !!CompositorService.fullscreenScreens[k])
    }

    // performance.apps → one case-insensitive regex ("steam_app_*", "blender").
    readonly property var _appGlobs: (root.perf.apps ?? []).map(g => String(g).trim()).filter(g => g.length > 0)
    readonly property var _appRe: root._appGlobs.length === 0 ? null
        : new RegExp("^(?:" + root._appGlobs.map(g => g.replace(/[.+^${}()|[\]\\]/g, "\\$&")
            .replace(/\*/g, ".*").replace(/\?/g, ".")).join("|") + ")$", "i")
    // Windows are leased from the compositor only while there is a list.
    readonly property bool _watchWindows: Config.ready && root._appRe !== null
    on_WatchWindowsChanged: root._watchWindows ? CompositorService.acquireWindows("performance") : CompositorService.releaseWindows("performance")
    Component.onDestruction: CompositorService.releaseWindows("performance")
    readonly property var matchedApps: {
        if (!root._appRe) return []
        const seen = []
        for (const w of CompositorService.windows ?? []) {
            const id = String(w.appId ?? "")
            if (id && root._appRe.test(id) && !seen.includes(id)) seen.push(id)
        }
        return seen
    }

    readonly property bool _byGame: (root.perf.onGameMode ?? true) && root.active
    readonly property bool _byFullscreen: (root.perf.onFullscreen ?? false) && root._anyFullscreen
    readonly property bool triggered: root._byGame || root._byFullscreen || root.matchedApps.length > 0
    // Turned off by hand while triggered; forgotten when the last trigger goes.
    property bool refused: false
    onTriggeredChanged: if (!root.triggered) root.refused = false

    readonly property bool performance: root.manual || (root.triggered && !root.refused)
    readonly property string performanceReason: !root.performance ? ""
        : root.manual ? "turned on by hand"
        : root._byGame ? "a game holds GameMode"
        : root.matchedApps.length > 0 ? `${root.matchedApps.join(", ")} ${root.matchedApps.length === 1 ? "is" : "are"} open`
        : "a window is fullscreen"
    function _lever(key) { return root.performance && (root.perf[key] ?? true) }
    readonly property bool stopAnimations: root._lever("stopAnimations")
    readonly property bool stopBlur: root._lever("stopBlur")
    readonly property bool stopVisualizers: root._lever("stopVisualizers")
    readonly property bool holdPopups: root._lever("holdPopups")
    readonly property bool stopShadows: root._lever("stopShadows")
    readonly property bool hidePieces: root._lever("hidePieces")
    readonly property bool slowPolling: root._lever("slowPolling")
    readonly property int pollInterval: Math.max(2000, root.perf.pollInterval ?? 10000)

    function on() {
        root.refused = false
        if (!root.manual && !root.triggered) Config.setNestedValue("performance.manual", true)
    }
    function off() {
        if (root.manual) Config.setNestedValue("performance.manual", false)
        if (root.triggered) root.refused = true
    }
    function toggle() { root.performance ? root.off() : root.on() }

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
        function on(): void { root.on() }
        function off(): void { root.off() }
        function status(): string {
            return JSON.stringify({ performance: root.performance, reason: root.performanceReason,
                gameMode: root.active, clients: root.clientCount, manual: root.manual,
                refused: root.refused, apps: root.matchedApps })
        }
    }
}
