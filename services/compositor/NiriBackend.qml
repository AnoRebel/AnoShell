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
        keyboardLayouts: true
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
                key: String(w.id), id: w.id, title: w.title ?? "", appId: w.app_id ?? "",
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
