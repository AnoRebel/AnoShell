import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * "Keep these display settings?" — shown on every screen while anod waits
 * for a risky display change (mode, scale, rotation, a monitor off) to be
 * confirmed. anod reverts on its own when the countdown ends, so this is
 * only the question; a crashed shell can't leave a bad mode behind.
 */
Scope {
    id: root

    property var pending: null       // anod's display_pending data
    property real deadline: 0        // ms since epoch
    property int left: 0

    Connections {
        target: Anod
        function onEvent(name, data) {
            if (name === "display_pending") {
                root.pending = data
                root.deadline = Date.now() + (data.seconds ?? 15) * 1000
                root.left = data.seconds ?? 15
            } else if (name === "display_confirmed" || name === "display_reverted") {
                root.pending = null
            }
        }
    }
    // Monitors plugged or unplugged: anod applies the profile saved for the
    // new set (display.outputsChanged) and we name it briefly.
    Connections {
        target: Quickshell
        function onScreensChanged() { profileDebounce.restart() }
    }
    Timer {
        id: profileDebounce
        interval: 1500 // let the compositor finish configuring the new output
        onTriggered: Anod.call("display.outputsChanged", {}, (r, e) => {
            if (r?.profile)
                Quickshell.execDetached(["notify-send", "-a", "AnoShell", "-u", "low", "-t", "2500", "Display profile", r.profile])
        })
    }
    Timer {
        running: root.pending !== null
        interval: 250
        repeat: true
        onTriggered: root.left = Math.max(0, Math.ceil((root.deadline - Date.now()) / 1000))
    }

    Variants {
        model: root.pending !== null ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: Qt.rgba(0, 0, 0, 0.35)
            WlrLayershell.namespace: "quickshell:displayConfirm"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            SurfaceMaterial {
                id: card
                surface: "displayConfirm"
                anchors.centerIn: parent
                width: Math.min(440, parent.width - 48)
                height: col.implicitHeight + 40
                radius: Appearance.rounding.large
                color: Appearance.m3colors.m3surfaceContainer
                focus: true
                Keys.onReturnPressed: Anod.call("display.confirm", {})
                Keys.onEscapePressed: Anod.call("display.revert", {})

                ColumnLayout {
                    id: col
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    spacing: 12
                    RowLayout {
                        spacing: 12
                        CircularProgress {
                            implicitSize: 44
                            value: root.left / Math.max(1, root.pending?.seconds ?? 15)
                            MaterialSymbol { anchors.centerIn: parent; text: "desktop_windows"; iconSize: 20 }
                        }
                        ColumnLayout {
                            spacing: 2
                            StyledText { text: "Keep these display settings?"; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold }
                            StyledText { text: `Going back to the previous ones in ${root.left} s`; color: Appearance.colors.colSubtext }
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        RippleButton { buttonText: "Revert"; onClicked: Anod.call("display.revert", {}) }
                        RippleButton {
                            buttonText: "Keep"
                            toggled: true // the primary action
                            onClicked: Anod.call("display.confirm", {})
                        }
                    }
                }
            }
        }
    }
}
