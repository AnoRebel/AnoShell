import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.spectrum
import qs.services

/**
 * Full-screen media controls panel. Shows large album art,
 * track info, playback controls, volume slider, player switcher,
 * and optional audio spectrum visualizer.
 */
Scope {
    id: root

    IpcHandler {
        target: "mediaControls"
        function toggle(): void { GlobalStates.mediaControlsOpen = !GlobalStates.mediaControlsOpen }
        function open(): void { GlobalStates.mediaControlsOpen = true }
        function close(): void { GlobalStates.mediaControlsOpen = false }
    }

    Connections {
        target: GlobalStates
        function onMediaControlsOpenChanged() {
            if (GlobalStates.mediaControlsOpen) SpectrumService.registerComponent("media")
            else SpectrumService.unregisterComponent("media")
        }
    }

    PanelWindow {
        id: mediaWindow
        visible: GlobalStates.mediaControlsOpen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:media"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.mediaControlsOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // Non-modal: no scrim, input only on the card (clicks elsewhere reach
        // your windows), keyboard focus when you interact with it.
        mask: Region { x: mediaCard.x; y: mediaCard.y; width: mediaCard.width; height: mediaCard.height }  // geometry: an item region keeps the scale-in size
        anchors { top: true; bottom: true; left: true; right: true }

        // Keys can't attach to a window (only to Items): a focused Item that
        // fills it receives the window's keys.
        Item {
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) GlobalStates.mediaControlsOpen = false
                else if (event.key === Qt.Key_Space) MprisController.togglePlaying()
                else if (event.key === Qt.Key_Right) MprisController.next()
                else if (event.key === Qt.Key_Left) MprisController.previous()
            }
        }

        // Media card
        PanelDragHandle { panelCard: mediaCard; key: "media" }

        SurfaceMaterial {
            id: mediaCard
            surface: "media"
            anchors.centerIn: parent
            width: Math.min(480, parent.width * 0.55)
            height: mediaContent.implicitHeight + 48
            radius: Appearance?.rounding.windowRounding ?? 20
            color: Appearance?.m3colors.m3background ?? "#1C1B1F"
            border.width: 1; border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
            clip: true

            opacity: GlobalStates.mediaControlsOpen ? 1 : 0
            scale: GlobalStates.mediaControlsOpen ? 1 : 0.9
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
            Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(300); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

            MediaControlsContent {
                id: mediaContent
                anchors { fill: parent; margins: 24 }
            }
        }
    }
}
