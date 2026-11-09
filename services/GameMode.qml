pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions
import qs.services
import "hyprperf.js" as HyprPerf

/**
 * GameMode state and the performance mode it drives.
 *
 * gamemoded is watched over D-Bus (dbus-monitor match rules on its signals
 * and its name), never polled, and never started by us: the client count is
 * read only while the name has an owner.
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
 *   hyprAnimations / hyprBlur / hyprShadows / hyprGaps / hyprRounding /
 *   hyprTearing — Hyprland options it turns while it lasts (hyprperf.js):
 *                  each is read first, only those not already at the
 *                  performance value are changed, and exactly those are put
 *                  back after, from a snapshot file that outlives a restart.
 *                  Nothing on niri or other compositors.
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

    // ─── Hyprland levers ──────────────────────────────────────────────────
    // {option: value while on} for the switched-on levers; {} when off.
    readonly property bool _hyprOk: Config.ready && CompositorService.isHyprland
    readonly property var _hyprWant: root._hyprOk && root.performance ? HyprPerf.wanted(root.perf) : ({})
    readonly property string _hyprWantKey: JSON.stringify(root._hyprWant)
    on_HyprWantKeyChanged: root._hyprSync()
    // {option: original value} of what we changed, kept in hyprSnapshot.
    property var _hyprSnap: ({})
    property bool _hyprLoaded: false
    property bool _hyprDirty: false

    function _hyprEval(values) {
        const call = HyprPerf.configCall(values)
        if (call) Quickshell.execDetached(["hyprctl", "eval", call])
    }
    function _hyprSave(snap) {
        root._hyprSnap = snap
        hyprSnapshot.setText(JSON.stringify(snap))
    }
    // Put back what's no longer wanted, then read what is but isn't held yet.
    function _hyprSync() {
        if (!root._hyprLoaded || !root._hyprOk) return
        if (hyprRead.running) { root._hyprDirty = true; return }
        const r = HyprPerf.reconcile(root._hyprSnap, root._hyprWant)
        root._hyprEval(r.restore)
        if (Object.keys(r.restore).length > 0) root._hyprSave(r.snapshot)
        if (r.toRead.length === 0) return
        // Fixed script; the option names are positional arguments.
        hyprRead.command = ["sh", "-c", "for o; do echo \"@$o\"; hyprctl getoption \"$o\"; done", "sh"].concat(r.toRead)
        hyprRead.running = true
    }

    Process {
        id: hyprRead
        stdout: StdioCollector {
            onStreamFinished: {
                const t = HyprPerf.take(root._hyprSnap, root._hyprWant, HyprPerf.parse(this.text))
                if (Object.keys(t.apply).length > 0) {
                    root._hyprSave(t.snapshot)  // saved before the change, so a crash can't lose it
                    root._hyprEval(t.apply)
                }
                if (root._hyprDirty) { root._hyprDirty = false; Qt.callLater(root._hyprSync) }
            }
        }
    }
    // A shell restarted while they were changed restores from here once it
    // knows performance mode is off (or keeps holding them while it's on).
    FileView {
        id: hyprSnapshot
        path: FileUtils.trimFileProtocol(`${Directories.state}/anoshell/performance-hyprland.json`)
        printErrors: false
        onLoaded: {
            try { root._hyprSnap = JSON.parse(hyprSnapshot.text()) || {} } catch (e) { root._hyprSnap = {} }
            root._hyprLoaded = true
            root._hyprSync()
        }
        onLoadFailed: { root._hyprLoaded = true; root._hyprSync() }
    }
    on_HyprOkChanged: root._hyprSync()

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

    // Any GameMode signal, or the name appearing/going: read the count again.
    function _onLine(line) {
        if (line.startsWith("signal ")) countProc.running = true
    }
    function _setCount(n) {
        root.clientCount = n
        root.active = n > 0
    }

    Process {
        id: monitor
        running: root._wanted
        command: ["setpriv", "--pdeathsig", "TERM", "--",
            // Match rules, not --dest: `gdbus monitor --dest` D-Bus-activates
            // gamemoded, starting the daemon just by watching for it.
            "dbus-monitor", "--session",
            "type='signal',sender='com.feralinteractive.GameMode'",
            "type='signal',interface='org.freedesktop.DBus',member='NameOwnerChanged',arg0='com.feralinteractive.GameMode'"]
        stdout: SplitParser { onRead: line => root._onLine(line) }
        onRunningChanged: {
            if (running) { countProc.running = true; return }
            root._setCount(0)
            if (root._wanted) restart.start()
        }
    }
    Timer { id: restart; interval: 5000; onTriggered: if (root._wanted) monitor.running = true }
    // The restart above replaces the binding, so follow _wanted by hand too.
    on_WantedChanged: { restart.stop(); monitor.running = root._wanted }

    Process {
        id: countProc
        // Only once the name has an owner: any call to it, even busctl's
        // --auto-start=no get-property, D-Bus-activates gamemoded. Fixed script.
        command: ["sh", "-c", "busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus NameHasOwner s com.feralinteractive.GameMode | grep -q 'b true' && busctl --user get-property com.feralinteractive.GameMode /com/feralinteractive/GameMode com.feralinteractive.GameMode ClientCount"]
        stdout: StdioCollector {
            // "i 1"; nothing when gamemoded isn't running
            onStreamFinished: {
                const m = (this.text || "").match(/^i (\d+)/)
                root._setCount(m ? parseInt(m[1], 10) : 0)
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
