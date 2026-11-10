import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.services

/**
 * Hyprland backend (see BackendContract.md).
 *
 * State is read with JSON requests on Hyprland's request socket (the same
 * `j/monitors`, `j/workspaces`, `j/clients` hyprctl sends, without spawning
 * hyprctl). Quickshell 0.3.2's Hyprland module mis-parses Hyprland 0.56
 * (workspace ids -1, no monitors), so only its raw event stream is used, to
 * know when to re-query. Actions use the Lua dispatch forms required by the
 * 0.56 Lua config (`man hyprctl`).
 */
QtObject {
    id: root

    readonly property string name: "hyprland"
    readonly property bool experimental: false
    readonly property var supports: ({
        workspaces: true, perOutputWorkspaces: false, windowCapture: true, blurProtocol: true, layerBlurRules: true,
        outerGaps: true, cursorZoom: true, screenShader: true, dpms: true, outputConfig: true, exit: true,
        keyboardLayouts: true
    })

    // Raw IPC state
    property var monitors: []          // j/monitors
    property var rawWorkspaces: []     // j/workspaces
    property var fullscreenOutputs: ({})
    // Maximised or fullscreen (the wallpaper can't be seen): video pauses.
    property var coveredOutputs: ({})
    property int revision: 0
    property int windowLeases: 0      // set by CompositorService
    property var clients: []           // j/clients, kept only while leased

    readonly property var _focusedMon: root.monitors.find(m => m.focused) ?? null
    readonly property string focusedOutput: root._focusedMon?.name ?? ""
    readonly property int activeWorkspaceNumber: root._focusedMon?.activeWorkspace?.id ?? 0
    readonly property string activeWorkspaceName: root._focusedMon?.activeWorkspace?.name ?? ""

    readonly property var workspaces: {
        const activeOn = {}
        for (const m of root.monitors) activeOn[m.activeWorkspace?.id] = true
        const focusedId = root.activeWorkspaceNumber
        return root.rawWorkspaces
            .filter(ws => ws.id > 0) // skip special workspaces
            .map(ws => ({
                id: ws.id, number: ws.id, name: ws.name ?? String(ws.id),
                output: ws.monitor ?? "",
                focused: ws.id === focusedId,
                active: !!activeOn[ws.id],
                occupied: (ws.windows ?? 0) > 0,
                urgent: false
            }))
            .sort((a, b) => a.number - b.number)
    }

    // ── Request socket: one request per connection, queued ──────────────────
    readonly property string _socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket.sock`
    property var _queue: []      // [{cmd, cb}]
    property var _current: null
    property string _buf: ""
    property var _socket: Socket {
        path: root._socketPath
        parser: SplitParser { splitMarker: ""; onRead: data => { root._buf += data } }
        onConnectedChanged: {
            if (connected) { write(root._current.cmd); flush(); return }
            // Hyprland closes the connection after replying.
            const job = root._current, text = root._buf
            root._current = null; root._buf = ""
            root._watchdog.stop()
            if (job) { try { job.cb(JSON.parse(text)) } catch (e) { console.warn(`[compositor:hyprland] bad reply to ${job.cmd}: ${e}`) } }
            root._next()
        }
    }
    // Replies are snapshots, so a request already waiting for the same command
    // just takes the newer callback (the queue can't grow while unreachable).
    // Caps/Num Lock of the main keyboard (right with keyd and other virtual
    // keyboards): cb({ capsLock, numLock }).
    // Apply config values live (`hl.config({…})` Lua; performance mode's levers).
    function evalConfig(call) { if (call) Quickshell.execDetached(["hyprctl", "eval", call]) }

    function lockKeys(cb) {
        root._request("j/devices", d => {
            const kb = (d?.keyboards ?? []).find(k => k.main)
            if (kb) cb({ capsLock: !!kb.capsLock, numLock: !!kb.numLock })
        })
        return true
    }

    function _request(cmd, cb) {
        const pending = root._queue.find(j => j.cmd === cmd)
        if (pending) pending.cb = cb
        else root._queue.push({ cmd, cb })
        if (!root._current) root._next()
    }
    function _next() {
        if (root._current || root._queue.length === 0) return
        root._current = root._queue.shift()
        root._watchdog.restart()
        root._socket.connected = true
    }
    // A request that never completes (socket missing, connect failed) is
    // dropped so the queue keeps moving.
    property var _watchdog: Timer {
        interval: 2000
        onTriggered: {
            if (!root._current) return
            console.warn(`[compositor:hyprland] ${root._current.cmd} timed out`)
            root._current = null; root._buf = ""
            root._socket.connected = false
            root._next()
        }
    }

    function refresh() {
        root._request("j/monitors", data => { root.monitors = data })
        root._request("j/workspaces", data => {
            root.rawWorkspaces = data
            root._refreshFullscreen()
        })
        if (root.windowLeases > 0) root._request("j/clients", data => { root.clients = data })
    }
    onWindowLeasesChanged: {
        if (root.windowLeases > 0) root._refreshTimer.restart()
        else root.clients = []
    }

    // Windows (only while leased). Toplevels are matched by Hyprland address.
    readonly property var windows: {
        if (root.windowLeases === 0) return []
        const monName = {}
        for (const m of root.monitors) monName[m.id] = m.name
        const byAddress = {}
        for (const t of Array.from(ToplevelManager.toplevels?.values ?? [])) {
            const a = t?.HyprlandToplevel?.address
            if (a) byAddress[`0x${a}`.replace(/^0x0x/, "0x")] = t
        }
        const focused = root.clients.reduce((best, c) => (best === null || c.focusHistoryID < best.focusHistoryID) ? c : best, null)
        return root.clients.filter(c => (c.workspace?.id ?? 0) > 0 && c.mapped !== false).map(c => ({
            key: c.address, id: c.address, title: c.title ?? "", appId: c.class ?? "",
            workspace: c.workspace?.id ?? 0, output: monName[c.monitor] ?? "",
            x: c.at?.[0] ?? 0, y: c.at?.[1] ?? 0, width: c.size?.[0] ?? 0, height: c.size?.[1] ?? 0,
            focused: c === focused, floating: !!c.floating, fullscreen: (c.fullscreen ?? 0) >= 2,
            toplevel: byAddress[c.address] ?? null
        }))
    }
    // Outputs as reported by j/monitors; applyOutputs takes
    // [{ name, width, height, rate, scale, x, y }] (x/y null = "auto").
    readonly property var outputs: root.monitors
    function applyOutputs(configs) {
        const lua = configs.map(c => `hl.monitor({ output = "${c.name}", mode = "${c.width}x${c.height}@${c.rate}", `
            + `position = "${(c.x === null || c.x === undefined) ? "auto" : `${Math.round(c.x)}x${Math.round(c.y)}`}", scale = "${c.scale}" })`)
        return lua.length > 0 ? root._eval(lua.join("; ")) : false
    }

    function focusWindowById(id) { return id ? root._lua(`hl.dsp.focus({ window = "address:${id}" })`) : false }
    function closeWindowById(id) { return id ? root._lua(`hl.dsp.window.close({ window = "address:${id}" })`) : false }

    // True fullscreen (mode 2) on a monitor's visible workspace. `hasfullscreen`
    // is also set by maximize, so clients are only fetched when it is set.
    function _refreshFullscreen() {
        const visible = {}
        for (const m of root.monitors) visible[m.activeWorkspace?.id] = m.name
        const candidates = root.rawWorkspaces.filter(ws => ws.hasfullscreen && visible[ws.id])
        if (candidates.length === 0) { root.fullscreenOutputs = {}; root.coveredOutputs = {}; root.revision++; return }
        root._request("j/clients", clients => {
            const out = {}, cov = {}
            for (const c of clients) {
                const on = visible[c.workspace?.id]
                if (!on) continue
                if ((c.fullscreen ?? 0) >= 2) out[on] = true
                if ((c.fullscreen ?? 0) >= 1) cov[on] = true   // 1 = maximised
            }
            root.fullscreenOutputs = out
            root.coveredOutputs = cov
            root.revision++
        })
    }

    readonly property var _refreshEvents: ["workspace", "workspacev2", "focusedmon", "focusedmonv2",
        "createworkspace", "createworkspacev2", "destroyworkspace", "destroyworkspacev2",
        "moveworkspace", "moveworkspacev2", "renameworkspace", "fullscreen",
        "openwindow", "closewindow", "movewindow", "movewindowv2", "monitoradded", "monitoraddedv2",
        "monitorremoved", "monitorremovedv2"]
    // Extra events that only matter while windows are leased.
    readonly property var _windowEvents: ["activewindow", "activewindowv2", "windowtitle", "windowtitlev2",
        "changefloatingmode", "pin", "minimized"]
    property var _layerSettle: Timer { interval: 300; onTriggered: root._request("j/monitors", data => { root.monitors = data }) }
    // A capture opened (true) or closed: owner "monitor", "window" or a region.
    signal screencast(bool open, string owner, string name)
    // Space other layer clients reserve on an output: [left, top, right, bottom].
    function reservedOf(outputName) { return root.monitors.find(m => m.name === outputName)?.reserved ?? null }
    // The focused window in layout coordinates ({x, y, width, height}), or null.
    function focusedWindowGeometry(cb) {
        root._request("j/activewindow", w => cb(w?.at && w?.size ? { x: w.at[0], y: w.at[1], width: w.size[0], height: w.size[1] } : null))
        return true
    }
    property var _refreshTimer: Timer {
        interval: 50 // coalesce bursts of events into one round of requests
        onTriggered: root.refresh()
    }
    // Set before anod was up (startup, anod restart, hot reload): tell it now,
    // and set it again in case the old connection's cleanup just cleared it.
    property string _screenShader: ""
    property var _anodWatch: Connections {
        target: Anod
        function onAvailableChanged() { if (Anod.available && root._screenShader) root.setScreenShader(root._screenShader) }
    }
    property var _events: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") {
                // `fullscreen>>0`: the focused window left fullscreen (or
                // maximise). Clear its monitor now: the debounced refresh
                // answered 100+ ms later, so the bar and pill came back well
                // after the window had. Entering ("1") can't be told from
                // maximise, so that waits for the refresh, sent straight away.
                const mon = Hyprland.focusedMonitor?.name ?? ""
                // Coverage (a maximised window may still be there) waits for
                // the refresh.
                if (event.data === "0" && mon && root.fullscreenOutputs[mon]) {
                    const f = Object.assign({}, root.fullscreenOutputs)
                    delete f[mon]
                    root.fullscreenOutputs = f; root.revision++
                }
                root._refreshTimer.stop()
                root.refresh()
            } else if (root._refreshEvents.includes(event.name)
                || (root.windowLeases > 0 && root._windowEvents.includes(event.name))) root._refreshTimer.restart()
            else if (event.name === "activelayout")
                root.keyboardLayout = event.data.substring(event.data.indexOf(",") + 1)
            // A layer's exclusive zone lands a commit after openlayer: re-read
            // the monitors' reserved edges a moment later.
            else if (event.name === "openlayer" || event.name === "closelayer") root._layerSettle.restart()
            // screencastv2>>STATE,OWNER,NAME (NAME, a window title, may hold commas).
            else if (event.name === "screencastv2") {
                const parts = event.data.split(",")
                root.screencast(parts[0] === "1", parts[1] ?? "", parts.slice(2).join(","))
            }
            else if (event.name === "configreloaded")
                root._refreshKeyboard()
        }
    }

    property string keyboardLayout: ""
    property var keyboardLayouts: [] // xkb layout codes of the main keyboard
    function _refreshKeyboard() {
        root._request("j/devices", d => {
            const kb = (d.keyboards ?? []).find(k => k.main) ?? (d.keyboards ?? [])[0]
            if (!kb) return
            root.keyboardLayout = kb.active_keymap ?? ""
            root.keyboardLayouts = (kb.layout ?? "").split(",").filter(x => x.length > 0)
        })
    }

    // ── Actions ──────────────────────────────────────────────────────────────
    function _lua(code) { Hyprland.dispatch(code); return true }
    function focusWorkspace(number, outputName) { // ids are global on Hyprland
        return root._lua(`hl.dsp.focus({ workspace = ${Math.round(number)} })`)
    }
    function focusWorkspaceRelative(delta) {
        return root._lua(`hl.dsp.focus({ workspace = "${delta >= 0 ? "r+" : "r-"}${Math.abs(Math.round(delta)) || 1}" })`)
    }
    function exit() { return root._lua("hl.dsp.exit()") }
    function powerOffMonitors() { return root._lua(`hl.dsp.dpms({ action = "off" })`) }
    function powerOnMonitors() { return root._lua(`hl.dsp.dpms({ action = "on" })`) }

    // Runtime config goes through `hyprctl eval` (keyword is rejected by the Lua provider).
    function _eval(lua) { Quickshell.execDetached(["hyprctl", "eval", lua]); return true }
    function setOuterGaps(px) { return root._eval(`hl.config({ general = { gaps_out = ${Math.max(0, Math.round(px))} } })`) }
    function setLayerBlur(namespaceRegex, enabled, ignoreAlpha) {
        return root._eval(`hl.layer_rule({ match = { namespace = "${namespaceRegex}" }, blur = ${enabled ? "true" : "false"}, ignore_alpha = ${ignoreAlpha ?? 0} })`)
    }
    // Full-screen GLSL shader ("" clears). damage_tracking must be off (1 = monitor) while set.
    function setScreenShader(path) {
        // anod clears it if the shell goes away without doing so (crash, kill).
        root._screenShader = path ?? ""
        Anod.call("screen.shaderSet", { path: path ?? "" })
        return root._eval(`hl.config({ decoration = { screen_shader = "${path ?? ""}" }, debug = { damage_tracking = ${path ? 1 : 2} } })`)
    }
    function setCursorZoom(factor) { return root._eval(`hl.config({ cursor = { zoom_factor = ${Number(factor)} } })`) }
    // Not a dispatcher in 0.56: `hyprctl switchxkblayout <device> next|prev` (user action only).
    function switchKeyboardLayout(delta) {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", delta < 0 ? "prev" : "next"])
        return true
    }

    Component.onCompleted: {
        root.refresh()
        root._refreshKeyboard() // later updates come from activelayout events
    }
}
