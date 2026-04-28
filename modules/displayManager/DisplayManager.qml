import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.services

/**
 * Display Manager — visual monitor configuration overlay.
 * Adapted from ilyamiro's MonitorPopup for Ano Shell.
 * Hyprland-only (uses hyprctl for monitor queries and apply).
 */
PanelWindow {
    id: panel

    WlSessionLock.surface: WlSessionLockSurface {}

    anchors {
        rect.x: (panel.screen.width - panelWidth) / 2
        rect.y: (panel.screen.height - panelHeight) / 2
        rect.width: panelWidth
        rect.height: panelHeight
    }

    property int panelWidth: Math.min(860, panel.screen.width * 0.55)
    property int panelHeight: Math.min(420, panel.screen.height * 0.45)

    screen: GlobalStates.primaryScreen
    visible: GlobalStates.displayManagerOpen && CompositorService.isHyprland
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true

    property string ns: "quickshell:displayManager"
    WlSessionLock.surface.layer: WlSessionLockSurface.Overlay

    color: "transparent"

    // ═══════════════════════════════════════════════════════════════════════
    // IPC
    // ═══════════════════════════════════════════════════════════════════════
    IpcHandler {
        target: "displayManager"
        function toggle(): void { GlobalStates.displayManagerOpen = !GlobalStates.displayManagerOpen }
        function open(): void { GlobalStates.displayManagerOpen = true }
        function close(): void { GlobalStates.displayManagerOpen = false }
    }

    // Close on click outside
    MouseArea {
        anchors.fill: parent
        onClicked: GlobalStates.displayManagerOpen = false
        z: -1
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Content
    // ═══════════════════════════════════════════════════════════════════════
    DisplayManagerContent {
        id: content
        anchors.fill: parent
        visible: GlobalStates.displayManagerOpen
    }
}
