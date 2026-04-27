import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "root:"
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

/**
 * AnoSpot — dynamic-island-style overlay aggregating Mpris, Notifications,
 * Recording, and Clock/Weather. Compositor-agnostic: never reads HyprlandData
 * directly; all compositor state flows through CompositorService.
 *
 * Toggle:    Config.options.anoSpot.enable
 * Position:  Config.options.anoSpot.position ∈ {top, bottom, left, right}
 *            (invalid values fall back to "top")
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.anoSpot?.enable ?? false
    readonly property string rawPosition: Config.options?.anoSpot?.position ?? "top"
    readonly property string position: ["top", "bottom", "left", "right"].indexOf(rawPosition) >= 0
                                        ? rawPosition : "top"
    readonly property int widthPx: Config.options?.anoSpot?.widthPx ?? 420
    readonly property int heightPx: Config.options?.anoSpot?.heightPx ?? 36
    readonly property bool isVertical: position === "left" || position === "right"

    readonly property bool showMpris: Config.options?.anoSpot?.showMpris ?? true
    readonly property bool showNotification: Config.options?.anoSpot?.showNotification ?? true
    readonly property bool showRecording: Config.options?.anoSpot?.showRecording ?? true
    readonly property bool showClockWeather: Config.options?.anoSpot?.showClockWeather ?? true

    readonly property var actions: Config.options?.anoSpot?.actions ?? ({})

    function _dispatchClick(button) {
        let target = "";
        if (button === Qt.LeftButton)        target = root.actions.leftClick   ?? "mediaControls";
        else if (button === Qt.RightButton)  target = root.actions.rightClick  ?? "controlPanel";
        else if (button === Qt.MiddleButton) target = root.actions.middleClick ?? "anoview";
        if (target.length > 0) {
            Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", target, "toggle"]);
        }
    }

    Variants {
        model: root.enabled ? Quickshell.screens : []

        PanelWindow {
            id: spotWindow
            required property var modelData
            screen: modelData

            visible: root.enabled
            color: "transparent"

            implicitWidth: root.isVertical ? root.heightPx : root.widthPx
            implicitHeight: root.isVertical ? root.widthPx : root.heightPx

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:anospot"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: root.position === "top" || root.isVertical
                bottom: root.position === "bottom" || root.isVertical
                left: root.position === "left" || !root.isVertical
                right: root.position === "right" || !root.isVertical
            }

            margins {
                top: root.position === "top" ? 6 : 0
                bottom: root.position === "bottom" ? 6 : 0
                left: root.position === "left" ? 6 : 0
                right: root.position === "right" ? 6 : 0
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: Math.min(width, height) / 2
                color: Appearance?.colors?.colLayer0 ?? "#1e1e2e"
                border.width: 1
                border.color: Appearance?.colors?.colOutlineVariant ?? "#444"
                opacity: 0.96

                // Click dispatcher — catches left/right/middle on the pill background.
                // Widget MouseAreas (e.g. AnoSpotMpris wheel handler) sit above this
                // and intercept their own events; unclaimed clicks fall through here.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => root._dispatchClick(mouse.button)
                }

                // Horizontal layout for top/bottom; vertical for left/right
                Loader {
                    anchors.fill: parent
                    anchors.margins: 6
                    sourceComponent: root.isVertical ? verticalLayout : horizontalLayout
                }

                Component {
                    id: horizontalLayout
                    RowLayout {
                        spacing: 10
                        AnoSpotMpris      { visible: root.showMpris && AnoSpotState.mpris !== null }
                        AnoSpotRecording  { visible: root.showRecording && AnoSpotState.recording.active }
                        AnoSpotNotification { Layout.fillWidth: true; visible: root.showNotification && AnoSpotState.latestNotification !== null }
                        AnoSpotClockWeather { visible: root.showClockWeather }
                    }
                }

                Component {
                    id: verticalLayout
                    ColumnLayout {
                        spacing: 10
                        AnoSpotMpris      { visible: root.showMpris && AnoSpotState.mpris !== null }
                        AnoSpotRecording  { visible: root.showRecording && AnoSpotState.recording.active }
                        AnoSpotNotification { Layout.fillHeight: true; visible: root.showNotification && AnoSpotState.latestNotification !== null }
                        AnoSpotClockWeather { visible: root.showClockWeather }
                    }
                }
            }
        }
    }
}
