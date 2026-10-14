import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.sidebarRight
import "."
/**
 * Right sidebar — slides in from the right edge.
 * Contains quick toggles, sliders, notifications, calendar, system info.
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

            // Whether THIS per-screen instance should show: the sidebar is open
            // AND (all-monitors mode, or this is the focused monitor).
            readonly property bool onFocusedOnly: Config.options?.sidebar?.onlyOnFocusedMonitor ?? true
            readonly property bool isFocusedScreen: !onFocusedOnly
                || (modelData?.name && modelData.name === GlobalStates.focusedScreenName)
            readonly property bool shouldShow: GlobalStates.sidebarRightOpen && isFocusedScreen

            Component.onCompleted: visible = shouldShow

            Connections {
                target: GlobalStates
                function onSidebarRightOpenChanged() {
                    if (sidebarRoot.shouldShow) { _closeTimer.stop(); sidebarRoot.visible = true }
                    else if (root.instantOpen) { _closeTimer.stop(); sidebarRoot.visible = false }
                    else _closeTimer.restart()
                }
            }
            // If focus moves between monitors while open, follow it.
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
                    if (GlobalStates.sidebarRightOpen
                        || Math.abs(Math.abs(slide.x) - (root.sidebarWidth + root.globalMargin)) < 1) sidebarRoot.visible = false
                    else restart()
                }
            }
            function hide() { GlobalStates.sidebarRightOpen = false }

            // Fuse into the connected frame, following the slide.
            ConnectedSurfaceLease {
                key: "sidebarRight:" + (sidebarRoot.modelData?.name ?? "")
                kind: "sidebar"; edge: "right"; priority: 5
                // Full height between the bar and the bottom band: both ends are
                // flush, so they fillet into them instead of rounding on their own.
                omitStartConnector: true; omitEndConnector: true
                screenName: sidebarRoot.modelData?.name ?? ""
                active: sidebarRoot.visible && progress > 0
                x: (sidebarRoot.screen?.width ?? 0) - PanelRegistry.inset(_scr, "right") - root.sidebarWidth + root.globalMargin + slide.x
                // The window is pushed in by exclusive zones (the bar).
                readonly property string _scr: sidebarRoot.modelData?.name ?? ""
                readonly property real _it: PanelRegistry.inset(_scr, "top")
                y: _it + root.globalMargin
                w: root.sidebarWidth - root.globalMargin * 2
                h: (sidebarRoot.screen?.height ?? 0) - _it - PanelRegistry.inset(_scr, "bottom") - root.globalMargin * 2
                progress: 1 - slide.x / Math.max(1, root.sidebarWidth + root.globalMargin)
            }

            exclusiveZone: 0
            implicitWidth: screen?.width ?? 1920
            WlrLayershell.namespace: "quickshell:sidebarRight"
            WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"
            anchors { top: true; right: true; bottom: true; left: true }

            MouseArea {
                anchors.fill: parent
                onClicked: mouse => {
                    const lp = mapToItem(contentLoader, mouse.x, mouse.y)
                    if (lp.x < 0 || lp.x > contentLoader.width || lp.y < 0 || lp.y > contentLoader.height) sidebarRoot.hide()
                }
            }

            Loader {
                id: contentLoader
                active: GlobalStates.sidebarRightOpen || (Config?.options?.sidebar?.keepRightSidebarLoaded ?? true)
                anchors { top: parent.top; right: parent.right; bottom: parent.bottom; margins: root.globalMargin }
                width: root.sidebarWidth - root.globalMargin * 2

                transform: Translate {
                    id: slide
                    x: GlobalStates.sidebarRightOpen ? 0 : (root.sidebarWidth + root.globalMargin)
                    Behavior on x {
                        enabled: !root.instantOpen
                        MotionSpring { token: GlobalStates.sidebarRightOpen ? "liquid" : "settle" }
                    }
                }

                focus: GlobalStates.sidebarRightOpen
                Keys.onPressed: event => { if (event.key === Qt.Key_Escape) sidebarRoot.hide() }

                sourceComponent: SidebarRightContent {
                    panelScreen: sidebarRoot.screen ?? null
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarRight"
        function toggle(): void { GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen }
        function close(): void { GlobalStates.sidebarRightOpen = false }
        function open(): void { GlobalStates.sidebarRightOpen = true }
    }
}
