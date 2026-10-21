import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.spectrum
import qs.services

/**
 * Control Panel — floating quick-access panel with system controls.
 * Shows quick toggles, sliders, media, battery, and network at a glance.
 * This is a standalone overlay distinct from the right sidebar — more like
 * Android's notification shade or macOS Control Center.
 *
 * Triggered via IPC, keybind, or bar click action "controlPanel".
 */
Scope {
    id: root

    // ResourceUsage polls only while a visible consumer holds a lease.
    ServiceLease { service: ResourceUsage; name: "controlPanel"; active: GlobalStates.controlPanelOpen }

    IpcHandler {
        target: "controlPanel"
        function toggle(): void { GlobalStates.controlPanelOpen = !GlobalStates.controlPanelOpen }
        function open(): void { GlobalStates.controlPanelOpen = true }
        function close(): void { GlobalStates.controlPanelOpen = false }
    }

    PanelWindow {
        id: cpWindow
        // Mapped until the card's exit animation ends (closing used to unmap at once).
        visible: GlobalStates.controlPanelOpen || cpCard.opacity > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:controlPanel"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.controlPanelOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // Non-modal: no scrim, input only on the card (clicks elsewhere reach
        // your windows), keyboard focus when you interact with it.
        mask: Region { x: cpCard.x; y: cpCard.y; width: cpCard.width; height: cpCard.height }  // geometry: an item region keeps the scale-in size
        anchors { top: true; bottom: true; left: true; right: true }
        // Keys can't attach to a window (only to Items); a Shortcut works there.
        Shortcut { sequence: "Escape"; autoRepeat: false; onActivated: GlobalStates.controlPanelOpen = false }

        // Panel card — positioned at top-right like a notification shade
        PanelDragHandle { panelCard: cpCard; key: "controlPanel" }

        SurfaceMaterial {
            id: cpCard
            surface: "controlPanel"
            anchors { top: parent.top; right: parent.right; margins: (Config.options?.appearance?.bezel ?? 0) + 8 }
            anchors.topMargin: (Config.options?.bar?.layout?.height ?? 42) + (Config.options?.appearance?.bezel ?? 0) + 12
            width: Math.min(380, parent.width * 0.4)
            height: Math.min(cpContent.implicitHeight + 32, parent.height * 0.7)
            radius: Appearance?.rounding.windowRounding ?? 20
            color: Appearance?.m3colors.m3background ?? "#1C1B1F"
            border.width: 1; border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
            clip: true

            opacity: GlobalStates.controlPanelOpen ? 1 : 0
            transform: Translate {
                y: GlobalStates.controlPanelOpen ? 0 : -20
                Behavior on y { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: GlobalStates.controlPanelOpen ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel } }
            }
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: (GlobalStates.controlPanelOpen ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel) } }

            StyledFlickable {
                anchors { fill: parent; margins: 16 }
                contentHeight: cpContent.implicitHeight
                clip: true

                ControlPanelContent {
                    id: cpContent
                    width: parent.width; spacing: 12
                    onCloseRequested: GlobalStates.controlPanelOpen = false
                }
            }
        }
    }

}
