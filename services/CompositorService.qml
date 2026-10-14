pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import "compositor"

// CompositorService — the one compositor API the UI uses (see
// compositor/BackendContract.md). It picks a backend at startup
// (compositor.backend, else the session environment) and forwards to it.
// Hyprland/niri specifics live only in services/compositor/ and NiriService.
Singleton {
    id: root

    // Backend selection ─────────────────────────────────────────────────────
    readonly property string hyprlandSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
    readonly property string niriSocket: Quickshell.env("NIRI_SOCKET")

    property QtObject backend: null
    readonly property string backendName: backend?.name ?? "generic"
    readonly property bool experimental: backend?.experimental ?? true
    readonly property var supports: backend?.supports ?? ({})

    // Legacy flags (pre-contract consumers; prefer backendName/supports).
    readonly property bool isHyprland: backendName === "hyprland"
    readonly property bool isNiri: backendName === "niri"
    readonly property string compositor: backendName

    // State (forwarded) ─────────────────────────────────────────────────────
    readonly property int activeWorkspaceIndex: backend?.activeWorkspaceNumber ?? 0
    readonly property string activeWorkspaceName: backend?.activeWorkspaceName ?? ""
    readonly property string focusedMonitorName: backend?.focusedOutput ?? ""
    readonly property var workspaces: backend?.workspaces ?? []
    // Workspaces to show for one output: niri numbers them per output,
    // Hyprland globally (every output shows the same numbers).
    function workspacesFor(outputName) {
        return root.supports.perOutputWorkspaces ? root.workspaces.filter(w => w.output === outputName) : root.workspaces
    }
    // The workspace number visible on an output (falls back to the focused one).
    function activeWorkspaceOn(outputName) {
        const ws = root.workspacesFor(outputName).find(w => w.active && (!outputName || w.output === outputName))
        return ws?.number ?? root.activeWorkspaceIndex
    }
    readonly property string keyboardLayout: backend?.keyboardLayout ?? ""
    readonly property var keyboardLayouts: backend?.keyboardLayouts ?? []

    // Outputs currently showing a fullscreen window (bar/frame hide there).
    readonly property var fullscreenScreens: backend?.fullscreenOutputs ?? ({})
    readonly property int fullscreenRevision: backend?.revision ?? 0
    function hasFullscreenOnScreen(screenName): bool {
        return !!root.fullscreenScreens[screenName]
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Windows (leased: backends only track them while someone needs them)
    // ═══════════════════════════════════════════════════════════════════════
    // Each window: { key, id, title, appId, workspace, output, x, y, width,
    // height, focused, floating, fullscreen, toplevel } — toplevel is the
    // foreign-toplevel handle when matched (used for focus/close/screencopy).
    readonly property var windows: backend?.windows ?? []
    property var _windowLeases: ({})
    function acquireWindows(name: string): void {
        if (root._windowLeases[name]) return
        root._windowLeases[name] = true
        if (root.backend) root.backend.windowLeases = Object.keys(root._windowLeases).length
    }
    function releaseWindows(name: string): void {
        if (!root._windowLeases[name]) return
        delete root._windowLeases[name]
        if (root.backend) root.backend.windowLeases = Object.keys(root._windowLeases).length
    }
    // Windows on the workspace currently visible on an output.
    function windowsOnOutput(outputName) {
        const ws = root.activeWorkspaceOn(outputName)
        return root.windows.filter(w => w.workspace === ws && (!root.supports.perOutputWorkspaces || w.output === outputName))
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Backend selection
    // ═══════════════════════════════════════════════════════════════════════
    Component { id: hyprlandBackend; HyprlandBackend {} }
    Component { id: niriBackend; NiriBackend {} }
    Component { id: genericBackend; GenericBackend {} }

    function _pickBackend(): string {
        const forced = (Config.options?.compositor?.backend ?? "auto").trim()
        if (forced && forced !== "auto") return forced
        if (root.hyprlandSignature) return "hyprland"
        if (root.niriSocket) return "niri"
        return "generic"
    }

    // Re-pick once the user config is loaded (compositor.backend may force one).
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && root._pickBackend() !== root.backendName) root.detectCompositor()
        }
    }

    function detectCompositor() {
        const name = root._pickBackend()
        const comp = { "hyprland": hyprlandBackend, "niri": niriBackend }[name] ?? genericBackend
        root.backend?.destroy()
        root.backend = comp.createObject(root, { windowLeases: Object.keys(root._windowLeases).length })
        console.info(`CompositorService: ${root.backend.name} backend${root.backend.experimental ? " (experimental)" : ""}`)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Actions (forwarded; unsupported ones return false)
    // ═══════════════════════════════════════════════════════════════════════
    function focusWorkspace(number) { return root.backend?.focusWorkspace(number) ?? false }
    function focusWorkspaceRelative(delta) { return root.backend?.focusWorkspaceRelative(delta) ?? false }
    function exit() { return root.backend?.exit() ?? false }
    function powerOffMonitors() { return root.backend?.powerOffMonitors() ?? false }
    function powerOnMonitors() { return root.backend?.powerOnMonitors() ?? false }
    // Runtime only: the outer gap (windows ↔ screen edge); connected mode sets 0.
    function setOuterGaps(px) { return root.backend?.setOuterGaps(px) ?? false }
    // Layer-rule blur fallback for compositors without ext-background-effect-v1.
    function setLayerBlur(namespaceRegex, enabled, ignoreAlpha) { return root.backend?.setLayerBlur(namespaceRegex, enabled, ignoreAlpha) ?? false }
    readonly property var outputs: backend?.outputs ?? []
    function applyOutputs(configs) { return root.backend?.applyOutputs(configs) ?? false }
    function setScreenShader(path) { return root.backend?.setScreenShader(path) ?? false }
    function setCursorZoom(factor) { return root.backend?.setCursorZoom(factor) ?? false }
    function switchKeyboardLayout(delta) { return root.backend?.switchKeyboardLayout(delta) ?? false }
    Timer { id: ipcLeaseTimer; interval: 10000; onTriggered: root.releaseWindows("ipc") }

    // Read-only snapshot for scripts, tests and `ano doctor`.
    IpcHandler {
        target: "compositor"
        function status(): string {
            return JSON.stringify({
                backend: root.backendName, experimental: root.experimental, supports: root.supports,
                focusedOutput: root.focusedMonitorName, activeWorkspace: root.activeWorkspaceIndex,
                workspaces: root.workspaces, fullscreen: Object.keys(root.fullscreenScreens),
                keyboardLayout: root.keyboardLayout
            })
        }
        // Window model snapshot. Takes a short "ipc" lease so the backend
        // starts tracking; call twice (first call primes it).
        function windows(): string {
            root.acquireWindows("ipc")
            ipcLeaseTimer.restart()
            return JSON.stringify(root.windows.map(w => ({ title: w.title.slice(0, 40), appId: w.appId,
                workspace: w.workspace, output: w.output, focused: w.focused, fullscreen: w.fullscreen,
                geometry: [w.x, w.y, w.width, w.height], toplevel: !!w.toplevel })))
        }
    }

    // Accepts a Toplevel or a window from `windows`. The foreign-toplevel
    // handle works everywhere; without one the backend uses its own id.
    function focusWindow(win) {
        const tl = win?.toplevel ?? (win?.activate ? win : null)
        if (tl) { tl.activate(); return true }
        return root.backend?.focusWindowById(win?.id) ?? false
    }
    function closeWindow(win) {
        const tl = win?.toplevel ?? (win?.close ? win : null)
        if (tl) { tl.close(); return true }
        return root.backend?.closeWindowById(win?.id) ?? false
    }
}
