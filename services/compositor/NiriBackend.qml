import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

/**
 * niri backend (see BackendContract.md). Thin adapter over NiriService, the
 * niri IPC client (event stream + requests on $NIRI_SOCKET, no `niri msg`
 * per event). niri's IPC does not report fullscreen state, so fullscreen
 * comes from the foreign-toplevel `Toplevel.fullscreen` flag, counted only
 * when the window's workspace is the visible one on its output.
 */
QtObject {
    id: root

    readonly property string name: "niri"
    readonly property bool experimental: false
    readonly property var supports: ({
        workspaces: true, perOutputWorkspaces: true, windowCapture: false, blurProtocol: true, layerBlurRules: false,
        outerGaps: false, cursorZoom: false, screenShader: false, dpms: true, outputConfig: false, exit: true,
        keyboardLayouts: true, windowBlur: true, scrollingLayout: true, infiniteDesktop: true
    })

    readonly property string focusedOutput: NiriService.currentOutput ?? ""
    readonly property var _focusedWs: (NiriService.allWorkspaces ?? []).find(ws => ws.is_focused) ?? null
    readonly property int activeWorkspaceNumber: root._focusedWs?.idx ?? 0
    readonly property string activeWorkspaceName: root._focusedWs?.name ?? ""

    property int revision: 0
    property int windowLeases: 0      // niri streams windows anyway; kept for the contract

    readonly property var workspaces: {
        void root.revision
        const windows = NiriService.windows ?? []
        return (NiriService.allWorkspaces ?? []).map(ws => ({
            id: ws.id, number: ws.idx, name: ws.name ?? String(ws.idx),
            output: ws.output ?? "",
            focused: !!ws.is_focused, active: !!ws.is_active,
            occupied: windows.some(w => w.workspace_id === ws.id),
            urgent: !!ws.is_urgent
        }))
    }

    readonly property var fullscreenOutputs: {
        void root.revision
        const out = {}
        const wsById = {}
        for (const ws of (NiriService.allWorkspaces ?? [])) wsById[ws.id] = ws
        for (const t of Array.from(ToplevelManager.toplevels?.values ?? [])) {
            if (!t?.fullscreen) continue
            const found = NiriService.findNiriWindow(t)
            const ws = found ? wsById[found.niriWindow.workspace_id] : null
            if (ws?.is_active && ws.output) out[ws.output] = true
        }
        return out
    }

    readonly property var coveredOutputs: {
        void root.revision
        const out = {}
        const wsById = {}
        for (const ws of (NiriService.allWorkspaces ?? [])) wsById[ws.id] = ws
        for (const t of Array.from(ToplevelManager.toplevels?.values ?? [])) {
            if (!t?.fullscreen && !t?.maximized) continue
            const found = NiriService.findNiriWindow(t)
            const ws = found ? wsById[found.niriWindow.workspace_id] : null
            if (ws?.is_active && ws.output) out[ws.output] = true
        }
        return out
    }

    // Fullscreen toggles change no niri IPC state, so watch each toplevel.
    property var _fullscreenWatch: Instantiator {
        model: ToplevelManager.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onFullscreenChanged() { root.revision++ }
            function onMaximizedChanged() { root.revision++ }
        }
    }
    property var _niriChanges: Connections {
        target: NiriService
        function onWindowsChanged() { root.revision++ }
        function onAllWorkspacesChanged() { root.revision++ }
    }

    readonly property var windows: {
        void root.revision
        const wsById = {}
        for (const ws of (NiriService.allWorkspaces ?? [])) wsById[ws.id] = ws
        const toplevels = Array.from(ToplevelManager.toplevels?.values ?? [])
        return (NiriService.windows ?? []).map(w => {
            const ws = wsById[w.workspace_id]
            const pos = w.layout?.tile_pos_in_workspace_view ?? w.layout?.pos_in_scrolling_layout ?? [0, 0]
            const size = w.layout?.tile_size ?? w.layout?.window_size ?? [0, 0]
            const tl = toplevels.find(t => t.appId === w.app_id && (!w.title || t.title === w.title)) ?? null
            return {
                key: String(w.id), id: w.id, title: w.title ?? "", appId: w.app_id ?? "", pid: w.pid ?? 0,
                workspace: ws?.idx ?? 0, output: ws?.output ?? "",
                x: pos[0] ?? 0, y: pos[1] ?? 0, width: size[0] ?? 0, height: size[1] ?? 0,
                focused: !!w.is_focused, floating: !!w.is_floating, fullscreen: !!tl?.fullscreen,
                toplevel: tl
            }
        })
    }
    // Runtime output config on niri comes with the Displays page (task 10.2).
    readonly property var outputs: []
    function applyOutputs(configs) { return false }

    // ── Infinite desktop (services/InfiniteDesktop.qml) ─────────────────────
    // Floating positions are set relative to the output's working area, which
    // niri doesn't report: learnt from where a placed window lands (_off).
    // niri keeps a sliver (10–75 px) of every floating window on screen.
    signal windowOpened(var id, string workspace)
    property var _niriOpen: Connections {
        target: NiriService
        function onWindowOpened(w) { root.windowOpened(w.id, String(w.workspace_id ?? "")) }
    }
    property var _off: ({})     // output → { x, y }
    property var _asked: ({})   // window id → { x, y, output } last requested (layout coordinates)
    function _outRect(name) {
        const l = NiriService.outputs?.[name]?.logical
        return l ? { x: l.x, y: l.y, width: l.width, height: l.height } : null
    }
    function canvasState(cb) {
        const ws = root._focusedWs, view = ws ? root._outRect(ws.output) : null
        if (!view) { cb(null); return true }
        const wins = []
        for (const w of (NiriService.windows ?? [])) {
            const pos = w.layout?.tile_pos_in_workspace_view, size = w.layout?.tile_size
            if (w.workspace_id !== ws.id || !pos || !size) continue
            const r = { id: w.id, x: view.x + pos[0], y: view.y + pos[1], width: size[0], height: size[1],
                        floating: !!w.is_floating, focused: !!w.is_focused, appId: w.app_id ?? "",
                        // borders: the size actions set the window, not the tile
                        insetW: size[0] - (w.layout.window_size?.[0] ?? size[0]), insetH: size[1] - (w.layout.window_size?.[1] ?? size[1]) }
            // Where it landed against where it was sent, while fully on screen (not clamped).
            const a = root._asked[w.id]
            if (a && r.x >= view.x && r.y >= view.y && r.x + r.width <= view.x + view.width && r.y + r.height <= view.y + view.height) {
                const o = Object.assign({}, root._off)
                o[ws.output] = { x: (o[ws.output]?.x ?? 0) + r.x - a.x, y: (o[ws.output]?.y ?? 0) + r.y - a.y }
                root._off = o
                delete root._asked[w.id]
            }
            wins.push(r)
        }
        cb({ workspace: String(ws.id), output: ws.output, view, others: [], windows: wins })
        return true
    }
    function _setPos(id, x, y) {
        const w = (NiriService.windows ?? []).find(w => w.id === id)
        const out = (NiriService.allWorkspaces ?? []).find(ws => ws.id === w?.workspace_id)?.output
        const r = out ? root._outRect(out) : null
        if (!r) return false
        const off = root._off[out] ?? { x: 0, y: 0 }
        root._asked[id] = { x, y }
        return NiriService.send({ "Action": { "MoveFloatingWindow": { "id": id,
            "x": { "SetFixed": Math.round(x - r.x - off.x) }, "y": { "SetFixed": Math.round(y - r.y - off.y) } } } })
    }
    function floatWindows(rects) {
        for (const r of rects) {
            if (!(NiriService.windows ?? []).find(w => w.id === r.id)?.is_floating)
                NiriService.send({ "Action": { "MoveWindowToFloating": { "id": r.id } } })
            NiriService.send({ "Action": { "SetWindowWidth": { "id": r.id, "change": { "SetFixed": Math.round(r.width - (r.insetW ?? 0)) } } } })
            NiriService.send({ "Action": { "SetWindowHeight": { "id": r.id, "change": { "SetFixed": Math.round(r.height - (r.insetH ?? 0)) } } } })
            root._setPos(r.id, r.x, r.y)
        }
        return true
    }
    function placeWindows(list) {
        for (const p of list) root._setPos(p.id, p.x, p.y)
        return true
    }
    function tileWindows(ids) {
        for (const id of ids) NiriService.send({ "Action": { "MoveWindowToTiling": { "id": id } } })
        return true
    }

    function focusWindowById(id) { return (id === undefined || id === null) ? false : NiriService.focusWindow(id) }
    function closeWindowById(id) { return (id === undefined || id === null) ? false : NiriService.closeWindow(id) }
    // Dropdown terminal (services/DropTerminal.qml). niri has no scratchpad:
    // hidden, it waits on the empty workspace at the end of its output; shown,
    // it floats at r (niri places floats in its working area: the output
    // less exclusive zones).
    function _wsOn(output) { return (NiriService.allWorkspaces ?? []).filter(w => w.output === output) }
    function showWindowAt(id, r, side) {
        const ws = root._wsOn(root.focusedOutput).find(w => w.is_active)
        if (!Number.isInteger(id) || !r || !ws) return false
        NiriService.send({ "Action": { "MoveWindowToWorkspace": { "window_id": id, "reference": { "Id": ws.id }, "focus": true } } })
        NiriService.send({ "Action": { "MoveWindowToFloating": { "id": id } } })
        NiriService.send({ "Action": { "SetWindowWidth": { "id": id, "change": { "SetFixed": Math.round(r.width) } } } })
        NiriService.send({ "Action": { "SetWindowHeight": { "id": id, "change": { "SetFixed": Math.round(r.height) } } } })
        NiriService.send({ "Action": { "MoveFloatingWindow": { "id": id, "x": { "SetFixed": r.x - r.screen.x }, "y": { "SetFixed": r.y - r.screen.y } } } })
        return NiriService.focusWindow(id)
    }
    function hideWindow(id, side) {
        const w = (NiriService.windows ?? []).find(w => w.id === id)
        const out = (NiriService.allWorkspaces ?? []).find(ws => ws.id === w?.workspace_id)?.output ?? root.focusedOutput
        const last = root._wsOn(out).reduce((a, b) => (a === null || b.idx > a.idx) ? b : a, null)
        if (!Number.isInteger(id) || !last || last.id === w?.workspace_id) return false
        return NiriService.send({ "Action": { "MoveWindowToWorkspace": { "window_id": id, "reference": { "Id": last.id }, "focus": false } } })
    }

    readonly property string keyboardLayout: NiriService.getCurrentKeyboardLayoutName()
    readonly property var keyboardLayouts: NiriService.keyboardLayoutNames ?? []

    // niri numbers workspaces per output; with an output, target that output's
    // workspace by its unique id (Index is relative to the focused output).
    function focusWorkspace(number, outputName) {
        const ws = outputName ? (NiriService.allWorkspaces ?? []).find(w => w.output === outputName && w.idx === Math.round(number)) : null
        if (ws) return NiriService.send({ "Action": { "FocusWorkspace": { "reference": { "Id": ws.id } } } }) ?? true
        return NiriService.switchToWorkspace(Math.round(number)) ?? true
    }
    function focusWorkspaceRelative(delta) {
        return delta < 0 ? NiriService.focusWorkspaceUp() : NiriService.focusWorkspaceDown()
    }
    function exit() { return NiriService.quit() }
    function powerOffMonitors() { return NiriService.powerOffMonitors() }
    function powerOnMonitors() { return NiriService.powerOnMonitors() }
    // Gaps, layer blur rules and cursor zoom are niri config, not runtime IPC.
    function setOuterGaps(px) { return false }
    function setLayerBlur(namespaceRegex, enabled, ignoreAlpha) { return false }
    function setScreenShader(path) { return false }
    function setCursorZoom(factor) { return false }
    function switchKeyboardLayout(delta) {
        return delta < 0 ? NiriService.switchLayoutPrevious() : NiriService.switchLayout()
    }
}
