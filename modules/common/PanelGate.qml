pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * PanelGate — the one place that decides which shell modules exist.
 *
 * A panel family is data: the set of module ids it hosts. shell.qml
 * instantiates every module in `modules` behind enabled(id), so switching
 * family only loads/unloads the modules that differ, and Settings can ask
 * reason(id) why a module is off.
 *
 * A module is on when ALL hold: the active family hosts it, the user has not
 * switched it off (enabledPanels — empty list means "all"), its own feature
 * key (if any) is true, and the running compositor supports it.
 */
Singleton {
    id: root

    // id, Settings label/icon/desc/category, QML source, optional feature
    // key (dotted Config path), optional compositor requirement, and whether
    // the Modules page lists it (features with their own Settings page or
    // helper windows are not listed).
    readonly property var modules: [
        // Bars & status surfaces
        { id: "anoBar", name: "Bar", icon: "dock_to_bottom", desc: "Status bar with configurable modules", category: "Bars", source: "modules/bar/BarManager.qml" },
        { id: "anoDock", name: "Dock", icon: "space_dashboard", desc: "Application dock with pinned apps", category: "Bars", source: "modules/dock/Dock.qml", key: "dock.enable" },
        { id: "anoHUD", name: "HUD", icon: "dashboard", desc: "System dashboard overlay", category: "Bars", source: "modules/hud/HUD.qml", key: "hud.enable" },
        { id: "anoOnScreenDisplay", name: "OSD", icon: "volume_up", desc: "Volume/brightness/media indicators", category: "Bars", source: "modules/osd/OSD.qml" },
        { id: "anoNotificationPopup", name: "Notification Popups", icon: "notifications", desc: "Floating notification bubbles", category: "Bars", source: "modules/notificationPopup/NotificationPopup.qml" },
        // Overlays & panels
        { id: "anoOverview", name: "AnoView Overview", icon: "overview", desc: "Window overview with 10 layout algorithms", category: "Overlays", source: "modules/overview/AnoView.qml" },
        { id: "anoTaskView", name: "Task View", icon: "view_comfy", desc: "Current workspace window view", category: "Overlays", source: "modules/taskView/TaskView.qml" },
        { id: "anoAltSwitcher", name: "Alt-Tab Switcher", icon: "tab", desc: "Window switcher with thumbnails", category: "Overlays", source: "modules/altSwitcher/AltSwitcher.qml" },
        { id: "anoSearch", name: "App Launcher", icon: "search", desc: "Application search and launch", category: "Overlays", source: "modules/search/Search.qml" },
        { id: "anoControlPanel", name: "Control Panel", icon: "tune", desc: "Quick-access system controls", category: "Overlays", source: "modules/controlPanel/ControlPanel.qml" },
        { id: "anoNetworkOrbit", name: "Network Orbit", icon: "hub", desc: "Animated Wi-Fi / Bluetooth / VPN panel (network.panelStyle \"orbit\")", category: "Overlays", source: "modules/networkOrbit/NetworkOrbit.qml" },
        { id: "anoMediaControls", name: "Media Controls", icon: "music_note", desc: "Full media player panel", category: "Overlays", source: "modules/mediaControls/MediaControls.qml" },
        { id: "anoWeatherPanel", name: "Weather Panel", icon: "thermostat", desc: "Detailed weather information", category: "Overlays", source: "modules/weather/WeatherPanel.qml" },
        { id: "anoCalendar", name: "Calendar", icon: "calendar_month", desc: "Calendar panel with events and holidays", category: "Overlays", source: "modules/calendar/CalendarPanel.qml" },
        { id: "anoCheatsheet", name: "Keybind Cheatsheet", icon: "keyboard", desc: "Searchable keyboard shortcuts", category: "Overlays", source: "modules/cheatsheet/Cheatsheet.qml" },
        { id: "anoActions", name: "Actions Ring", icon: "bolt", desc: "Your macros on a ring (Settings → Actions; Super+Ctrl+X)", category: "Overlays", source: "modules/actions/ActionsRing.qml" },
        { id: "anoSessionScreen", name: "Session Screen", icon: "power_settings_new", desc: "Lock/logout/suspend/reboot/shutdown", category: "Overlays", source: "modules/session/SessionScreen.qml" },
        { id: "anoSettings", name: "Settings Overlay", icon: "settings", desc: "This settings panel", category: "Overlays", source: "modules/settings/SettingsOverlay.qml", required: true },
        // Sidebars
        { id: "anoSidebarLeft", name: "Left Sidebar", icon: "view_sidebar", desc: "AI Chat, Notifications, Translator", category: "Sidebars", source: "modules/sidebarLeft/SidebarLeft.qml" },
        { id: "anoSidebarRight", name: "Right Sidebar", icon: "view_sidebar", desc: "Quick controls, media, calendar, system info", category: "Sidebars", source: "modules/sidebarRight/SidebarRight.qml" },
        // Utilities & integrations
        { id: "anoClipboard", name: "Clipboard Manager", icon: "content_paste", desc: "Clipboard history browser", category: "Utilities", source: "modules/clipboard/ClipboardManager.qml" },
        { id: "anoScreenshot", name: "Screenshots", icon: "screenshot_region", desc: "Region, window and screen captures with a preview card (copy, save, edit, delete)", category: "Utilities", source: "modules/screenshot/ScreenshotPreview.qml" },
        { id: "anoWallpaperSelector", name: "Wallpaper Selector", icon: "image", desc: "Browse and apply wallpapers", category: "Utilities", source: "modules/wallpaperSelector/WallpaperSelector.qml" },
        { id: "anoScreenCorners", name: "Hot Corners", icon: "fullscreen", desc: "Screen corner triggers", category: "Utilities", source: "modules/screenCorners/ScreenCorners.qml", key: "screenCorners.enable" },
        { id: "anoFocusTime", name: "Focus Time", icon: "timer", desc: "App usage tracker with daily/weekly stats", category: "Utilities", source: "modules/focusTime/FocusTimePanel.qml", key: "focusTime.enable" },
        { id: "anoReader", name: "Reader", icon: "auto_stories", desc: "Novel, manga and anime panels (anod's reader backend)", category: "Utilities", source: "modules/reader/ReaderHost.qml", key: "reader.enable" },
        { id: "anoStickyNote", name: "Sticky Note", icon: "sticky_note_2", desc: "A note on the desktop, kept in a file (click-through toggle)", category: "Utilities", source: "modules/stickyNotes/StickyNote.qml", key: "stickyNotes.enable" },
        { id: "anoDisplayManager", name: "Display Manager", icon: "desktop_windows", desc: "Monitor arrangement, mode and scale", category: "Utilities", source: "modules/displayManager/DisplayManager.qml", key: "displayManager.enable", capability: "outputConfig" },
        { id: "anoPolkit", name: "Password Prompt", icon: "admin_panel_settings", desc: "Built-in polkit agent: asks for your password when an app needs permission", category: "Utilities", source: "modules/polkit/PolkitPrompt.qml", key: "polkit.enable" },
        { id: "anoLockScreen", name: "Lock Screen", icon: "lock", desc: "Locks the session on niri, with your chosen lock screen (Hyprland locks with hyprlock; there only the preview runs)", category: "Utilities", source: "modules/lock/LockScreen.qml" },
        // Features with their own Settings pages (not listed on the Modules page)
        { id: "anoScreen", source: "modules/anoScreen/AnoScreen.qml", key: "appearance.connectedCorners.enable", listed: false },
        { id: "anoBackground", source: "modules/background/ShellBackground.qml", effective: "shellBackground", listed: false },
        { id: "anoSpot", source: "modules/anoSpot/AnoSpot.qml", key: "anoSpot.enable", orPillBar: true, listed: false },
        { id: "anoSpotStash", source: "modules/anoSpot/AnoSpotStashPopout.qml", key: "anoSpot.enable", orPillBar: true, listed: false },
        { id: "anoCustomize", source: "modules/settings/CustomizeSheet.qml", listed: false },
        { id: "anoWelcome", source: "modules/onboarding/Welcome.qml", listed: false },
        { id: "anoDisplayConfirm", source: "modules/displayManager/DisplayConfirm.qml", listed: false },
        { id: "anoMorphLayer", source: "modules/common/widgets/TopLayerPanel.qml", listed: false, effective: "morphingPanels" },
        { id: "anoPieces", source: "modules/pieces/PieceLayer.qml", key: "pieces.enable", listed: false, effective: "piecesShown" },
        { id: "anoScratchpad", source: "modules/scratchpad/ScratchpadPanel.qml", key: "scratchpad.enable", listed: false },
    ]

    // Ids each family hosts. Everything not listed here is unavailable in
    // that family (Settings shows it disabled with the reason).
    readonly property var _core: ["anoBar", "anoScreen", "anoOverview", "anoNotificationPopup", "anoOnScreenDisplay",
        "anoSessionScreen", "anoSettings", "anoSearch", "anoAltSwitcher", "anoLockScreen", "anoPolkit",
        "anoSpot", "anoSpotStash", "anoBackground", "anoDisplayConfirm", "anoWelcome", "anoCustomize", "anoPieces", "anoScratchpad", "anoActions"]
    readonly property var _sidebars: ["anoSidebarLeft", "anoSidebarRight", "anoClipboard", "anoScreenshot", "anoCheatsheet", "anoCalendar"]
    readonly property var _rich: ["anoDock", "anoHUD", "anoTaskView", "anoControlPanel", "anoNetworkOrbit", "anoMediaControls",
        "anoWeatherPanel", "anoWallpaperSelector", "anoScreenCorners", "anoMorphLayer", "anoReader", "anoStickyNote"]
    readonly property var familyModules: ({
        "ano": _core.concat(_sidebars, _rich, ["anoFocusTime", "anoDisplayManager"]),
        "hefty": _core.concat(_sidebars, _rich),
        "clean": _core.concat(_sidebars),
        "minimal": _core,
    })

    readonly property string family: Config.options?.panelFamily ?? "ano"
    readonly property var _hosted: familyModules[family] ?? familyModules["ano"]

    // Family-dependent effective values (computed, never written to config).
    // Hefty is the morphing family; Clean/Minimal never morph; Ano follows the setting.
    readonly property bool shellBackground: (Config.options?.background?.engine ?? "awww") === "shell"
    readonly property bool morphingPanels: family === "hefty" ? true
        : family === "ano" ? (Config.options?.bar?.morphingPanels ?? false) : false

    // Performance mode puts the pieces away (performance.hidePieces).
    readonly property bool piecesShown: !GameMode.hidePieces
    function module(id) { return root.modules.find(m => m.id === id) ?? null }

    function _keyValue(path) {
        let v = Config.options
        for (const part of path.split(".")) { v = v?.[part]; if (v === undefined) return undefined }
        return v
    }

    function hosted(id) { return root._hosted.includes(id) }

    // disabledPanels (or a legacy enabledPanels) only governs modules listed on
    // the Modules page; unlisted
    // features are switched by their own key.
    function userEnabled(id) {
        const m = root.module(id)
        if (!m || m.listed === false || m.required) return true
        if ((Config.options?.disabledPanels ?? []).includes(id)) return false
        // Legacy allow-list (configs written before disabledPanels): empty = all.
        const legacy = Config.options?.enabledPanels ?? []
        return legacy.length === 0 || legacy.includes(id)
    }

    // anoSpot.pillOnly: the pill replaces the bar and the dock (their own
    // switches are left as they are, so turning it off brings them back).
    readonly property bool pillOnly: (Config.options?.anoSpot?.pillOnly ?? false) && (Config.options?.anoSpot?.enable ?? false)
    readonly property var _pillOnlyHides: ["anoBar", "anoDock"]

    function enabled(id) {
        if (!Config.ready) return false
        const m = root.module(id)
        if (!m || !root.hosted(id) || !root.userEnabled(id)) return false
        if (root.pillOnly && root._pillOnlyHides.includes(id)) return false
        // The pill also loads when it is the bar (bar.style pill), whatever
        // anoSpot.enable says.
        if (m.key && !(root._keyValue(m.key) ?? false) && !(m.orPillBar && BarStyle.pillBar)) return false
        if (m.effective && !root[m.effective]) return false
        if (m.compositor && CompositorService.compositor !== m.compositor) return false
        if (m.capability && !(CompositorService.supports[m.capability] ?? false)) return false
        return true
    }

    // Why a hosted-or-not module is unavailable; "" when the user can toggle it.
    function reason(id) {
        const m = root.module(id)
        if (!m) return "unknown module"
        if (!root.hosted(id)) return `not available in the ${root.family} family`
        if (root.pillOnly && root._pillOnlyHides.includes(id)) return "hidden by AnoSpot \"Pill only\""
        if (m.compositor && CompositorService.compositor !== m.compositor)
            return `${m.compositor === "niri" ? "niri" : "Hyprland"} only`
        if (m.capability && !(CompositorService.supports[m.capability] ?? false))
            return `not supported on ${CompositorService.backendName} yet`
        return ""
    }
}
