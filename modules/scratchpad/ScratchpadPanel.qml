import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The scratchpad on its own, for when the pill isn't running (with the pill
 * it grows out of the pill instead, AnoSpot.qml): a card on the pill's edge
 * (anoSpot.position), on the focused screen.
 */
Scope {
    id: root
    readonly property bool pillRunning: PanelGate.enabled("anoSpot")
    readonly property bool shown: Scratchpad.open && !root.pillRunning
    readonly property string edge: ["top", "bottom", "left", "right"].includes(BarStyle.pillEdge) ? BarStyle.pillEdge : "top"

    PanelWindow {
        id: win
        visible: root.shown || card.opacity > 0.01
        screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.namespace: "quickshell:scratchpad"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors {
            top: root.edge === "top"; bottom: root.edge === "bottom"
            left: root.edge === "left"; right: root.edge === "right"
        }
        margins { top: 8; bottom: 8; left: 8; right: 8 }
        implicitWidth: Math.min(760, (screen?.width ?? 1280) - 32)
        implicitHeight: 432
        mask: Region { item: card }
        Shortcut { sequence: "Escape"; autoRepeat: false; enabled: root.shown; onActivated: Scratchpad.open = false }

        SurfaceMaterial {
            id: card
            surface: "scratchpad"
            anchors.fill: parent
            radius: Appearance.rounding.windowRounding
            color: Appearance.m3colors.m3background
            clip: true
            opacity: root.shown ? 1 : 0
            // Comes out of its edge.
            transform: Translate {
                readonly property real d: root.shown ? 0 : 24
                x: root.edge === "left" ? -d : root.edge === "right" ? d : 0
                y: root.edge === "top" ? -d : root.edge === "bottom" ? d : 0
                Behavior on x { MotionSpring { token: "settle" } }
                Behavior on y { MotionSpring { token: "settle" } }
            }
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }

            Loader {
                anchors { fill: parent; margins: 16 }
                active: root.shown
                sourceComponent: ScratchpadContent { onCloseRequested: Scratchpad.open = false }
            }
        }
    }
}
