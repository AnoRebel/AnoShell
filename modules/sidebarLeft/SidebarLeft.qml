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

            Component.onCompleted: { visible = shouldShow; _updateReg() }

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
            Timer { id: _closeTimer; interval: 300; onTriggered: sidebarRoot.visible = false }
            function hide() { GlobalStates.sidebarLeftOpen = false }

            // Register content rect with PanelRegistry for connected-corners joins.
            readonly property string _regKey: "sidebarLeft:" + (modelData?.name ?? "")
            readonly property bool _regActive: GlobalStates.sidebarLeftOpen && sidebarRoot.visible
            function _updateReg() {
                if (_regActive) {
                    const m = root.globalMargin
                    const sh = screen?.height ?? 0
                    PanelRegistry.register(_regKey, {
                        "kind": "sidebar", "screenName": modelData?.name ?? "", "edge": "left",
                        "x": m, "y": m,
                        "w": root.sidebarWidth - m * 2, "h": sh - m * 2
                    })
                } else {
                    PanelRegistry.unregister(_regKey)
                }
            }
            on_RegActiveChanged: _updateReg()
            Component.onDestruction: PanelRegistry.unregister(_regKey)

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
                    x: GlobalStates.sidebarLeftOpen ? 0 : -(root.sidebarWidth + root.globalMargin)
                    Behavior on x {
                        enabled: !root.instantOpen
                        NumberAnimation {
                            duration: (Appearance?.animationCurves.expressiveDefaultSpatialDuration ?? 500) * (Appearance?.animSpeedMultiplier ?? 1)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Appearance?.animationCurves.expressiveDefaultSpatial ?? [0.38, 1.21, 0.22, 1.00, 1, 1]
                        }
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
