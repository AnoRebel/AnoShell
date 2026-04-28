import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Settings overlay — floating panel over the shell.
 * Navigation rail on the left, content pages on the right.
 */
Scope {
    id: root
    property int currentPage: 0

    readonly property var pages: [
        { name: "General", icon: "tune" },
        { name: "Modules", icon: "extension" },
        { name: "Bar", icon: "dock_to_bottom" },
        { name: "Dock", icon: "space_dashboard" },
        { name: "Sidebars", icon: "view_sidebar" },
        { name: "AnoSpot", icon: "view_compact_alt" },
        { name: "Appearance", icon: "palette" },
        { name: "Overview", icon: "overview" },
        { name: "Services", icon: "cloud" },
        { name: "About", icon: "info" },
    ]

    PanelWindow {
        id: settingsPanel
        visible: GlobalStates.settingsOpen

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:settings"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }

        // Scrim
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: GlobalStates.settingsOpen ? 0.4 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }
            MouseArea { anchors.fill: parent; onClicked: GlobalStates.settingsOpen = false }
        }

        // Settings card
        Rectangle {
            id: settingsCard
            anchors.centerIn: parent
            width: Math.min(900, parent.width * 0.85)
            height: Math.min(700, parent.height * 0.85)
            radius: Appearance?.rounding.windowRounding ?? 20
            color: Appearance?.m3colors.m3background ?? "#1C1B1F"
            border.width: 1
            border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
            clip: true

            opacity: GlobalStates.settingsOpen ? 1 : 0
            scale: GlobalStates.settingsOpen ? 1 : 0.92
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // Navigation rail
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 200
                    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
                    radius: settingsCard.radius

                    ColumnLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 4

                        StyledText {
                            text: "Settings"
                            font.pixelSize: Appearance?.font.pixelSize.huger ?? 22
                            font.weight: Font.Bold
                            Layout.bottomMargin: 10
                        }

                        Repeater {
                            model: root.pages

                            RippleButton {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                implicitHeight: 40
                                buttonRadius: Appearance?.rounding.small ?? 8
                                toggled: root.currentPage === index
                                colBackgroundToggled: Appearance?.colors.colSecondaryContainer ?? "#E8DEF8"

                                contentItem: RowLayout {
                                    anchors { leftMargin: 12; rightMargin: 12 }
                                    spacing: 8
                                    MaterialSymbol {
                                        text: modelData.icon; iconSize: 20
                                        fill: root.currentPage === index ? 1 : 0
                                        color: root.currentPage === index ? Appearance?.m3colors.m3onSecondaryContainer : Appearance?.m3colors.m3onBackground
                                    }
                                    StyledText {
                                        text: modelData.name
                                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                                        Layout.fillWidth: true
                                    }
                                }

                                onClicked: root.currentPage = index
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // Reload button
                        RippleButton {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            buttonRadius: Appearance?.rounding.small ?? 8
                            contentItem: RowLayout {
                                spacing: 6
                                MaterialSymbol { text: "restart_alt"; iconSize: 18 }
                                StyledText { text: "Reload Shell"; font.pixelSize: Appearance?.font.pixelSize.smaller ?? 13 }
                            }
                            onClicked: Quickshell.reload(true)
                        }
                    }
                }

                // Content area
                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: contentColumn.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: contentColumn
                        width: parent.width
                        anchors.margins: 20

                        Loader {
                            Layout.fillWidth: true
                            Layout.margins: 20
                            sourceComponent: {
                                switch (root.currentPage) {
                                    case 0: return generalPage
                                    case 1: return modulesPage
                                    case 2: return barPage
                                    case 3: return dockPage
                                    case 4: return sidebarsPage
                                    case 5: return anoSpotPage
                                    case 6: return appearancePage
                                    case 7: return overviewPage
                                    case 8: return servicesPage
                                    case 9: return aboutPage
                                    default: return generalPage
                                }
                            }
                        }
                    }
                }
            }
        }

        Keys.onPressed: event => { if (event.key === Qt.Key_Escape) GlobalStates.settingsOpen = false }
    }

    // ═══════════════════════════════════════
    // Page components
    // ═══════════════════════════════════════

    Component {
        id: generalPage
        GeneralConfig {}
    }
    Component {
        id: modulesPage
        ModulesConfig {}
    }
    Component {
        id: barPage
        BarConfig {}
    }
    Component {
        id: dockPage
        DockConfig {}
    }
    Component {
        id: sidebarsPage
        SidebarsConfig {}
    }
    Component {
        id: anoSpotPage
        AnoSpotConfig {}
    }
    Component {
        id: appearancePage
        AppearanceConfig {}
    }
    Component {
        id: overviewPage
        OverviewConfig {}
    }
    Component {
        id: servicesPage
        ServicesConfig {}
    }
    Component {
        id: aboutPage
        AboutPage {}
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { GlobalStates.settingsOpen = !GlobalStates.settingsOpen }
        function open(): void { GlobalStates.settingsOpen = true }
        function close(): void { GlobalStates.settingsOpen = false }
    }
}
