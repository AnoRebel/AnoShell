import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland

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
        outerGaps: true, cursorZoom: true, dpms: true, outputConfig: true, exit: true,
        keyboardLayouts: true
    })

    // Raw IPC state
    property var monitors: []          // j/monitors
    property var rawWorkspaces: []     // j/workspaces
    property var fullscreenOutputs: ({})
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
            if (job) { try { job.cb(JSON.parse(text)) } catch (e) { console.warn(`[compositor:hyprland] bad reply to ${job.cmd}: ${e}`) } }
            root._next()
        }
    }
    function _request(cmd, cb) { root._queue.push({ cmd, cb }); if (!root._current) root._next() }
    function _next() {
        if (root._current || root._queue.length === 0) return
        root._current = root._queue.shift()
        root._socket.connected = true
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
    function focusWindowById(id) { return id ? root._lua(`hl.dsp.focus({ window = "address:${id}" })`) : false }
    function closeWindowById(id) { return id ? root._lua(`hl.dsp.window.close({ window = "address:${id}" })`) : false }

    // True fullscreen (mode 2) on a monitor's visible workspace. `hasfullscreen`
    // is also set by maximize, so clients are only fetched when it is set.
    function _refreshFullscreen() {
        const visible = {}
        for (const m of root.monitors) visible[m.activeWorkspace?.id] = m.name
        const candidates = root.rawWorkspaces.filter(ws => ws.hasfullscreen && visible[ws.id])
        if (candidates.length === 0) { root.fullscreenOutputs = {}; root.revision++; return }
        root._request("j/clients", clients => {
            const out = {}
            for (const c of clients)
                if ((c.fullscreen ?? 0) >= 2 && visible[c.workspace?.id]) out[visible[c.workspace.id]] = true
            root.fullscreenOutputs = out
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
    property var _refreshTimer: Timer {
        interval: 50 // coalesce bursts of events into one round of requests
        onTriggered: root.refresh()
    }
    property var _events: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root._refreshEvents.includes(event.name)
                || (root.windowLeases > 0 && root._windowEvents.includes(event.name))) root._refreshTimer.restart()
            else if (event.name === "activelayout")
                root.keyboardLayout = event.data.substring(event.data.indexOf(",") + 1)
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
    function focusWorkspace(number) { return root._lua(`hl.dsp.focus({ workspace = ${Math.round(number)} })`) }
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
