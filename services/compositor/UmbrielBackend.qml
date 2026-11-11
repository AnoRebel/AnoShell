import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "UmbrielModel.js" as UmbrielModel

/**
 * Umbriel backend (experimental; written against umbriel 0.1.0, see
 * BackendContract.md and docs/compositors.md).
 *
 * One `umbriel subscribe windows,workspaces,keyboard_layout` process drives
 * everything: it prints the whole state of a kind as a JSON line at start and
 * on every change (UmbrielModel.js). Actions are `umbriel msg <action> …`
 * argv. The CLI finds the compositor through $UMBRIEL_SOCKET, which umbriel
 * exports to everything it starts. Workspaces are per output, numbered from 1.
 * No ext-background-effect: blur comes from the layer rules in
 * external/umbriel/ano.toml.
 */
GenericBackend {
    id: root

    name: "umbriel"
    supports: ({
        workspaces: true, perOutputWorkspaces: true, windowCapture: false, blurProtocol: false, layerBlurRules: false,
        outerGaps: false, cursorZoom: false, screenShader: false, dpms: true, outputConfig: false, exit: true,
        keyboardLayouts: true
    })

    property var _workspaces: []
    property var _windows: []

    focusedOutput: UmbrielModel.focusedOutput(root._workspaces) || (Quickshell.screens[0]?.name ?? "")
    workspaces: UmbrielModel.workspaces(root._workspaces)
    fullscreenOutputs: UmbrielModel.fullscreen(root._windows)
    coveredOutputs: UmbrielModel.covered(root._windows)
    windows: {
        if (root.windowLeases === 0) return []
        const toplevels = Array.from(ToplevelManager.toplevels?.values ?? [])
        return UmbrielModel.windows(root._windows, root._workspaces).map(w => Object.assign(w, {
            toplevel: toplevels.find(t => t.appId === w.appId && t.title === w.title) ?? null
        }))
    }

    // ── Events ───────────────────────────────────────────────────────────
    // umbriel resends a kind with nothing changed (e.g. windows on a redraw):
    // identical lines are dropped.
    property var _last: ({})
    property var _subscribe: Process {
        command: ["umbriel", "subscribe", "windows,workspaces,keyboard_layout"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const o = UmbrielModel.parse(line)
                if (!o || root._last[o.event] === line) return
                root._last[o.event] = line
                if (o.event === "workspaces" && Array.isArray(o.data)) root._workspaces = o.data
                else if (o.event === "windows" && Array.isArray(o.data)) root._windows = o.data
                else if (o.event === "keyboard_layout") {
                    const l = UmbrielModel.layouts(o.data)
                    root.keyboardLayout = l.current
                    root.keyboardLayouts = l.names
                    return
                } else return
                root.revision++
            }
        }
        // umbriel restarted, or not up yet: try again.
        onExited: (code, status) => { root._last = {}; root._retry.restart() }
    }
    property var _retry: Timer { interval: 2000; onTriggered: root._subscribe.running = true }

    // ── Actions ──────────────────────────────────────────────────────────
    function _msg(action, args, opts) {
        const argv = UmbrielModel.msg(action, args, opts)
        if (!argv) return false
        Quickshell.execDetached(argv)
        return true
    }
    function focusWorkspace(number, outputName) {
        const n = Math.round(number)
        if (n < 1) return false
        return outputName ? root._msg("workspace-switch", [n], { output: outputName }) : root._msg("workspace-switch", [n])
    }
    function focusWorkspaceRelative(delta) { return root._msg(delta < 0 ? "workspace-previous" : "workspace-next") }
    function exit() { return root._msg("session-quit", ["skip-confirmation"]) }
    function powerOffMonitors() { return root._msg("dpms-off") }
    function powerOnMonitors() { return root._msg("dpms-on") }
    // umbriel only steps forward: back is forward n-1 times.
    function switchKeyboardLayout(delta) {
        const steps = delta < 0 ? Math.max(1, root.keyboardLayouts.length - 1) : 1
        for (let i = 0; i < steps; i++) root._msg("keyboard-layout-next")
        return true
    }
    function focusedWindowGeometry(cb) {
        const w = UmbrielModel.windows(root._windows, root._workspaces).find(w => w.focused)
        cb(w ? { x: w.x, y: w.y, width: w.width, height: w.height } : null)
        return true
    }
    function focusWindowById(id) { return UmbrielModel.validId(id) ? root._msg("window-focus", [id]) : false }
    function closeWindowById(id) { return UmbrielModel.validId(id) ? root._msg("window-close", [id]) : false }
    // Dropdown terminal (services/DropTerminal.qml): the "anodrop" scratchpad
    // (external/umbriel/ano.toml gives ano.dropterm to it, with its size).
    // Each msg is its own process, so the move waits for the reveal.
    property var _dropMove: null
    function showWindowAt(id, r, side) {
        if (!UmbrielModel.validId(id)) return false
        root._msg("window-focus", [id]) // reveals it from the hidden scratchpad
        root._dropMove = { args: [({ top: "top", bottom: "bottom", left: "left", right: "right" })[side] ?? "center", 0, 0], window: id }
        dropMoveTimer.restart()
        return true
    }
    function hideWindow(id, side) { return UmbrielModel.validId(id) ? root._msg("scratchpad-toggle", ["anodrop"]) : false }
    property Timer _dropMoveTimer: Timer { id: dropMoveTimer; interval: 150; onTriggered: root._msg("window-move-to", root._dropMove.args, { window: root._dropMove.window }) }
}
