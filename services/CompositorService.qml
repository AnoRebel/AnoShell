pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
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

    // Niri toplevel sorting (delegated to NiriService when available)
    property bool useNiriSorting: isNiri && NiriService

    // State (forwarded) ─────────────────────────────────────────────────────
    readonly property int activeWorkspaceIndex: backend?.activeWorkspaceNumber ?? 0
    readonly property string activeWorkspaceName: backend?.activeWorkspaceName ?? ""
    readonly property string focusedMonitorName: backend?.focusedOutput ?? ""
    readonly property var workspaces: backend?.workspaces ?? []
    readonly property string keyboardLayout: backend?.keyboardLayout ?? ""
    readonly property var keyboardLayouts: backend?.keyboardLayouts ?? []

    // Outputs currently showing a fullscreen window (bar/frame hide there).
    readonly property var fullscreenScreens: backend?.fullscreenOutputs ?? ({})
    readonly property int fullscreenRevision: backend?.revision ?? 0
    function hasFullscreenOnScreen(screenName): bool {
        return !!root.fullscreenScreens[screenName]
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Sorted toplevels (compositor-aware window list)
    // ═══════════════════════════════════════════════════════════════════════
    property var sortedToplevels: sortedToplevelsCache
    property var sortedToplevelsCache: []

    property var _sortingConsumers: ({})
    property int _sortingConsumersCount: 0
    readonly property bool sortingActive: root.isNiri || root._sortingConsumersCount > 0

    property bool _sortScheduled: false
    property bool _refreshScheduled: false
    property bool _hasRefreshedOnce: false
    property var _coordCache: ({})

    Timer {
        id: refreshTimer
        interval: 40
        repeat: false
        onTriggered: {
            try { Hyprland.refreshToplevels() } catch(e) {}
            _refreshScheduled = false
            _hasRefreshedOnce = true
            scheduleSort()
        }
    }

    Timer {
        id: sortTimer
        interval: 100
        repeat: false
        onTriggered: {
            _sortScheduled = false
            sortedToplevelsCache = computeSortedToplevels()
        }
    }

    function scheduleSort() {
        if (root.isHyprland && !root.sortingActive) return
        if (_sortScheduled) return
        _sortScheduled = true
        sortTimer.restart()
    }

    function scheduleRefresh() {
        if (!root.sortingActive) return
        if (!isHyprland) return
        if (_refreshScheduled) return
        _refreshScheduled = true
        refreshTimer.restart()
    }

    // Register/unregister sorting consumers (e.g., dock, task view)
    function setSortingConsumer(name: string, active: bool): void {
        if (!name || name.length === 0) return;
        const prev = !!root._sortingConsumers[name]
        if (prev === active) return;
        root._sortingConsumers[name] = active
        let count = 0
        for (const k in root._sortingConsumers) {
            if (root._sortingConsumers[k]) count++
        }
        root._sortingConsumersCount = count
        if (root.isHyprland && root.sortingActive) root.scheduleSort()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Connections to compositor signals
    // ═══════════════════════════════════════════════════════════════════════
    Connections {
        target: ToplevelManager.toplevels
        enabled: !root.isHyprland || root.sortingActive
        function onValuesChanged() { root.scheduleSort() }
    }
    Connections {
        target: Hyprland.toplevels
        enabled: root.isHyprland && root.sortingActive
        function onValuesChanged() {
            root._hasRefreshedOnce = false
            root.scheduleSort()
        }
    }
    Connections {
        target: Hyprland.workspaces
        enabled: root.isHyprland && root.sortingActive
        function onValuesChanged() { root.scheduleSort() }
    }
    Connections {
        target: Hyprland
        enabled: root.isHyprland && root.sortingActive
        function onFocusedWorkspaceChanged() { root.scheduleSort() }
    }
    Connections {
        target: NiriService
        enabled: root.isNiri
        function onWindowsChanged() { root.scheduleSort() }
    }

    Component.onCompleted: {
        detectCompositor()
        if (root.isNiri) scheduleSort()
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Sorting implementations
    // ═══════════════════════════════════════════════════════════════════════
    function computeSortedToplevels() {
        if (!ToplevelManager.toplevels || !ToplevelManager.toplevels.values)
            return []
        if (useNiriSorting) return NiriService.sortToplevels(ToplevelManager.toplevels.values)
        if (isHyprland) return sortHyprlandToplevelsSafe()
        return Array.from(ToplevelManager.toplevels.values)
    }

    function _get(o, path, fallback) {
        try {
            let v = o
            for (let i = 0; i < path.length; i++) {
                if (v === null || v === undefined) return fallback
                v = v[path[i]]
            }
            return (v === undefined || v === null) ? fallback : v
        } catch (e) { return fallback }
    }

    function sortHyprlandToplevelsSafe() {
        if (!Hyprland.toplevels || !Hyprland.toplevels.values) return []
        if (_refreshScheduled) return sortedToplevelsCache

        const items = Array.from(Hyprland.toplevels.values)

        let snap = []
        let missingAnyPosition = false
        let hasNewWindow = false
        for (let i = 0; i < items.length; i++) {
            const t = items[i]
            if (!t) continue

            const addr = t.address || ""
            const li = t.lastIpcObject || null

            const monName = _get(li, ["monitor"], null) ?? _get(t, ["monitor", "name"], "")
            const monX = _get(t, ["monitor", "x"], Number.MAX_SAFE_INTEGER)
            const monY = _get(t, ["monitor", "y"], Number.MAX_SAFE_INTEGER)

            const wsId = _get(li, ["workspace", "id"], null) ?? _get(t, ["workspace", "id"], Number.MAX_SAFE_INTEGER)

            const at = _get(li, ["at"], null)
            let atX = (at !== null && at !== undefined && typeof at[0] === "number") ? at[0] : NaN
            let atY = (at !== null && at !== undefined && typeof at[1] === "number") ? at[1] : NaN

            if (!(atX === atX) || !(atY === atY)) {
                const cached = _coordCache[addr]
                if (cached) { atX = cached.x; atY = cached.y }
                else { if (addr) hasNewWindow = true; missingAnyPosition = true; atX = 1e9; atY = 1e9 }
            } else if (addr) {
                _coordCache[addr] = { x: atX, y: atY }
            }

            const relX = Number.isFinite(monX) ? (atX - monX) : atX
            const relY = Number.isFinite(monY) ? (atY - monY) : atY

            snap.push({
                monKey: String(monName),
                monOrderX: Number.isFinite(monX) ? monX : Number.MAX_SAFE_INTEGER,
                monOrderY: Number.isFinite(monY) ? monY : Number.MAX_SAFE_INTEGER,
                wsId: (typeof wsId === "number") ? wsId : Number.MAX_SAFE_INTEGER,
                x: relX, y: relY,
                title: t.title || "", address: addr, wayland: t.wayland
            })
        }

        if (missingAnyPosition && hasNewWindow) {
            _hasRefreshedOnce = false
            scheduleRefresh()
        }

        const groups = new Map()
        for (const it of snap) {
            const key = it.monKey + "::" + it.wsId
            if (!groups.has(key)) groups.set(key, [])
            groups.get(key).push(it)
        }

        let groupList = []
        for (const [key, arr] of groups) {
            const repr = arr[0]
            groupList.push({ key, monKey: repr.monKey, monOrderX: repr.monOrderX, monOrderY: repr.monOrderY, wsId: repr.wsId, items: arr })
        }

        groupList.sort((a, b) => {
            if (a.monOrderX !== b.monOrderX) return a.monOrderX - b.monOrderX
            if (a.monOrderY !== b.monOrderY) return a.monOrderY - b.monOrderY
            if (a.monKey !== b.monKey) return a.monKey.localeCompare(b.monKey)
            if (a.wsId !== b.wsId) return a.wsId - b.wsId
            return 0
        })

        const COLUMN_THRESHOLD = 48
        const JITTER_Y = 6
        let ordered = []
        for (const g of groupList) {
            const arr = g.items
            const xs = arr.map(it => it.x).filter(x => Number.isFinite(x)).sort((a, b) => a - b)
            let colCenters = []
            if (xs.length > 0) {
                for (const x of xs) {
                    if (colCenters.length === 0) colCenters.push(x)
                    else if (x - colCenters[colCenters.length - 1] >= COLUMN_THRESHOLD) colCenters.push(x)
                }
            } else { colCenters = [0] }

            for (const it of arr) {
                let bestCol = 0, bestDist = Number.POSITIVE_INFINITY
                for (let ci = 0; ci < colCenters.length; ci++) {
                    const d = Math.abs(it.x - colCenters[ci])
                    if (d < bestDist) { bestDist = d; bestCol = ci }
                }
                it._col = bestCol
            }

            arr.sort((a, b) => {
                if (a._col !== b._col) return a._col - b._col
                const dy = a.y - b.y
                if (Math.abs(dy) > JITTER_Y) return dy
                if (a.title !== b.title) return a.title.localeCompare(b.title)
                if (a.address !== b.address) return a.address.localeCompare(b.address)
                return 0
            })

            ordered.push.apply(ordered, arr)
        }

        return ordered.map(x => x.wayland).filter(w => w !== null && w !== undefined)
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Filter toplevels by current workspace
    // ═══════════════════════════════════════════════════════════════════════
    function filterCurrentWorkspace(toplevels, screen) {
        if (useNiriSorting) return NiriService.filterCurrentWorkspace(toplevels, screen)
        if (isHyprland) return filterHyprlandCurrentWorkspaceSafe(toplevels, screen)
        return toplevels
    }

    function filterHyprlandCurrentWorkspaceSafe(toplevels, screenName) {
        if (!toplevels || toplevels.length === 0 || !Hyprland.toplevels) return toplevels

        let currentWorkspaceId = null
        try {
            const hy = Array.from(Hyprland.toplevels.values)
            for (const t of hy) {
                const mon = _get(t, ["monitor", "name"], "")
                const wsId = _get(t, ["workspace", "id"], null)
                const active = !!_get(t, ["activated"], false)
                if (mon === screenName && wsId !== null) {
                    if (active) { currentWorkspaceId = wsId; break }
                    if (currentWorkspaceId === null) currentWorkspaceId = wsId
                }
            }
            if (currentWorkspaceId === null && Hyprland.workspaces) {
                const wss = Array.from(Hyprland.workspaces.values)
                const focusedId = _get(Hyprland, ["focusedWorkspace", "id"], null)
                for (const ws of wss) {
                    const monName = _get(ws, ["monitor"], "")
                    const wsId = _get(ws, ["id"], null)
                    if (monName === screenName && wsId !== null) {
                        if (focusedId !== null && wsId === focusedId) { currentWorkspaceId = wsId; break }
                        if (currentWorkspaceId === null) currentWorkspaceId = wsId
                    }
                }
            }
        } catch (e) { console.warn("CompositorService: workspace snapshot failed:", e) }

        if (currentWorkspaceId === null) return toplevels
        let map = new Map()
        try {
            const hy = Array.from(Hyprland.toplevels.values)
            for (const t of hy) {
                const wsId = _get(t, ["workspace", "id"], null)
                if (t && t.wayland && wsId !== null) map.set(t.wayland, wsId)
            }
        } catch (e) {}
        return toplevels.filter(w => map.get(w) === currentWorkspaceId)
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
        root.backend = comp.createObject(root)
        console.info(`CompositorService: ${root.backend.name} backend${root.backend.experimental ? " (experimental)" : ""}`)
        if (root.isHyprland) { try { Hyprland.refreshToplevels() } catch (e) {} }
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
    function setCursorZoom(factor) { return root.backend?.setCursorZoom(factor) ?? false }
    function switchKeyboardLayout(delta) { return root.backend?.switchKeyboardLayout(delta) ?? false }
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
    }

    // Windows are foreign-toplevel handles: focus/close work on every backend.
    function focusWindow(toplevel) { toplevel?.activate(); return !!toplevel }
    function closeWindow(toplevel) { toplevel?.close(); return !!toplevel }
}
