//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import "modules/common"
import "modules/common/widgets"
import "modules/settings"
import "services"

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

/**
 * Standalone settings window — launched separately from the shell via:
 *   qs -n -p ~/.config/quickshell/ano/settings.qml
 *
 * Uses the same config pages as the overlay (GeneralConfig, BarConfig, DockConfig, etc.)
 * but in a native ApplicationWindow instead of a layer-shell PanelWindow.
 * This allows editing settings even when the shell is not running.
 */
ShellRoot {
    id: settingsRoot

    // `ano atelier [type]` starts this with ANO_SETTINGS_PAGE=atelier ANO_ATELIER_TAB=<type>.
    property int currentPage: Quickshell.env("ANO_SETTINGS_PAGE") === "atelier" ? Math.max(0, SettingsRegistry.pages.findIndex(p => p.name === "Atelier")) : 0
    Component.onCompleted: {
        const tab = Quickshell.env("ANO_ATELIER_TAB") ?? ""
        if (Atelier.types.some(t => t.id === tab)) Atelier.tab = tab
        LockScreens.remote = true // the preview is the shell's, not this window's
    }

    readonly property var pages: SettingsRegistry.pages


    FloatingWindow {
        id: settingsWindow
        visible: true
        title: "Ano Shell Settings"
        color: Appearance?.m3colors.m3background ?? "#1C1B1F"

        implicitWidth: 960
        implicitHeight: 720

        // Shared keyboard navigation: Up/Down/Tab through pages, Ctrl+1..9
        // jump-to-page, Esc closes the window. focus: true so the handler
        // gets the activeFocusItem when the window opens.
        SettingsKeyHandler {
            id: keyHandler
            anchors.fill: parent
            focus: true
            currentPage: settingsRoot.currentPage
            pageCount: settingsRoot.pages.length
            onPageRequested: idx => settingsRoot.currentPage = idx
            onCloseRequested: Qt.quit()
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ─── Navigation rail ──────────────────────────────────────
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 220
                color: Appearance?.colors.colLayer1 ?? "#2B2930"

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 4

                    // Title
                    RowLayout {
                        Layout.bottomMargin: 12; spacing: 8
                        MaterialSymbol { text: "settings"; iconSize: 28; color: Appearance?.colors.colPrimary ?? "#65558F" }
                        StyledText {
                            text: "Settings"
                            font.pixelSize: Appearance?.font.pixelSize.huger ?? 22
                            font.weight: Font.Bold
                        }
                    }

                    SettingsSearchButton { Layout.bottomMargin: 6 }

                    // Page buttons
                    Repeater {
                        model: settingsRoot.pages

                        RippleButton {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: 42
                            buttonRadius: Appearance?.rounding.small ?? 8
                            toggled: settingsRoot.currentPage === index
                            colBackgroundToggled: Appearance?.colors.colSecondaryContainer ?? "#E8DEF8"

                            contentItem: RowLayout {
                                anchors { leftMargin: 14; rightMargin: 14 }
                                spacing: 10
                                MaterialSymbol {
                                    text: modelData.icon; iconSize: 20
                                    fill: settingsRoot.currentPage === index ? 1 : 0
                                    color: settingsRoot.currentPage === index
                                        ? Appearance?.m3colors.m3onSecondaryContainer ?? "#1D1B20"
                                        : Appearance?.m3colors.m3onBackground ?? "#E6E1E5"
                                }
                                StyledText {
                                    text: modelData.name
                                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                                    font.weight: settingsRoot.currentPage === index ? Font.DemiBold : Font.Normal
                                    Layout.fillWidth: true
                                }
                            }

                            onClicked: settingsRoot.currentPage = index
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Reload shell button
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        buttonRadius: Appearance?.rounding.small ?? 8
                        colBackground: Appearance?.colors.colLayer2 ?? "#2B2930"
                        contentItem: RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "restart_alt"; iconSize: 18 }
                            StyledText { text: "Reload Shell"; font.pixelSize: Appearance?.font.pixelSize.smaller ?? 13 }
                        }
                        onClicked: {
                            Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "shell", "reload"])
                        }
                    }

                    // Quit settings
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        buttonRadius: Appearance?.rounding.small ?? 8
                        contentItem: RowLayout {
                            spacing: 8
                            MaterialSymbol { text: "close"; iconSize: 18 }
                            StyledText { text: "Close"; font.pixelSize: Appearance?.font.pixelSize.smaller ?? 13 }
                        }
                        onClicked: Qt.quit()
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                color: Appearance?.colors.colOutlineVariant ?? "#44444488"
                opacity: 0.3
            }

            // ─── Content area ─────────────────────────────────────────
            StyledFlickable {
                id: pageFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: pageLoader.implicitHeight + 40
                clip: true

                Loader {
                    id: pageLoader
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }

                    sourceComponent: {
                        switch (settingsRoot.currentPage) {
                            case 0: return comp_general
                            case 1: return comp_modules
                            case 2: return comp_bar
                            case 3: return comp_dock
                            case 4: return comp_sidebars
                            case 5: return comp_anospot
                            case 6: return comp_appearance
                            case 7: return comp_overview
                            case 8: return comp_services
                            case 9: return comp_displays
                            case 10: return comp_keybinds
                            case 11: return comp_atelier
                            case 12: return comp_actions
                            case 13: return comp_about
                            default: return comp_general
                        }
                    }
                }
            }
        }

        // ── Ctrl+K command palette ──────────────────────────────────
        SettingsCommandPalette {
            anchors.fill: parent
            currentPage: settingsRoot.currentPage
            pageCount: settingsRoot.pages.length
            flickable: pageFlickable
            activePageItem: pageLoader.item
            focusReturn: keyHandler
            onPageRequested: idx => settingsRoot.currentPage = idx
        }
    }

    Component { id: comp_general; GeneralConfig {} }
    Component { id: comp_modules; ModulesConfig {} }
    Component { id: comp_bar; BarConfig {} }
    Component { id: comp_dock; DockConfig {} }
    Component { id: comp_sidebars; SidebarsConfig {} }
    Component { id: comp_anospot; AnoSpotConfig {} }
    Component { id: comp_appearance; AppearanceConfig {} }
    Component { id: comp_overview; OverviewConfig {} }
    Component { id: comp_services; ServicesConfig {} }
    Component { id: comp_displays; DisplaysPage {} }
    Component { id: comp_keybinds; KeybindsPage {} }
    Component { id: comp_atelier; AtelierPage {} }
    Component { id: comp_actions; ActionsPage {} }
    Component { id: comp_about; AboutPage {} }
}
