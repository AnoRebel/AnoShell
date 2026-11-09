import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings
import "."
/**
 * Settings overlay — floating panel over the shell (window + pages live in
 * SettingsOverlayWindow.qml). This always-loaded part only owns the IPC
 * target and the lazy loader. The current page is GlobalStates.settingsPage.
 */
Scope {
    id: root

    // Window + pages compile/instantiate on first open and are released after
    // the overlay has been closed for closeGrace (reopening within it is instant).
    // Driven imperatively: a binding on settingsOpen || timer.running could
    // flip false for a moment on close and rebuild the whole window.
    LazyLoader {
        id: windowLoader
        active: false
        // Loader (not LazyLoader.source) so nothing is compiled until first open.
        component: Loader { source: Qt.resolvedUrl("SettingsOverlayWindow.qml") }
    }
    Timer {
        id: closeGrace
        interval: 30000
        onTriggered: if (!GlobalStates.settingsOpen) windowLoader.active = false
    }
    Connections {
        target: GlobalStates
        function onSettingsOpenChanged() {
            if (GlobalStates.settingsOpen) { closeGrace.stop(); windowLoader.active = true }
            else closeGrace.restart()
        }
    }

    // settings.softenWallpaper with the awww engine: the shell doesn't draw
    // the wallpaper (ShellBackground blurs its own), so a translucent layer on
    // the background layer dims it instead. Mapped only while it shows.
    property real soften: GlobalStates.settingsOpen && (Config.options?.settings?.softenWallpaper ?? true)
        && (Config.options?.background?.engine ?? "awww") !== "shell" ? 1 : 0
    Behavior on soften { NumberAnimation { duration: AnimationConfig.scaledDuration(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard } }
    Variants {
        model: Quickshell.screens
        LazyLoader {
            id: dimLoader
            required property var modelData
            active: root.soften > 0
            PanelWindow {
                screen: dimLoader.modelData
                color: Qt.rgba(0, 0, 0, 0.25 * root.soften)
                exclusionMode: ExclusionMode.Ignore
                mask: Region {} // clicks reach the desktop
                WlrLayershell.layer: WlrLayer.Background
                WlrLayershell.namespace: "quickshell:wallpaperDim"
                anchors { top: true; bottom: true; left: true; right: true }
            }
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { GlobalStates.settingsOpen = !GlobalStates.settingsOpen }
        function open(): void { GlobalStates.settingsOpen = true }
        function close(): void {
            GlobalStates.settingsCommandPaletteOpen = false
            GlobalStates.settingsOpen = false
        }
        // Open on a page by index (0 = About, 1 = General … see SettingsRegistry.pages).
        function page(index: int): void {
            GlobalStates.settingsPage = Math.max(0, Math.min(index, SettingsRegistry.pages.length - 1))
            GlobalStates.settingsOpen = true
        }
        // Open the Ctrl+K palette with a query (scripts/tests drive it without keystrokes).
        function palette(query: string): void {
            GlobalStates.settingsOpen = true
            SettingsRegistry.query = query
            GlobalStates.settingsCommandPaletteOpen = true
        }
    }

    // `ano atelier [type]`: the Atelier page on a type's tab — in the overlay
    // when it is open, else in standalone Settings (which reads the env below).
    function openAtelier(type: string): void {
        const tab = Atelier.types.some(t => t.id === type) ? type : ""
        const page = SettingsRegistry.pages.findIndex(p => p.name === "Atelier")
        if (GlobalStates.settingsOpen) {
            if (tab) Atelier.tab = tab
            GlobalStates.settingsPage = page
            return
        }
        Quickshell.execDetached(["env", "ANO_SETTINGS_PAGE=atelier", `ANO_ATELIER_TAB=${tab}`,
            "qs", "-n", "-p", Quickshell.shellPath("settings.qml")])
    }
    IpcHandler {
        target: "atelier"
        function open(type: string): void { root.openAtelier(type) }
    }
}
