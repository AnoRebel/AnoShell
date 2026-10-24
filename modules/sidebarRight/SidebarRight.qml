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

            // The window stays mapped; closed, it is "parked": no input, no
            // focus, the content slid out of view. Mapping it on every open
            // cost a ~75 ms first frame, so the slide started with a jump.
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
                function onSidebarRightOpenChanged() {
                    if (sidebarRoot.shouldShow) { _closeTimer.stop(); sidebarRoot._ensureMapped(); sidebarRoot.parked = false }
                    else if (root.instantOpen) { _closeTimer.stop(); sidebarRoot.parked = true }
                    else _closeTimer.restart()
                }
            }
            // If focus moves between monitors while open, follow it.
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
                    if (GlobalStates.sidebarRightOpen
                        || Math.abs(Math.abs(slide.x) - sidebarRoot._slideAway) < 1) sidebarRoot.parked = true
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
                active: !sidebarRoot.parked && progress > 0
                x: (sidebarRoot.screen?.width ?? 0) - PanelRegistry.inset(_scr, "right") - root.sidebarWidth + root.globalMargin + slide.x
                readonly property string _scr: sidebarRoot.modelData?.name ?? ""
                y: sidebarRoot._insetTop + root.globalMargin
                w: root.sidebarWidth - root.globalMargin * 2
                h: (sidebarRoot.screen?.height ?? 0) - sidebarRoot._insetTop - sidebarRoot._insetBottom - root.globalMargin * 2
                progress: 1 - slide.x / Math.max(1, sidebarRoot._slideAway)
            }

            // Where the content starts and ends: past the bar's zone, but not
            // the pill's when the pill at its widest stays clear of the sidebar
            // (it then reaches the edge). Ignoring zones means placing past the
            // others by hand, which only the connected frame's registry knows.
            readonly property string _scr: sidebarRoot.modelData?.name ?? ""
            readonly property real _from: (sidebarRoot.screen?.width ?? 0) - root.sidebarWidth
            readonly property real _to: sidebarRoot.screen?.width ?? 0
            readonly property real _insetTop: PanelRegistry.insetBeside(_scr, "top", _from, _to)
            readonly property real _insetBottom: PanelRegistry.insetBeside(_scr, "bottom", _from, _to)
            readonly property bool _besidePill: PanelRegistry.enabled
                && (_insetTop < PanelRegistry.inset(_scr, "top") || _insetBottom < PanelRegistry.inset(_scr, "bottom"))
            exclusionMode: _besidePill ? ExclusionMode.Ignore : ExclusionMode.Normal
            // Fully past the screen edge (and the frame band there, when the window covers it).
            readonly property real _slideAway: root.sidebarWidth + root.globalMargin + (_besidePill ? PanelRegistry.inset(_scr, "right") : 0)
            exclusiveZone: 0
            implicitWidth: screen?.width ?? 1920
            WlrLayershell.namespace: "quickshell:sidebarRight"
            // Per screen: a parked copy on another monitor must not take the keyboard.
            WlrLayershell.keyboardFocus: sidebarRoot.shouldShow ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
                // Parked (closed, slid away): not drawn at all, so nothing in it renders.
                visible: !sidebarRoot.parked
                active: GlobalStates.sidebarRightOpen || (Config?.options?.sidebar?.keepRightSidebarLoaded ?? true)
                anchors {
                    top: parent.top; right: parent.right; bottom: parent.bottom
                    // Ignoring zones, the window covers the screen: add the insets.
                    topMargin: root.globalMargin + (sidebarRoot._besidePill ? sidebarRoot._insetTop : 0)
                    bottomMargin: root.globalMargin + (sidebarRoot._besidePill ? sidebarRoot._insetBottom : 0)
                    rightMargin: root.globalMargin + (sidebarRoot._besidePill ? PanelRegistry.inset(sidebarRoot._scr, "right") : 0)
                }
                width: root.sidebarWidth - root.globalMargin * 2

                transform: Translate {
                    id: slide
                    x: sidebarRoot.shouldShow ? 0 : sidebarRoot._slideAway // per screen (see keyboardFocus)
                    Behavior on x {
                        id: slideMotion
                        enabled: !root.instantOpen
                        MotionSpring { token: Math.abs(slideMotion.targetValue) < 0.5 ? "liquid" : "settle" }
                    }
                }

                focus: sidebarRoot.shouldShow
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
