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

        ConfigSwitch {
            label: "Allow drag to reposition"
            sublabel: "Show a drag handle on the leading edge; releasing snaps to the nearest screen edge"
            checked: Config.options?.anoSpot?.draggable ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.draggable", checked)
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
        ConfigSwitch {
            label: "Workspace"
            sublabel: "Active workspace number/name (click → overview)"
            checked: Config.options?.anoSpot?.showWorkspace ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showWorkspace", checked)
        }
        ConfigSwitch {
            label: "Battery"
            sublabel: "Hidden automatically on desktops without a battery"
            checked: Config.options?.anoSpot?.showBattery ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showBattery", checked)
        }
    }

    // ═══ Event border animation ═══
    SettingsCard {
        icon: "auto_awesome"
        title: "Event border animation"
        subtitle: "Pulsing gradient halo when configured events occur"

        ConfigSwitch {
            id: borderEnable
            label: "Enable"
            checked: Config.options?.anoSpot?.eventBorder?.enable ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.eventBorder.enable", checked)
        }

        ConfigSlider {
            label: "Hold duration"
            sublabel: "How long the halo stays visible before fading out"
            from: 500; to: 5000; stepSize: 100
            value: Config.options?.anoSpot?.eventBorder?.holdMs ?? 1500
            valueText: `${Math.round(value)} ms`
            enabled: borderEnable.checked
            onValueChanged: Config.setNestedValue("anoSpot.eventBorder.holdMs", Math.round(value))
        }

        // ─── Per-event-type triggers ─────────────────────────────────────
        // Each switch toggles presence of its event-type string in the
        // anoSpot.eventBorder.events array.
        function _hasEvent(name) {
            const events = Config.options?.anoSpot?.eventBorder?.events ?? [];
            return events.indexOf(name) >= 0;
        }
        function _setEvent(name, on) {
            const current = (Config.options?.anoSpot?.eventBorder?.events ?? []).slice();
            const idx = current.indexOf(name);
            if (on && idx < 0) current.push(name);
            else if (!on && idx >= 0) current.splice(idx, 1);
            Config.setNestedValue("anoSpot.eventBorder.events", current);
        }

        ConfigSwitch {
            label: "On notification"
            checked: parent._hasEvent("notification")
            enabled: borderEnable.checked
            onCheckedChanged: parent._setEvent("notification", checked)
        }
        ConfigSwitch {
            label: "On track change"
            checked: parent._hasEvent("track")
            enabled: borderEnable.checked
            onCheckedChanged: parent._setEvent("track", checked)
        }
        ConfigSwitch {
            label: "On recording start/stop"
            checked: parent._hasEvent("recording")
            enabled: borderEnable.checked
            onCheckedChanged: parent._setEvent("recording", checked)
        }
        ConfigSwitch {
            label: "On workspace change"
            sublabel: "Fires often if you switch workspaces frequently"
            checked: parent._hasEvent("workspace")
            enabled: borderEnable.checked
            onCheckedChanged: parent._setEvent("workspace", checked)
        }
    }
}
