import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.WindowManager
import "GenericModel.js" as GenericModel

/**
 * Generic Wayland backend (see BackendContract.md) for compositors without a
 * dedicated backend. Windows come from the foreign-toplevel protocol
 * (ToplevelManager), workspaces from ext-workspace-v1 (Quickshell.WindowManager).
 * ext-workspace does not say which workspaces hold windows, so only the
 * active ones count as occupied. Session control is unavailable.
 */
QtObject {
    id: root

    // Overridable by the backends built on this one (sway, mango, labwc).
    property string name: "generic"
    property bool experimental: true
    property var supports: ({
        workspaces: true, perOutputWorkspaces: true, windowCapture: false, blurProtocol: false, layerBlurRules: false,
        outerGaps: false, cursorZoom: false, screenShader: false, dpms: false, outputConfig: false, exit: false,
        keyboardLayouts: false
    })

    property string focusedOutput: Quickshell.screens[0]?.name ?? ""
    readonly property var _focusedWs: root.workspaces.find(w => w.output === root.focusedOutput && w.active) ?? null
    readonly property int activeWorkspaceNumber: root._focusedWs?.number ?? 0
    readonly property string activeWorkspaceName: root._focusedWs?.name ?? ""
    property int revision: 0
    property int windowLeases: 0
    property var windows: {
        void root.revision
        return Array.from(ToplevelManager.toplevels?.values ?? []).map((t, i) => ({
            key: `${i}:${t.appId}`, id: i, title: t.title ?? "", appId: t.appId ?? "",
            workspace: 0, output: t.screens?.[0]?.name ?? "", x: 0, y: 0, width: 0, height: 0,
            focused: !!t.activated, floating: false, fullscreen: !!t.fullscreen, toplevel: t
        }))
    }
    readonly property var outputs: []
    function applyOutputs(configs) { return false }

    function focusWindowById(id) { return false }
    function closeWindowById(id) { return false }
    // One entry per (screen, windowset); `set` keeps the handle for activate().
    readonly property var _sets: {
        void root.revision
        return GenericModel.sets(Quickshell.screens.map(screen => ({ name: screen.name,
            windowsets: Array.from(WindowManager.screenProjection(screen)?.windowsets ?? []) })))
    }
    property var workspaces: GenericModel.workspaces(root._sets, root.focusedOutput, e => root.occupiedOf(e))
    // ext-workspace doesn't say which workspaces hold windows: only the
    // shown ones count, unless a backend knows better.
    function occupiedOf(e) { return !!e.set.active }
    // No change signal on WindowManager itself: the bindings above follow each
    // projection's windowsetsChanged and each windowset's own properties.

    property var fullscreenOutputs: {
        void root.revision
        return GenericModel.outputsWhere(Array.from(ToplevelManager.toplevels?.values ?? []), t => t.fullscreen)
    }
    property var coveredOutputs: {
        void root.revision
        return GenericModel.outputsWhere(Array.from(ToplevelManager.toplevels?.values ?? []), t => t.fullscreen || t.maximized)
    }
    property var _fullscreenWatch: Instantiator {
        model: ToplevelManager.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onFullscreenChanged() { root.revision++ }
            function onMaximizedChanged() { root.revision++ }
        }
    }

    property string keyboardLayout: ""
    property var keyboardLayouts: []

    function _unsupported(what) { console.warn(`[compositor:generic] ${what} unsupported`); return false }
    function focusWorkspace(number, outputName) {
        const out = outputName || root.focusedOutput
        const e = root._sets.find(s => s.output === out && s.number === Math.round(number))
        if (!e) return false
        e.set.activate(); return true
    }
    function focusWorkspaceRelative(delta) {
        return root.focusWorkspace(Math.max(1, root.activeWorkspaceNumber + (delta < 0 ? -1 : 1)))
    }
    function exit() { return root._unsupported("exit") }
    function powerOffMonitors() { return root._unsupported("dpms") }
    function powerOnMonitors() { return root._unsupported("dpms") }
    function setOuterGaps(px) { return false }
    function setLayerBlur(namespaceRegex, enabled, ignoreAlpha) { return false }
    function setScreenShader(path) { return false }
    function setCursorZoom(factor) { return false }
    function switchKeyboardLayout(delta) { return root._unsupported("switchKeyboardLayout") }
}
