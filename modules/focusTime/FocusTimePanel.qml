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
 * FocusTime Panel — app usage tracker overlay.
 * Adapted from ilyamiro's FocusTimePopup for Ano Shell.
 * Uses Appearance singleton for theming, compositor-agnostic.
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

    property int panelWidth: Math.min(820, panel.screen.width * 0.55)
    property int panelHeight: Math.min(680, panel.screen.height * 0.75)

    screen: GlobalStates.primaryScreen
    visible: GlobalStates.focusTimeOpen
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: true

    // Namespace for layer rules
    property string ns: "quickshell:focusTime"
    WlSessionLock.surface.layer: WlSessionLockSurface.Overlay

    color: "transparent"

    // ═══════════════════════════════════════════════════════════════════════
    // IPC
    // ═══════════════════════════════════════════════════════════════════════
    IpcHandler {
        target: "focusTime"
        function toggle(): void { GlobalStates.focusTimeOpen = !GlobalStates.focusTimeOpen }
        function open(): void { GlobalStates.focusTimeOpen = true }
        function close(): void { GlobalStates.focusTimeOpen = false }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Close on click outside
    // ═══════════════════════════════════════════════════════════════════════
    MouseArea {
        anchors.fill: parent
        onClicked: GlobalStates.focusTimeOpen = false
        z: -1
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Content
    // ═══════════════════════════════════════════════════════════════════════
    FocusTimeContent {
        id: content
        anchors.fill: parent
        visible: GlobalStates.focusTimeOpen
    }
}
