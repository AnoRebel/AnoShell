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
        outerGaps: false, cursorZoom: false, dpms: true, outputConfig: true, exit: true,
        keyboardLayouts: true
    })

    readonly property string focusedOutput: NiriService.currentOutput ?? ""
    readonly property var _focusedWs: (NiriService.allWorkspaces ?? []).find(ws => ws.is_focused) ?? null
    readonly property int activeWorkspaceNumber: root._focusedWs?.idx ?? 0
    readonly property string activeWorkspaceName: root._focusedWs?.name ?? ""

    property int revision: 0

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

    // Fullscreen toggles change no niri IPC state, so watch each toplevel.
    property var _fullscreenWatch: Instantiator {
        model: ToplevelManager.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onFullscreenChanged() { root.revision++ }
        }
    }
    property var _niriChanges: Connections {
        target: NiriService
        function onWindowsChanged() { root.revision++ }
        function onAllWorkspacesChanged() { root.revision++ }
    }

    readonly property string keyboardLayout: NiriService.getCurrentKeyboardLayoutName()
    readonly property var keyboardLayouts: NiriService.keyboardLayoutNames ?? []

    function focusWorkspace(number) { NiriService.switchToWorkspace(Math.round(number)); return true }
    function focusWorkspaceRelative(delta) {
        if (delta < 0) NiriService.focusWorkspaceUp(); else NiriService.focusWorkspaceDown()
        return true
    }
    function exit() { NiriService.quit(); return true }
    function powerOffMonitors() { NiriService.powerOffMonitors(); return true }
    function powerOnMonitors() { NiriService.powerOnMonitors(); return true }
    // Gaps, layer blur rules and cursor zoom are niri config, not runtime IPC.
    function setOuterGaps(px) { return false }
    function setLayerBlur(namespaceRegex, enabled, ignoreAlpha) { return false }
    function setCursorZoom(factor) { return false }
    function switchKeyboardLayout(delta) {
        if (delta < 0) NiriService.switchLayoutPrevious(); else NiriService.switchLayout()
        return true
    }
}
