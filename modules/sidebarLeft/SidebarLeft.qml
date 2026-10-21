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

            // Mapped always; closed it is "parked" (no input, no focus, content
            // slid away): mapping on every open cost a slow first frame.
            property bool parked: !shouldShow
            // Mapped on the first open (after the connected frame exists) and kept;
            // re-mapped if the frame window was re-created since, to stay above it
            // (Top-layer surfaces stack in map order).
            property bool _mapped: false
            property int _mappedGen: -1
            visible: _mapped
            function _ensureMapped() {
                if (_remap.running) return
                if (!_mapped) { _mapped = true; _mappedGen = GlobalStates.frameGeneration }
                else if (_mappedGen !== GlobalStates.frameGeneration && parked) { _mapped = false; _remap.restart() }
            }
            // Unmapped for a moment (a real unmap, not a same-turn flip), then mapped above the frame.
            Timer { id: _remap; interval: 30; onTriggered: { sidebarRoot._mapped = true; sidebarRoot._mappedGen = GlobalStates.frameGeneration } }
            Component.onCompleted: if (shouldShow) _ensureMapped()
            mask: parked ? noInput : null
            Region { id: noInput; item: null } // an empty input region: clicks pass through

            Connections {
                target: GlobalStates
                function onSidebarLeftOpenChanged() {
                    if (sidebarRoot.shouldShow) { _closeTimer.stop(); sidebarRoot._ensureMapped(); sidebarRoot.parked = false }
                    else if (root.instantOpen) { _closeTimer.stop(); sidebarRoot.parked = true }
                    else _closeTimer.restart()
                }
            }
            onShouldShowChanged: {
                if (shouldShow) { _closeTimer.stop(); _ensureMapped(); parked = false }
                else if (root.instantOpen) { _closeTimer.stop(); parked = true }
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
                        || Math.abs(Math.abs(slide.x) - (root.sidebarWidth + root.globalMargin)) < 1) sidebarRoot.parked = true
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
                active: !sidebarRoot.parked && progress > 0
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
            // Per screen: a parked copy on another monitor must not take the keyboard.
            WlrLayershell.keyboardFocus: sidebarRoot.shouldShow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
                // Parked (closed, slid away): not drawn at all, so nothing in it renders.
                visible: !sidebarRoot.parked
                active: GlobalStates.sidebarLeftOpen || (Config?.options?.sidebar?.keepLeftSidebarLoaded ?? true)
                anchors { top: parent.top; left: parent.left; bottom: parent.bottom; margins: root.globalMargin }
                width: root.sidebarWidth - root.globalMargin * 2

                transform: Translate {
                    id: slide
                    x: sidebarRoot.shouldShow ? 0 : -(root.sidebarWidth + root.globalMargin) // per screen (see keyboardFocus)
                    Behavior on x {
                        enabled: !root.instantOpen
                        MotionSpring { token: GlobalStates.sidebarLeftOpen ? "liquid" : "settle" }
                    }
                }

                focus: sidebarRoot.shouldShow
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
