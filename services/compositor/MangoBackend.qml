import QtQuick
import Quickshell
import Quickshell.Io
import "MangoModel.js" as MangoModel

/**
 * Mango backend (written against mango 0.18.3; tested headless on 0.18.5, see
 * BackendContract.md).
 *
 * Mango's IPC is a Unix socket at $MANGO_INSTANCE_SIGNATURE taking one text
 * line per connection: `get …` and `dispatch …` get one JSON line back and the
 * connection closes; `watch …` keeps it open and sends the whole state as a
 * JSON line on every change. Two watches (all-monitors: tags, the selected
 * monitor, the keyboard layout; all-clients: fullscreen, maximised, windows)
 * drive everything; actions are dispatches (docs/bindings/keys.md). Tags are
 * per monitor, several can be shown at once.
 */
GenericBackend {
    id: root
    experimental: false // tested end to end (docs/compositors.md)

    name: "mango"
    supports: ({
        workspaces: true, perOutputWorkspaces: true, windowCapture: false, blurProtocol: false, layerBlurRules: false,
        outerGaps: false, cursorZoom: false, screenShader: false, dpms: true, outputConfig: false, exit: true,
        keyboardLayouts: true
    })

    readonly property string _socketPath: Quickshell.env("MANGO_INSTANCE_SIGNATURE") ?? ""
    property var _monitors: []
    property var _clients: []

    focusedOutput: MangoModel.focusedOutput(root._monitors) || (Quickshell.screens[0]?.name ?? "")
    workspaces: MangoModel.workspaces(root._monitors)
    fullscreenOutputs: MangoModel.fullscreen(root._clients)
    coveredOutputs: MangoModel.covered(root._clients)
    windows: root.windowLeases > 0 ? MangoModel.windows(root._clients, root._monitors) : []
    keyboardLayout: MangoModel.keyboardLayout(root._monitors)

    // ── Watches ──────────────────────────────────────────────────────────
    component Watch: Socket {
        id: watch
        required property string topic
        // The raw line: an object passed through a `var` parameter arrives
        // converted (its arrays fail Array.isArray), so each handler parses.
        signal received(string line)
        path: root._socketPath
        connected: root._socketPath.length > 0
        parser: SplitParser {
            onRead: line => watch.received(line)
        }
        onConnectedChanged: {
            if (connected) { write(`watch ${topic}\n`); flush() }
            else retry.restart()
        }
        // A connect that fails outright never changes `connected`.
        onError: retry.restart()
        // A watch that drops (mango restarted, the socket went away) comes back.
        property var retry: Timer { interval: 2000; onTriggered: if (root._socketPath && !watch.connected) { watch.connected = false; watch.connected = true } }
    }
    property var _monitorWatch: Watch {
        topic: "all-monitors"
        onReceived: line => { const o = MangoModel.parse(line); if (Array.isArray(o?.monitors)) { root._monitors = o.monitors; root.revision++ } }
    }
    property var _clientWatch: Watch {
        topic: "all-clients"
        onReceived: line => { const o = MangoModel.parse(line); if (Array.isArray(o?.clients)) { root._clients = o.clients; root.revision++ } }
    }

    // ── Dispatch: one command per connection, queued ─────────────────────
    property var _queue: []
    property string _current: ""
    property var _socket: Socket {
        path: root._socketPath
        parser: SplitParser {
            onRead: line => {
                const o = MangoModel.parse(line)
                if (o?.error) console.warn(`[compositor:mango] ${root._current.trim()}: ${o.error}`)
            }
        }
        onConnectedChanged: {
            if (connected) { write(root._current); flush(); return }
            root._current = ""
            root._watchdog.stop()
            root._next()
        }
    }
    function _next() {
        if (root._current || root._queue.length === 0) return
        root._current = root._queue.shift()
        root._watchdog.restart()
        root._socket.connected = true
    }
    property var _watchdog: Timer {
        interval: 2000
        onTriggered: { if (!root._current) return; root._current = ""; root._socket.connected = false; root._next() }
    }
    function _dispatch(func, args, clientId) {
        const line = MangoModel.dispatchLine(func, args, clientId)
        if (!line || !root._socketPath) return false
        root._queue.push(line)
        root._next()
        return true
    }

    // ── Actions ──────────────────────────────────────────────────────────
    function focusWorkspace(number, outputName) {
        const n = Math.round(number)
        if (n < 1) return false
        return outputName && outputName !== root.focusedOutput
            ? root._dispatch("viewcrossmon", [n, outputName]) : root._dispatch("view", [n])
    }
    function focusWorkspaceRelative(delta) { return root._dispatch(delta < 0 ? "viewtoleft" : "viewtoright", []) }
    function exit() { return root._dispatch("quit", []) }
    function _eachMonitor(func) {
        let ok = false
        for (const m of root._monitors) ok = root._dispatch(func, [m.name]) || ok
        return ok
    }
    function powerOffMonitors() { return root._eachMonitor("sleep_monitor") }
    function powerOnMonitors() { return root._eachMonitor("wakeup_monitor") }
    // ponytail: mango only cycles forward (switch_keyboard_layout takes an
    // index, but its IPC doesn't list the layouts); both directions go next.
    function switchKeyboardLayout(delta) { return root._dispatch("switch_keyboard_layout", []) }
    function focusedWindowGeometry(cb) {
        const w = MangoModel.windows(root._clients, root._monitors).find(w => w.focused)
        cb(w ? { x: w.x, y: w.y, width: w.width, height: w.height } : null)
        return true
    }
    function focusWindowById(id) { return root._dispatch("focusid", [], id) }
    function closeWindowById(id) { return root._dispatch("killclient", [], id) }
    // Dropdown terminal (services/DropTerminal.qml): minimized while hidden.
    // Shown: restored, resized by the difference to r, centred, then pushed
    // to the edge (smartmovewin steps past other windows and the centre, so
    // three times; at the edge it stays). Floating comes from the window rule
    // in external/mango/ano.conf. The queue sends these in order.
    function _dropClient(id, appId) { return root._clients.find(c => c.id === id) ?? root._clients.find(c => appId && c.appid === appId) ?? null }
    function showWindowAt(id, r, side, appId) {
        const c = root._dropClient(id, appId)
        if (!c || !r) return false
        const dw = Math.round(r.width - (c.width || 0)), dh = Math.round(r.height - (c.height || 0))
        const sign = v => (v < 0 ? String(v) : `+${v}`)
        root._dispatch("restore_minimized", [], c.id)
        if (dw !== 0 || dh !== 0) root._dispatch("resizewin", [sign(dw), sign(dh)], c.id)
        root._dispatch("centerwin", [], c.id)
        const dir = ({ top: "up", bottom: "down", left: "left", right: "right" })[side]
        if (dir) for (let i = 0; i < 3; i++) root._dispatch("smartmovewin", [dir], c.id)
        return root._dispatch("focusid", [], c.id)
    }
    function hideWindow(id, side, appId) {
        const c = root._dropClient(id, appId)
        return c ? root._dispatch("minimized", [], c.id) : false
    }
}
