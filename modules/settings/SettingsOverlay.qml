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
    LazyLoader {
        active: GlobalStates.settingsOpen || closeGrace.running
        // Loader (not LazyLoader.source) so nothing is compiled until first open.
        component: Loader { source: Qt.resolvedUrl("SettingsOverlayWindow.qml") }
    }
    Timer { id: closeGrace; interval: 30000 }
    Connections {
        target: GlobalStates
        function onSettingsOpenChanged() { if (!GlobalStates.settingsOpen) closeGrace.restart() }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { GlobalStates.settingsOpen = !GlobalStates.settingsOpen }
        function open(): void { GlobalStates.settingsOpen = true }
        function close(): void {
            GlobalStates.settingsCommandPaletteOpen = false
            GlobalStates.settingsOpen = false
        }
        // Open on a page by index (0 = General … see SettingsRegistry.pages).
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
}
