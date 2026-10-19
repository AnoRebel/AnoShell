import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.settings
import "."
/**
 * The Settings overlay window and its pages. Loaded by SettingsOverlay on
 * first open and released after it has been closed for a while, so none of
 * this (window + every page type) is compiled at shell startup.
 */
PanelWindow {
    id: settingsPanel
    visible: GlobalStates.settingsOpen

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    // Non-modal: no scrim, input only on the card (clicks elsewhere reach
    // your windows), keyboard focus when you interact with it.
    mask: Region { x: settingsCard.x; y: settingsCard.y; width: settingsCard.width; height: settingsCard.height }  // geometry: an item region keeps the scale-in size
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }

    // Settings card
    PanelDragHandle { panelCard: settingsCard; key: "settings" }

    SurfaceMaterial {
        id: settingsCard
        surface: "settings"
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
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
        Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

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
                        model: SettingsRegistry.pages

                        RippleButton {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 40
                            buttonRadius: Appearance?.rounding.small ?? 8
                            toggled: GlobalStates.settingsPage === index
                            colBackgroundToggled: Appearance?.colors.colSecondaryContainer ?? "#E8DEF8"

                            contentItem: RowLayout {
                                anchors { leftMargin: 12; rightMargin: 12 }
                                spacing: 8
                                MaterialSymbol {
                                    text: modelData.icon; iconSize: 20
                                    fill: GlobalStates.settingsPage === index ? 1 : 0
                                    color: GlobalStates.settingsPage === index ? Appearance?.m3colors.m3onSecondaryContainer : Appearance?.m3colors.m3onBackground
                                }
                                StyledText {
                                    text: modelData.name
                                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                                    Layout.fillWidth: true
                                }
                            }

                            onClicked: GlobalStates.settingsPage = index
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
                id: pageFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: contentColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: contentColumn
                    width: parent.width
                    anchors.margins: 20

                    Loader {
                        id: pageLoader
                        Layout.fillWidth: true
                        Layout.margins: 20
                        sourceComponent: {
                            switch (GlobalStates.settingsPage) {
                                case 0: return generalPage
                                case 1: return modulesPage
                                case 2: return barPage
                                case 3: return dockPage
                                case 4: return sidebarsPage
                                case 5: return anoSpotPage
                                case 6: return appearancePage
                                case 7: return overviewPage
                                case 8: return servicesPage
                                case 9: return displaysPage
                                case 10: return keybindsPage
                                case 11: return aboutPage
                                default: return generalPage
                            }
                        }
                    }
                }
            }
        }

        // ── Ctrl+K command palette ──────────────────────────────
        // Anchored over the settings card so the scrim covers the
        // whole panel without bleeding outside it.
        SettingsCommandPalette {
            anchors.fill: parent
            currentPage: GlobalStates.settingsPage
            pageCount: SettingsRegistry.pages.length
            flickable: pageFlickable
            activePageItem: pageLoader.item
            onPageRequested: idx => GlobalStates.settingsPage = idx
        }
    }

    // Shared keyboard navigation: Up/Down/Tab through pages, Ctrl+1..9
    // jump-to-page, Esc closes. Lives behind the visible card so it
    // doesn't intercept clicks but still receives focus when the panel
    // is open (WlrKeyboardFocus.Exclusive grants the panel the focus
    // chain).
    SettingsKeyHandler {
        anchors.fill: parent
        focus: settingsPanel.visible
        currentPage: GlobalStates.settingsPage
        pageCount: SettingsRegistry.pages.length
        onPageRequested: idx => GlobalStates.settingsPage = idx
        onCloseRequested: GlobalStates.settingsOpen = false
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
        id: displaysPage
        DisplaysPage {}
    }
    Component {
        id: keybindsPage
        KeybindsPage {}
    }
    Component {
        id: aboutPage
        AboutPage {}
    }
}
