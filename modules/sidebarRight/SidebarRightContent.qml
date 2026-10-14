import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "."

/**
 * Right sidebar content — system controls, quick toggles,
 * media player, volume/brightness sliders, calendar, system info.
 * Modules are configurable via Config.options.sidebar.right.enabledWidgets.
 */
Rectangle {
    id: root
    property var panelScreen: null
    property var brightnessMonitor: panelScreen ? Brightness.getMonitorForScreen(panelScreen) : null

    // In connected mode the AnoScreen frame shader ALREADY paints this sidebar's
    // fused surface (it's registered with PanelRegistry, so the shader fills its
    // whole body with the frame colour + draws the concave join). Painting our own
    // colLayer0 on top produces a second, slightly-inset background — the "double
    // background". Go transparent and let the frame show through, and drop the
    // border/rounding (the frame is the surface). Floating mode keeps the full
    // translucent card (compositor-blurred). Same rule as BarWindow / StyledPopup.
    readonly property bool connectedMode: PanelRegistry.enabled
    color: connectedMode ? "transparent" : (Appearance?.colors.colLayer0 ?? "#1C1B1F")
    radius: connectedMode ? 0 : (Appearance?.rounding.normal ?? 12)
    border.width: 0
    border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
    clip: true

    readonly property var enabledWidgets: Config.options?.sidebar?.right?.enabledWidgets ?? [
        "systemButtons", "quickSliders", "quickToggles", "networkDetail", "media", "notifications", "calendar", "systemInfo"
    ]

    StyledFlickable {
        anchors.fill: parent
        anchors.margins: 10
        contentHeight: mainColumn.implicitHeight
        clip: true

        ColumnLayout {
            id: mainColumn
            width: parent.width
            spacing: 10

            // ═══════════════════════════════════════
            // System button row (uptime + reload/settings/power)
            // ═══════════════════════════════════════
            Loader {
                Layout.fillWidth: true
                active: root.enabledWidgets.includes("systemButtons")
                visible: active
                sourceComponent: RowLayout {
                    spacing: 8

                    // Uptime pill
                    Rectangle {
                        implicitWidth: uptimeRow.implicitWidth + 20
                        implicitHeight: uptimeRow.implicitHeight + 8
                        radius: height / 2
                        color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

                        RowLayout {
                            id: uptimeRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol { text: "schedule"; iconSize: 18; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5" }
                            StyledText {
                                text: `Up ${DateTime.uptime}`
                                font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                                color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Action buttons (reload / settings / session)
                    RowLayout {
                        spacing: 4
                        ToolbarButton { iconName: "restart_alt"; iconSize: 18; toolTipText: "Reload shell"; onClicked: Quickshell.reload(true) }
                        ToolbarButton {
                            iconName: "settings"; iconSize: 18; toolTipText: "Settings"
                            onClicked: {
                                GlobalStates.sidebarRightOpen = false
                                GlobalStates.settingsOpen = true
                            }
                        }
                        ToolbarButton {
                            iconName: "power_settings_new"; iconSize: 18; toolTipText: "Session"
                            onClicked: {
                                GlobalStates.sidebarRightOpen = false
                                GlobalStates.sessionOpen = true
                            }
                        }
                    }

                    // Close pushed to the far end, separated from the action
                    // group (mirrors the left sidebar's close placement).
                    Item { implicitWidth: 12 }
                    ToolbarButton { iconName: "close"; iconSize: 18; toolTipText: "Close"; onClicked: GlobalStates.sidebarRightOpen = false }
                }
            }

            // ═══════════════════════════════════════
            // Quick sliders (Volume + Brightness)
            // ═══════════════════════════════════════
            Loader {
                Layout.fillWidth: true
                active: root.enabledWidgets.includes("quickSliders")
                visible: active
                sourceComponent: QuickSliders { brightnessMonitor: root.brightnessMonitor }
            }

            // ═══════════════════════════════════════
            // Quick toggles (WiFi, BT, DND, Idle, etc.)
            // ═══════════════════════════════════════
            Loader {
                Layout.fillWidth: true
                active: root.enabledWidgets.includes("quickToggles")
                visible: active
                sourceComponent: QuickToggles {}
            }

            // ═══════════════════════════════════════
            // Network detail (bandwidth + VPN)
            // ═══════════════════════════════════════
            Loader {
                Layout.fillWidth: true
                active: root.enabledWidgets.includes("networkDetail")
                visible: active
                sourceComponent: NetworkDetailPanel {}
            }

            // ═══════════════════════════════════════
            // Media player (compact)
            // ═══════════════════════════════════════
            Loader {
                Layout.fillWidth: true
                active: root.enabledWidgets.includes("media") && MprisController.activePlayer != null
                visible: active
                sourceComponent: CompactMediaPlayer {}
            }

            // ═══════════════════════════════════════
            // Notifications center
            // ═══════════════════════════════════════
            Loader {
                Layout.fillWidth: true
                active: root.enabledWidgets.includes("notifications")
                visible: active
                sourceComponent: NotificationCenter {}
            }

            // ═══════════════════════════════════════
            // Calendar
            // ═══════════════════════════════════════
            Loader {
                Layout.fillWidth: true
                active: root.enabledWidgets.includes("calendar")
                visible: active
                sourceComponent: Rectangle {
                    implicitHeight: calView.implicitHeight + 20
                    radius: Appearance?.rounding.normal ?? 12
                    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
                    CalendarView {
                        id: calView
                        anchors { fill: parent; margins: 10 }
                    }
                }
            }

            // ═══════════════════════════════════════
            // System info (CPU/RAM/Battery)
            // ═══════════════════════════════════════
            Loader {
                Layout.fillWidth: true
                active: root.enabledWidgets.includes("systemInfo")
                visible: active
                sourceComponent: SystemInfoPanel {}
            }
        }
    }
}
