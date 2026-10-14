import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.sidebarLeft
import "."
/**
 * Left sidebar — slides in from the left edge.
 * Contains notifications center and media player.
 */
Scope {
    id: root
    property int sidebarWidth: Appearance?.sizes.sidebarWidth ?? 420
    readonly property bool instantOpen: Config.options?.sidebar?.instantOpen ?? false
    readonly property real globalMargin: Config.options?.appearance?.bezel ?? 0

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: sidebarRoot
            required property var modelData
            screen: modelData

            // Show only on the focused monitor unless all-monitors mode is on.
            readonly property bool onFocusedOnly: Config.options?.sidebar?.onlyOnFocusedMonitor ?? true
            readonly property bool isFocusedScreen: !onFocusedOnly
                || (modelData?.name && modelData.name === GlobalStates.focusedScreenName)
            readonly property bool shouldShow: GlobalStates.sidebarLeftOpen && isFocusedScreen

            Component.onCompleted: visible = shouldShow

            Connections {
                target: GlobalStates
                function onSidebarLeftOpenChanged() {
                    if (sidebarRoot.shouldShow) { _closeTimer.stop(); sidebarRoot.visible = true }
                    else if (root.instantOpen) { _closeTimer.stop(); sidebarRoot.visible = false }
                    else _closeTimer.restart()
                }
            }
            onShouldShowChanged: {
                if (shouldShow) { _closeTimer.stop(); visible = true }
                else if (root.instantOpen) { _closeTimer.stop(); visible = false }
                else _closeTimer.restart()
            }
            // Hide once the spring has retracted the body into its edge (a fixed
            // delay cut the retract short).
            Timer {
                id: _closeTimer; interval: 100
                onTriggered: {
                    if (sidebarRoot.shouldShow) return
                    // Open on another monitor: nothing retracts here, hide now.
                    if (GlobalStates.sidebarLeftOpen
                        || Math.abs(Math.abs(slide.x) - (root.sidebarWidth + root.globalMargin)) < 1) sidebarRoot.visible = false
                    else restart()
                }
            }
            function hide() { GlobalStates.sidebarLeftOpen = false }

            // Fuse into the connected frame, following the slide: the body's
            // outer edge is the content's translated right edge.
            ConnectedSurfaceLease {
                key: "sidebarLeft:" + (sidebarRoot.modelData?.name ?? "")
                kind: "sidebar"; edge: "left"; priority: 5
                // Full height between the bar and the bottom band: both ends are
                // flush, so they fillet into them instead of rounding on their own.
                omitStartConnector: true; omitEndConnector: true
                screenName: sidebarRoot.modelData?.name ?? ""
                active: sidebarRoot.visible && progress > 0
                x: PanelRegistry.inset(_scr, "left") + root.globalMargin + slide.x
                // The window is pushed in by exclusive zones (the bar).
                readonly property string _scr: sidebarRoot.modelData?.name ?? ""
                readonly property real _it: PanelRegistry.inset(_scr, "top")
                y: _it + root.globalMargin
                w: contentLoader.width
                h: (sidebarRoot.screen?.height ?? 0) - _it - PanelRegistry.inset(_scr, "bottom") - root.globalMargin * 2
                progress: (slide.x + root.globalMargin + w) / Math.max(1, root.globalMargin + w)
            }

            exclusiveZone: 0
            implicitWidth: screen?.width ?? 1920
            WlrLayershell.namespace: "quickshell:sidebarLeft"
            WlrLayershell.keyboardFocus: GlobalStates.sidebarLeftOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"
            anchors { top: true; left: true; bottom: true; right: true }

            // Backdrop click to dismiss
            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    const lp = mapToItem(contentLoader, mouse.x, mouse.y)
                    if (lp.x < 0 || lp.x > contentLoader.width || lp.y < 0 || lp.y > contentLoader.height) sidebarRoot.hide()
                }
            }

            Loader {
                id: contentLoader
                active: GlobalStates.sidebarLeftOpen || (Config?.options?.sidebar?.keepLeftSidebarLoaded ?? true)
                anchors { top: parent.top; left: parent.left; bottom: parent.bottom; margins: root.globalMargin }
                width: root.sidebarWidth - root.globalMargin * 2

                transform: Translate {
                    id: slide
                    x: GlobalStates.sidebarLeftOpen ? 0 : -(root.sidebarWidth + root.globalMargin)
                    Behavior on x {
                        enabled: !root.instantOpen
                        MotionSpring { token: GlobalStates.sidebarLeftOpen ? "liquid" : "settle" }
                    }
                }

                focus: GlobalStates.sidebarLeftOpen
                Keys.onPressed: event => { if (event.key === Qt.Key_Escape) sidebarRoot.hide() }

                sourceComponent: SidebarLeftContent {}
            }
        }
    }

    IpcHandler {
        target: "sidebarLeft"
        function toggle(): void { GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen }
        function close(): void { GlobalStates.sidebarLeftOpen = false }
        function open(): void { GlobalStates.sidebarLeftOpen = true }
    }
}
