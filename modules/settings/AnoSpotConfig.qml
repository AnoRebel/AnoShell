import QtQuick
import QtQuick.Layouts
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

/**
 * AnoSpot settings page — toggle, position selector (4-way), per-widget toggles,
 * and a non-blocking warning when bar.edge collides with anoSpot.position.
 */
ColumnLayout {
    id: root
    spacing: 16

    readonly property bool enabled: Config.options?.anoSpot?.enable ?? false
    readonly property string currentPosition: Config.options?.anoSpot?.position ?? "top"
    readonly property string barEdge: Config.options?.bars?.[0]?.edge ?? "top"
    readonly property bool collides: enabled && currentPosition === barEdge

    // ═══ Enable + collision warning ═══
    SettingsCard {
        icon: "view_compact_alt"
        title: "AnoSpot"
        subtitle: "Dynamic-island-style overlay for now playing, notifications, recording, clock"

        ConfigSwitch {
            label: "Enable AnoSpot"
            sublabel: "Compositor-agnostic. Works on Hyprland and Niri."
            checked: root.enabled
            onCheckedChanged: Config.setNestedValue("anoSpot.enable", checked)
        }

        Rectangle {
            visible: root.collides
            Layout.fillWidth: true
            implicitHeight: warningRow.implicitHeight + 16
            radius: Appearance?.rounding.small ?? 8
            color: Appearance?.colors.colSecondaryContainer ?? "#5d4037"
            border.width: 1
            border.color: Appearance?.colors.colSecondary ?? "#f9e2af"

            RowLayout {
                id: warningRow
                anchors.fill: parent
                anchors.margins: 8
                spacing: 10
                MaterialSymbol {
                    text: "warning"
                    iconSize: 18
                    color: Appearance?.colors.colSecondary ?? "#f9e2af"
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: `Heads-up: AnoSpot position (${root.currentPosition}) matches the bar edge — they may visually overlap.`
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 13
                    color: Appearance?.colors.colOnSecondaryContainer ?? "#fef9e7"
                }
            }
        }
    }

    // ═══ Position ═══
    SettingsCard {
        icon: "open_in_full"
        title: "Position"
        subtitle: "Which screen edge the overlay anchors to"

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 160

            Rectangle {
                anchors.centerIn: parent
                width: 200; height: 130
                radius: 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                border.width: 1
                border.color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"

                StyledText {
                    anchors.centerIn: parent
                    text: "Desktop"
                    font.pixelSize: 11
                    opacity: 0.3
                }

                Repeater {
                    model: [
                        { pos: "top",    x: 70, y: 6,   w: 60, h: 12 },
                        { pos: "bottom", x: 70, y: 112, w: 60, h: 12 },
                        { pos: "left",   x: 6,  y: 50,  w: 12, h: 30 },
                        { pos: "right",  x: 182, y: 50, w: 12, h: 30 }
                    ]

                    Rectangle {
                        required property var modelData
                        x: modelData.x; y: modelData.y
                        width: modelData.w; height: modelData.h
                        radius: Math.min(width, height) / 2
                        color: root.currentPosition === modelData.pos
                            ? Appearance?.colors.colPrimary ?? "#65558F"
                            : "transparent"
                        border.width: 1
                        border.color: root.currentPosition === modelData.pos
                            ? Appearance?.colors.colPrimary ?? "#65558F"
                            : Appearance?.colors.colOutlineVariant ?? "#44444488"
                        opacity: root.currentPosition === modelData.pos ? 1 : 0.3

                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.setNestedValue("anoSpot.position", modelData.pos)
                        }
                    }
                }
            }
        }
    }

    // ═══ Widgets ═══
    SettingsCard {
        icon: "widgets"
        title: "Widgets"
        subtitle: "Which slots to render"

        ConfigSwitch {
            label: "Now playing (Mpris)"
            checked: Config.options?.anoSpot?.showMpris ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showMpris", checked)
        }
        ConfigSwitch {
            label: "Latest notification"
            checked: Config.options?.anoSpot?.showNotification ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showNotification", checked)
        }
        ConfigSwitch {
            label: "Recording indicator"
            checked: Config.options?.anoSpot?.showRecording ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showRecording", checked)
        }
        ConfigSwitch {
            label: "Clock & weather"
            checked: Config.options?.anoSpot?.showClockWeather ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showClockWeather", checked)
        }
    }
}
