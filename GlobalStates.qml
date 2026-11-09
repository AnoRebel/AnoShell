pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// GlobalStates: Central state singleton for all panel/overlay open/close states.
// Compositor-aware: uses Loader for Hyprland-only GlobalShortcuts.
Singleton {
    id: root

    // ═══════════════════════════════════════════════════════════════════════
    // Panel & Overlay States
    // ═══════════════════════════════════════════════════════════════════════
    // True once the config is ready and startup layout has settled; the bar,
    // pill, dock and frame map only then, so nothing jumps or flashes at start.
    property bool shellSettled: false
    // Where each standalone panel was dragged to this session (PanelDragHandle).
    property var panelPositions: ({})
    property bool barOpen: true
    property bool crosshairOpen: false
    property bool sidebarLeftOpen: false
    property bool sidebarRightOpen: false
    // Bumped each time a connected-frame window maps: Top-layer surfaces stack in
    // map order, so a sidebar mapped before it would sit under the frame.
    property int frameGeneration: 0
    // Windows with a StyledPopup open from them (its anchor's window), so the
    // pill doesn't morph into a transient out from under its own drawer.
    // One entry per open popout (a window can have two open).
    property var popoutWindows: []
    function setPopoutOpen(win, open) {
        if (!win) return
        const list = root.popoutWindows.slice()
        if (open) list.push(win)
        else { const i = list.indexOf(win); if (i < 0) return; list.splice(i, 1) }
        root.popoutWindows = list
    }
    property bool mediaControlsOpen: false
    property bool osdBrightnessOpen: false
    property bool osdVolumeOpen: false
    property bool osdMediaOpen: false
    property string osdMediaAction: "play" // "play", "pause", "next", "previous"
    property bool oskOpen: false
    property bool overlayOpen: false
    property bool overviewOpen: false
    property bool taskViewOpen: false
    property bool altSwitcherOpen: false
    property bool clipboardOpen: false
    property bool controlPanelOpen: false
    property bool cheatsheetOpen: false
    property bool actionsRingOpen: false   // the actions ring (modules/actions)
    property bool settingsOverlayOpen: false
    property bool settingsOpen: false
    property bool settingsCommandPaletteOpen: false
    // Settings overlay page index (kept here so it survives the window being unloaded).
    property int settingsPage: 0
    // In-place Customize: "bar", "pill" or "dock" while its sheet is open.
    property string customizeSurface: ""
    // The palette jumped to an advanced option: show advanced cards until Settings closes.
    property bool settingsRevealAdvanced: false
    // What advanced Settings cards follow: your choice, or a palette jump.
    readonly property bool settingsShowAdvanced: (Config.options.settings?.showAdvanced ?? false) || settingsRevealAdvanced
    // Hidden with the palette up: reopening it would find the palette open but
    // the keyboard on the page keys (its field only takes focus when created).
    onSettingsOpenChanged: if (!settingsOpen) { settingsRevealAdvanced = false; settingsCommandPaletteOpen = false }
    property bool regionSelectorOpen: false
    property bool searchOpen: false
    property bool weatherPanelOpen: false
    property bool focusTimeOpen: false
    property bool displayManagerOpen: false
    property bool anoSpotStashOpen: false
    property bool calendarOpen: false
    // Network Orbit panel (modules/networkOrbit) and its tab: wifi, bt, vpn, eth.
    property bool networkOrbitOpen: false
    property string networkOrbitTab: "wifi"
    // True when network.panelStyle is "orbit" and the panel is loaded: the bar
    // and sidebar network/Bluetooth entry points then open it instead of their
    // inline pickers.
    readonly property bool networkOrbitStyle: (Config.options?.network?.panelStyle ?? "classic") === "orbit"
        && PanelGate.enabled("anoNetworkOrbit")
    function openNetworkOrbit(tab: string): void {
        const t = String(tab ?? "").toLowerCase()
        const alias = { wlan: "wifi", bluetooth: "bt", ethernet: "eth", wired: "eth" }
        const m = alias[t] ?? t
        if (["wifi", "bt", "vpn", "eth"].includes(m)) root.networkOrbitTab = m
        root.networkOrbitOpen = true
    }
    // Closes it when it is already open on that tab (or tab is ""), else opens it there.
    function toggleNetworkOrbit(tab: string): void {
        const t = String(tab ?? "")
        if (root.networkOrbitOpen && (t === "" || t === root.networkOrbitTab)) root.networkOrbitOpen = false
        else root.openNetworkOrbit(t)
    }

    // Lock screen
    property bool screenLocked: false
    property bool screenLockContainsCharacters: false
    property bool screenUnlockFailed: false

    // Session
    property bool sessionOpen: false

    // Keyboard state
    property bool superDown: false
    property bool superReleaseMightTrigger: true

    // Wallpaper selector
    property bool wallpaperSelectorOpen: false
    property bool coverflowSelectorOpen: false
    property string wallpaperSelectionTarget: "main" // "main", "backdrop"
    property string wallpaperSelectorTargetMonitor: ""
    onWallpaperSelectorOpenChanged: {
        if (!wallpaperSelectorOpen) {
            wallpaperSelectionTarget = "main";
            wallpaperSelectorTargetMonitor = "";
        }
    }
    onCoverflowSelectorOpenChanged: {
        if (!coverflowSelectorOpen) {
            wallpaperSelectionTarget = "main";
            wallpaperSelectorTargetMonitor = "";
        }
    }

    // Workspace numbers overlay
    property bool workspaceShowNumbers: false

    // HUD
    property bool hudVisible: false

    // Panel family transition
    property bool familyTransitionActive: false
    property string familyTransitionDirection: "left"

    // Cross-panel dialog requests
    property bool requestWifiDialog: false
    property bool requestBluetoothDialog: false

    // ═══════════════════════════════════════════════════════════════════════
    // Signals
    // ═══════════════════════════════════════════════════════════════════════
    signal requestRipple(real x, real y, string screenName)

    // ═══════════════════════════════════════════════════════════════════════
    // Primary Screen (user-configured or fallback to first screen)
    // ═══════════════════════════════════════════════════════════════════════
    readonly property var primaryScreen: {
        const name = Config.options?.display?.primaryMonitor ?? ""
        if (name.length > 0) {
            const s = Quickshell.screens.find(scr => scr.name === name)
            if (s) return s
        }
        return Quickshell.screens[0]
    }

    // Name of the currently focused monitor (compositor-agnostic; delegated to
    // CompositorService). Used to open per-screen overlays only on the active
    // monitor.
    readonly property string focusedScreenName: CompositorService.focusedMonitorName
    readonly property var focusedScreen: {
        const n = focusedScreenName
        if (n.length > 0) {
            const s = Quickshell.screens.find(scr => scr.name === n)
            if (s) return s
        }
        return primaryScreen
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Sidebar notification integration
    // ═══════════════════════════════════════════════════════════════════════
    onSidebarRightOpenChanged: {
        if (root.sidebarRightOpen) {
            // Mark notifications as read when opening notification sidebar
            // (Notifications service will be available in Phase 2)
            try {
                Notifications.timeoutAll();
                Notifications.markAllRead();
            } catch (e) {}
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Screen Zoom (where the compositor supports it — supports.cursorZoom)
    // ═══════════════════════════════════════════════════════════════════════
    // Applied once per step. (An animated Behavior here sent one compositor
    // command per animation frame — ~60 process spawns per second.)
    property real screenZoom: 1
    onScreenZoomChanged: CompositorService.setCursorZoom(root.screenZoom)

    // ═══════════════════════════════════════════════════════════════════════
    // Compositor-guarded shortcuts (only load on Hyprland)
    // ═══════════════════════════════════════════════════════════════════════
    Loader {
        active: CompositorService.isHyprland
        sourceComponent: GlobalShortcut {
            name: "workspaceNumber"
            description: "Hold to show workspace numbers, release to show icons"
            onPressed: root.superDown = true
            onReleased: root.superDown = false
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // IPC Handlers (compositor-agnostic)
    // ═══════════════════════════════════════════════════════════════════════
    IpcHandler {
        target: "zoom"
        function zoomIn(): void { screenZoom = Math.min(screenZoom + 0.4, 3.0) }
        function zoomOut(): void { screenZoom = Math.max(screenZoom - 0.4, 1) }
    }

    // Test alive handler — used by Hyprland keybinds to check if shell is running
    IpcHandler {
        target: "TEST_ALIVE"
        // Just existing is enough — if this IPC call succeeds, the shell is alive
    }
}
