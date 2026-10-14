import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Generic Wayland backend (see BackendContract.md) for compositors without a
 * dedicated backend. Windows come from the foreign-toplevel protocol
 * (ToplevelManager); workspace switching and session control are not
 * available, so those calls report unsupported.
 * ponytail: no workspaces yet — Quickshell.WindowManager (ext-workspace) can
 * fill them in when an experimental backend needs it (task 2.4/12.x).
 */
QtObject {
    id: root

    readonly property string name: "generic"
    readonly property bool experimental: true
    readonly property var supports: ({
        workspaces: false, windowCapture: false, blurProtocol: false, layerBlurRules: false,
        outerGaps: false, cursorZoom: false, dpms: false, outputConfig: false, exit: false,
        keyboardLayouts: false
    })

    readonly property string focusedOutput: Quickshell.screens[0]?.name ?? ""
    readonly property int activeWorkspaceNumber: 0
    readonly property string activeWorkspaceName: ""
    property int revision: 0
    readonly property var workspaces: []

    readonly property var fullscreenOutputs: {
        void root.revision
        const out = {}
        for (const t of Array.from(ToplevelManager.toplevels?.values ?? []))
            if (t?.fullscreen) for (const s of (t.screens ?? [])) out[s.name] = true
        return out
    }
    property var _fullscreenWatch: Instantiator {
        model: ToplevelManager.toplevels
        delegate: Connections {
            required property var modelData
            target: modelData
            function onFullscreenChanged() { root.revision++ }
        }
    }

    readonly property string keyboardLayout: ""
    readonly property var keyboardLayouts: []

    function _unsupported(what) { console.warn(`[compositor:generic] ${what} unsupported`); return false }
    function focusWorkspace(number) { return root._unsupported("focusWorkspace") }
    function focusWorkspaceRelative(delta) { return root._unsupported("focusWorkspaceRelative") }
    function exit() { return root._unsupported("exit") }
    function powerOffMonitors() { return root._unsupported("dpms") }
    function powerOnMonitors() { return root._unsupported("dpms") }
    function setOuterGaps(px) { return false }
    function setLayerBlur(namespaceRegex, enabled, ignoreAlpha) { return false }
    function setCursorZoom(factor) { return false }
    function switchKeyboardLayout(delta) { return root._unsupported("switchKeyboardLayout") }
}
