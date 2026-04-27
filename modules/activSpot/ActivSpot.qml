import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "root:"
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

/**
 * ActivSpot — dynamic-island-style overlay aggregating Mpris, Notifications,
 * Recording, and Clock/Weather. Compositor-agnostic: never reads HyprlandData
 * directly; all compositor state flows through CompositorService.
 *
 * Toggle:    Config.options.activSpot.enable
 * Position:  Config.options.activSpot.position ∈ {top, bottom, left, right}
 *            (invalid values fall back to "top")
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.activSpot?.enable ?? false
    readonly property string rawPosition: Config.options?.activSpot?.position ?? "top"
    readonly property string position: ["top", "bottom", "left", "right"].indexOf(rawPosition) >= 0
                                        ? rawPosition : "top"
    readonly property int widthPx: Config.options?.activSpot?.widthPx ?? 420
    readonly property int heightPx: Config.options?.activSpot?.heightPx ?? 36
    readonly property bool isVertical: position === "left" || position === "right"

    readonly property bool showMpris: Config.options?.activSpot?.showMpris ?? true
    readonly property bool showNotification: Config.options?.activSpot?.showNotification ?? true
    readonly property bool showRecording: Config.options?.activSpot?.showRecording ?? true
    readonly property bool showClockWeather: Config.options?.activSpot?.showClockWeather ?? true

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
            WlrLayershell.namespace: "quickshell:activspot"
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
                        ActivSpotMpris      { visible: root.showMpris && ActivSpotState.mpris !== null }
                        ActivSpotRecording  { visible: root.showRecording && ActivSpotState.recording.active }
                        ActivSpotNotification { Layout.fillWidth: true; visible: root.showNotification && ActivSpotState.latestNotification !== null }
                        ActivSpotClockWeather { visible: root.showClockWeather }
                    }
                }

                Component {
                    id: verticalLayout
                    ColumnLayout {
                        spacing: 10
                        ActivSpotMpris      { visible: root.showMpris && ActivSpotState.mpris !== null }
                        ActivSpotRecording  { visible: root.showRecording && ActivSpotState.recording.active }
                        ActivSpotNotification { Layout.fillHeight: true; visible: root.showNotification && ActivSpotState.latestNotification !== null }
                        ActivSpotClockWeather { visible: root.showClockWeather }
                    }
                }
            }
        }
    }
}
