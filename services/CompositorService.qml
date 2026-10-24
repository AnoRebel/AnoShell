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
    // Experimental backends (BackendContract.md).
    readonly property string swaySocket: Quickshell.env("SWAYSOCK")
    readonly property string mangoSocket: Quickshell.env("MANGO_INSTANCE_SIGNATURE")
    readonly property string labwcPid: Quickshell.env("LABWC_PID")

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
    // Outputs whose wallpaper is hidden (a maximised or fullscreen window).
    readonly property var coveredScreens: backend?.coveredOutputs ?? ({})
    function isCovered(screenName) { void root.fullscreenRevision; return !!root.coveredScreens[screenName] }
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
    // Counted per name: several instances (e.g. one per screen) may share a name.
    property var _windowLeases: ({})
    function _leaseTotal() { return Object.values(root._windowLeases).reduce((a, b) => a + b, 0) }
    function acquireWindows(name: string): void {
        root._windowLeases[name] = (root._windowLeases[name] ?? 0) + 1
        if (root.backend) root.backend.windowLeases = root._leaseTotal()
    }
    function releaseWindows(name: string): void {
        if (!root._windowLeases[name]) return
        if (--root._windowLeases[name] <= 0) delete root._windowLeases[name]
        if (root.backend) root.backend.windowLeases = root._leaseTotal()
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
    Component { id: swayBackend; SwayBackend {} }
    Component { id: mangoBackend; MangoBackend {} }
    Component { id: labwcBackend; LabwcBackend {} }
    Component { id: genericBackend; GenericBackend {} }

    function _pickBackend(): string {
        const forced = (Config.options?.compositor?.backend ?? "auto").trim()
        if (forced && forced !== "auto") return forced
        if (root.hyprlandSignature) return "hyprland"
        if (root.niriSocket) return "niri"
        if (root.swaySocket) return "sway"
        if (root.mangoSocket) return "mango"
        if (root.labwcPid) return "labwc"
        return "generic"
    }

    // Re-pick once the user config is loaded (compositor.backend may force one).
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready && root._pickBackend() !== root.backend?.name) root.detectCompositor()
        }
    }

    Component.onCompleted: detectCompositor()

    function detectCompositor() {
        const name = root._pickBackend()
        const comp = { "hyprland": hyprlandBackend, "niri": niriBackend, "sway": swayBackend,
            "mango": mangoBackend, "labwc": labwcBackend }[name] ?? genericBackend
        root.backend?.destroy()
        root.backend = comp.createObject(root, { windowLeases: root._leaseTotal() })
        if (!root.backend) {
            console.error(`CompositorService: failed to create the ${name} backend: ${comp.errorString()}`)
            return
        }
        console.info(`CompositorService: ${root.backend.name} backend${root.backend.experimental ? " (experimental)" : ""}`)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Actions (forwarded; unsupported ones return false)
    // ═══════════════════════════════════════════════════════════════════════
    // outputName (optional): the output whose workspace number is meant — matters
    // where numbers are per output (niri); defaults to the focused output.
    function focusWorkspace(number, outputName) { return root.backend?.focusWorkspace(number, outputName) ?? false }
    function focusWorkspaceRelative(delta, outputName) {
        if (outputName && root.supports.perOutputWorkspaces) {
            const nums = root.workspacesFor(outputName).map(w => w.number).sort((a, b) => a - b)
            const i = nums.indexOf(root.activeWorkspaceOn(outputName))
            const target = nums[Math.max(0, Math.min(nums.length - 1, i + (delta < 0 ? -1 : 1)))]
            return target ? root.focusWorkspace(target, outputName) : false
        }
        return root.backend?.focusWorkspaceRelative(delta) ?? false
    }
    function exit() { return root.backend?.exit() ?? false }
    function powerOffMonitors() { return root.backend?.powerOffMonitors() ?? false }
    function powerOnMonitors() { return root.backend?.powerOnMonitors() ?? false }
    // Runtime only: the outer gap (windows ↔ screen edge); connected mode sets 0.
    function setOuterGaps(px) { return root.backend?.setOuterGaps(px) ?? false }
    // Blur behind shell surfaces. Preferred: the surface sets
    //   BackgroundEffect.blurRegion: CompositorService.supports.blurProtocol ? Region { item: body; radius: r } : null
    // (ext-background-effect-v1: blur follows the drawn shape, no halo).
    // requestBlur() covers the rest: a no-op when the protocol is there (the
    // surface's region does it), otherwise the compositor's layer-rule fallback.
    function requestBlur(namespaceRegex, enabled, ignoreAlpha) {
        if (root.supports.blurProtocol) return true
        return root.backend?.setLayerBlur(namespaceRegex, enabled, ignoreAlpha) ?? false
    }
    // Layer-rule blur, for callers that specifically need the rule.
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
            return JSON.stringify(root.windows.map(w => ({ id: String(w.id), title: w.title.slice(0, 40), appId: w.appId,
                workspace: w.workspace, output: w.output, focused: w.focused, fullscreen: w.fullscreen,
                geometry: [w.x, w.y, w.width, w.height], toplevel: !!w.toplevel })))
        }
        // Actions through the same contract the UI uses (tests, the `ano` CLI).
        function focusWorkspace(number: int): bool { return root.backend?.focusWorkspace(number, root.focusedMonitorName) ?? false }
        function focusWindow(id: string): bool {
            const w = root.windows.find(x => String(x.id) === id)
            return w ? root.focusWindow(w) : false
        }
    }

    // Accepts a Toplevel or a window from `windows`. The backend's own focus
    // comes first: Hyprland ignores foreign-toplevel activate unless
    // misc:focus_on_activate is set. The toplevel handle is the fallback.
    function focusWindow(win) {
        if (win?.id !== undefined && root.backend?.focusWindowById(win.id)) return true
        const tl = win?.toplevel ?? (win?.activate ? win : null)
        if (tl) { tl.activate(); return true }
        return false
    }
    function closeWindow(win) {
        const tl = win?.toplevel ?? (win?.close ? win : null)
        if (tl) { tl.close(); return true }
        return root.backend?.closeWindowById(win?.id) ?? false
    }
}
