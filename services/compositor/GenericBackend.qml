import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.WindowManager

/**
 * Generic Wayland backend (see BackendContract.md) for compositors without a
 * dedicated backend. Windows come from the foreign-toplevel protocol
 * (ToplevelManager), workspaces from ext-workspace-v1 (Quickshell.WindowManager).
 * ext-workspace does not say which workspaces hold windows, so only the
 * active ones count as occupied. Session control is unavailable.
 */
QtObject {
    id: root

    readonly property string name: "generic"
    readonly property bool experimental: true
    readonly property var supports: ({
        workspaces: true, perOutputWorkspaces: true, windowCapture: false, blurProtocol: false, layerBlurRules: false,
        outerGaps: false, cursorZoom: false, screenShader: false, dpms: false, outputConfig: false, exit: false,
        keyboardLayouts: false
    })

    readonly property string focusedOutput: Quickshell.screens[0]?.name ?? ""
    readonly property var _focusedWs: root.workspaces.find(w => w.output === root.focusedOutput && w.active) ?? null
    readonly property int activeWorkspaceNumber: root._focusedWs?.number ?? 0
    readonly property string activeWorkspaceName: root._focusedWs?.name ?? ""
    property int revision: 0
    property int windowLeases: 0
    readonly property var windows: {
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
        const out = []
        for (const screen of Quickshell.screens) {
            const sets = Array.from(WindowManager.screenProjection(screen)?.windowsets ?? []).filter(ws => ws.shouldDisplay !== false)
            // Coordinates are compositor-defined (Hyprland uses the workspace id),
            // so prefer a numeric name, then the first coordinate, then the order.
            sets.forEach((ws, i) => out.push({ set: ws, output: screen.name,
                number: parseInt(ws.name) || ws.coordinates?.[0] || i + 1 }))
        }
        return out.sort((x, y) => x.number - y.number)
    }
    readonly property var workspaces: root._sets.map(e => ({
        id: `${e.output}:${e.number}`, number: e.number, name: e.set.name ?? String(e.number),
        output: e.output, focused: !!e.set.active && e.output === root.focusedOutput,
        active: !!e.set.active, occupied: !!e.set.active, urgent: !!e.set.urgent
    }))
    property var _wsChanges: Connections {
        target: WindowManager
        function onWindowsetsChanged() { root.revision++ }
    }

    readonly property var fullscreenOutputs: {
        void root.revision
        const out = {}
        for (const t of Array.from(ToplevelManager.toplevels?.values ?? []))
            if (t?.fullscreen) for (const s of (t.screens ?? [])) out[s.name] = true
        return out
    }
    readonly property var coveredOutputs: {
        void root.revision
        const out = {}
        for (const t of Array.from(ToplevelManager.toplevels?.values ?? []))
            if (t?.fullscreen || t?.maximized) for (const s of (t.screens ?? [])) out[s.name] = true
        return out
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

    readonly property string keyboardLayout: ""
    readonly property var keyboardLayouts: []

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
