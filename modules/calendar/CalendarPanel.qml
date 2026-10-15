import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * Calendar panel — month grid + upcoming-events list, sourced from
 * CalendarSync (external ICS feeds) and DateTime (today highlight).
 *
 * IPC: `qs -c ano ipc call calendar toggle`. Panel is layer-shell
 * Non-modal overlay card; Escape closes.
 *
 * Read-only: clicking a date filters the bottom list to that day's
 * events; "Today" button resets to the upcoming view. Editing feeds
 * happens in Settings → Services → Calendar sync.
 *
 * Spec: ano-deferred-features-batch-2026 ▸ calendar-sync.
 */
Scope {
    id: root

    readonly property bool open: GlobalStates.calendarOpen

    IpcHandler {
        target: "calendar"
        function toggle(): void { GlobalStates.calendarOpen = !GlobalStates.calendarOpen }
        function open(): void { GlobalStates.calendarOpen = true }
        function close(): void { GlobalStates.calendarOpen = false }
    }

    Variants {
        model: root.open ? Quickshell.screens : []

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            visible: root.open
            color: "transparent"

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:calendar"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Non-modal: input only on the card; clicks elsewhere reach your windows.
            mask: Region { x: card.x; y: card.y; width: card.width; height: card.height }  // geometry: an item region keeps the scale-in size

            // Card
            PanelDragHandle { panelCard: card; key: "calendar" }

            SurfaceMaterial {
                id: card
                surface: "calendar"
                anchors.centerIn: parent
                width: 420
                height: Math.min(620, parent.height * 0.85)
                radius: Appearance?.rounding.normal ?? 14
                // Same card as the other panels: an opaque background, so the
                // text stays readable over any wallpaper (a translucent fill
                // plus whole-card opacity washed the text out).
                color: Appearance?.m3colors.m3background ?? "#1C1B1F"
                border.width: 1; border.color: Appearance?.colors.colLayer0Border ?? "#44444488"


                // Animation in/out
                scale: root.open ? 1 : 0.95
                Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(180); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                CalendarContent {
                    id: calContent
                    anchors.fill: parent
                    anchors.margins: 12
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) GlobalStates.calendarOpen = false
                }
            }
        }
    }
}
