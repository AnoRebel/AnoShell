import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.networkOrbit

/**
 * Network Orbit: an animated network / Bluetooth / VPN panel, the
 * alternative to the inline pickers (network.panelStyle "orbit" makes the bar
 * and sidebar open it). Adapted from ilyamiro's NetworkPopup.
 *
 * Non-modal like the control panel: input only on the card, Escape closes
 * (or cancels a password prompt), Tab cycles the tabs.
 *
 *   ano ipc call networkOrbit toggle wifi      (wifi | bt | vpn | eth | "")
 */
Scope {
    id: root

    // The window stays mapped through the exit animation.
    property bool _mapped: GlobalStates.networkOrbitOpen

    Connections {
        target: GlobalStates
        function onNetworkOrbitOpenChanged() {
            if (GlobalStates.networkOrbitOpen) root._mapped = true
            else if (!content.item) root._mapped = false   // closed before it finished loading
        }
    }

    IpcHandler {
        target: "networkOrbit"
        function open(tab: string): void { GlobalStates.openNetworkOrbit(tab) }
        function close(): void { GlobalStates.networkOrbitOpen = false }
        function toggle(tab: string): void { GlobalStates.toggleNetworkOrbit(tab) }
    }

    PanelWindow {
        id: orbitWindow
        visible: root._mapped
        screen: GlobalStates.focusedScreen
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:networkOrbit"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.networkOrbitOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        mask: Region { x: card.x; y: card.y; width: card.width; height: card.height }
        anchors { top: true; bottom: true; left: true; right: true }

        Shortcut {
            sequence: "Escape"
            onActivated: {
                if (content.item && content.item.pendingWifiSsid !== "") content.item.pendingWifiSsid = ""
                else GlobalStates.networkOrbitOpen = false
            }
        }
        Shortcut { sequence: "Tab"; onActivated: content.item?.cycleMode() }

        PanelDragHandle { panelCard: card; key: "networkOrbit" }

        SurfaceMaterial {
            id: card
            surface: "networkOrbit"
            anchors.centerIn: parent
            width: Math.min(760, parent.width - 32)
            height: Math.min(600, parent.height - 32)
            radius: Appearance.rounding.windowRounding
            color: Appearance.m3colors.m3background
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true
            // The view drives the card's intro / exit (fade + slight scale).
            opacity: content.item?.cardOpacity ?? 0
            scale: content.item?.cardScale ?? 0.96

            // Deep content attaches a turn after the layer surface exists.
            Loader {
                id: content
                anchors.fill: parent
                asynchronous: true
                active: root._mapped
                sourceComponent: OrbitView {
                    shown: GlobalStates.networkOrbitOpen
                    onExited: root._mapped = false
                }
            }
        }
    }
}
