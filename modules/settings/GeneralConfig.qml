import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * General settings — elaborate with collapsible cards, detailed controls,
 * visual indicators, and comprehensive audio/battery/time/notification config.
 */
ColumnLayout {
    spacing: 16

    // ═══ Audio ═══
    SettingsCard {
        icon: "volume_up"
        title: "Audio"
        subtitle: "Volume protection, system sounds, and audio behavior"

        // Current volume indicator
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            CircularProgress {
                implicitSize: 48; lineWidth: 3
                value: Audio.sink?.audio?.volume ?? 0
                colPrimary: (Audio.sink?.audio?.volume ?? 0) > 1 ? Appearance?.m3colors.m3error ?? "#BA1A1A" : Appearance?.colors.colPrimary ?? "#65558F"
            }
            ColumnLayout {
                spacing: 2
                StyledText {
                    text: `${Math.round((Audio.sink?.audio?.volume ?? 0) * 100)}%`
                    font.pixelSize: Appearance?.font.pixelSize.large ?? 18
                    font.weight: Font.Bold
                    font.family: Appearance?.font.family.numbers ?? "monospace"
                }
                StyledText {
                    text: Audio.sink?.audio?.muted ? "Muted" : (Audio.friendlyDeviceName(Audio.sink) ?? "Default sink")
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    opacity: 0.5
                    elide: Text.ElideRight
                    Layout.maximumWidth: 200
                }
            }
            Item { Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.2 }

        ConfigSwitch {
            label: "Volume protection (Earbang guard)"
            sublabel: "Blocks sudden volume jumps that could damage hearing"
            checked: Config.options?.audio?.protection?.enable ?? false
            onCheckedChanged: Config.setNestedValue("audio.protection.enable", checked)
        }

        ConfigSlider {
            label: "Max allowed increase per step"
            sublabel: "Maximum % the volume can jump in a single change"
            from: 1; to: 50; stepSize: 1
            value: Config.options?.audio?.protection?.maxAllowedIncrease ?? 10
            onValueChanged: Config.setNestedValue("audio.protection.maxAllowedIncrease", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSlider {
            label: "Hard volume limit"
            sublabel: "Absolute maximum volume percentage (pavucontrol allows up to 153%)"
            from: 50; to: 200; stepSize: 5
            value: Config.options?.audio?.protection?.maxAllowed ?? 100
            onValueChanged: Config.setNestedValue("audio.protection.maxAllowed", Math.round(value))
            valueText: `${Math.round(value)}%`
        }
    }

    // ═══ Battery ═══
    SettingsCard {
        icon: "battery_full"
        title: "Battery"
        subtitle: "Warning thresholds, auto-suspend, and power notifications"
        visible: Battery.available

        // Live battery indicator
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            CircularProgress {
                implicitSize: 56; lineWidth: 4
                value: Battery.percentage
                colPrimary: Battery.isLow && !Battery.isCharging ? Appearance?.m3colors.m3error ?? "#BA1A1A"
                    : Battery.isCharging ? "#81C784" : Appearance?.colors.colPrimary ?? "#65558F"
            }
            ColumnLayout {
                spacing: 2
                RowLayout {
                    spacing: 4
                    StyledText {
                        text: `${Math.round(Battery.percentage * 100)}%`
                        font.pixelSize: Appearance?.font.pixelSize.huger ?? 24
                        font.weight: Font.Bold
                        font.family: Appearance?.font.family.numbers ?? "monospace"
                    }
                    MaterialSymbol {
                        text: Battery.isCharging ? "bolt" : ""
                        iconSize: 20; fill: 1; visible: Battery.isCharging
                        color: "#81C784"
                    }
                }
                StyledText {
                    text: Battery.isCharging ? "Charging" : "On battery"
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    opacity: 0.5
                }
            }
            Item { Layout.fillWidth: true }
            // Health indicator
            ColumnLayout {
                spacing: 2; visible: Battery.health > 0
                StyledText { text: "Health"; font.pixelSize: 11; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
                StyledText {
                    text: `${Math.round(Battery.health)}%`
                    font.pixelSize: Appearance?.font.pixelSize.normal ?? 16
                    font.weight: Font.DemiBold
                    font.family: Appearance?.font.family.numbers ?? "monospace"
                    color: Battery.health > 80 ? "#81C784" : Battery.health > 50 ? "#FFB74D" : Appearance?.m3colors.m3error ?? "#BA1A1A"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.2 }

        ConfigSlider {
            label: "Low battery warning"
            sublabel: "Show notification when battery drops below this level"
            from: 5; to: 50; stepSize: 5
            value: Config.options?.battery?.low ?? 20
            onValueChanged: Config.setNestedValue("battery.low", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSlider {
            label: "Critical battery warning"
            sublabel: "Urgent notification with sound"
            from: 3; to: 30; stepSize: 1
            value: Config.options?.battery?.critical ?? 10
            onValueChanged: Config.setNestedValue("battery.critical", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSlider {
            label: "Auto-suspend threshold"
            sublabel: "System suspends automatically below this level"
            from: 1; to: 15; stepSize: 1
            value: Config.options?.battery?.suspend ?? 5
            onValueChanged: Config.setNestedValue("battery.suspend", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSwitch {
            label: "Enable automatic suspend"
            sublabel: "Suspend the system when battery reaches the threshold above"
            checked: Config.options?.battery?.automaticSuspend ?? false
            onCheckedChanged: Config.setNestedValue("battery.automaticSuspend", checked)
        }

        ConfigSlider {
            label: "Full battery notification"
            sublabel: "Notify to unplug when charged above this level"
            from: 80; to: 100; stepSize: 1
            value: Config.options?.battery?.full ?? 100
            onValueChanged: Config.setNestedValue("battery.full", Math.round(value))
            valueText: `${Math.round(value)}%`
        }
    }

    // ═══ Time & Clock ═══
    SettingsCard {
        icon: "schedule"
        title: "Time & Clock"
        subtitle: "Clock format, date format, and second precision"

        // Live clock preview
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 56
            radius: Appearance?.rounding.small ?? 8
            color: Appearance?.colors.colLayer2 ?? "#2B2930"

            RowLayout {
                anchors.centerIn: parent; spacing: 12
                StyledText {
                    text: DateTime.time
                    font.pixelSize: Appearance?.font.pixelSize.huger ?? 28
                    font.weight: Font.Bold
                    font.family: Appearance?.font.family.numbers ?? "monospace"
                }
                StyledText {
                    text: "•"; font.pixelSize: 20; opacity: 0.3
                }
                StyledText {
                    text: DateTime.longDate
                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                    opacity: 0.6
                }
            }
        }

        ConfigRow {
            label: "Time format"
            sublabel: "Qt format: hh:mm (24h), h:mm AP (12h), hh:mm:ss (with seconds)"
            StyledTextInput {
                text: Config.options?.time?.format ?? "hh:mm"
                onEditingFinished: Config.setNestedValue("time.format", text)
                Layout.preferredWidth: 120
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }

        ConfigRow {
            label: "Short date format"
            StyledTextInput {
                text: Config.options?.time?.shortDateFormat ?? "dd/MM"
                onEditingFinished: Config.setNestedValue("time.shortDateFormat", text)
                Layout.preferredWidth: 120
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }

        ConfigRow {
            label: "Long date format"
            StyledTextInput {
                text: Config.options?.time?.dateFormat ?? "dddd, dd/MM"
                onEditingFinished: Config.setNestedValue("time.dateFormat", text)
                Layout.preferredWidth: 180
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }

        ConfigSwitch {
            label: "Second precision"
            sublabel: "Update clock every second (slightly more CPU usage)"
            checked: Config.options?.time?.secondPrecision ?? false
            onCheckedChanged: Config.setNestedValue("time.secondPrecision", checked)
        }
    }

    // ═══ Notifications ═══
    SettingsCard {
        icon: "notifications"
        title: "Notifications"
        subtitle: "Popup behavior, timeout, and sounds"

        ConfigSlider {
            label: "Auto-dismiss timeout"
            sublabel: "How long popup notifications stay visible"
            from: 1000; to: 30000; stepSize: 1000
            value: Config.options?.notifications?.timeout ?? 7000
            onValueChanged: Config.setNestedValue("notifications.timeout", Math.round(value))
            valueText: `${(Math.round(value) / 1000).toFixed(0)}s`
        }

        ConfigSwitch {
            label: "Battery sounds"
            sublabel: "Play sounds for charging, low battery, and full events"
            checked: Config.options?.sounds?.battery ?? true
            onCheckedChanged: Config.setNestedValue("sounds.battery", checked)
        }
    }

    // ═══ Interactions ═══
    SettingsCard {
        icon: "touch_app"
        title: "Scrolling & Interactions"
        subtitle: "Touchpad and mouse scroll speed"

        ConfigSwitch {
            label: "Faster touchpad scrolling"
            sublabel: "Enhanced scroll speed for high-res touchpads"
            checked: Config.options?.interactions?.scrolling?.fasterTouchpadScroll ?? false
            onCheckedChanged: Config.setNestedValue("interactions.scrolling.fasterTouchpadScroll", checked)
        }

        ConfigSlider {
            label: "Touchpad scroll factor"
            from: 10; to: 300; stepSize: 10
            value: Config.options?.interactions?.scrolling?.touchpadScrollFactor ?? 100
            onValueChanged: Config.setNestedValue("interactions.scrolling.touchpadScrollFactor", Math.round(value))
            valueText: `${Math.round(value)}`
        }

        ConfigSlider {
            label: "Mouse scroll factor"
            from: 10; to: 200; stepSize: 10
            value: Config.options?.interactions?.scrolling?.mouseScrollFactor ?? 50
            onValueChanged: Config.setNestedValue("interactions.scrolling.mouseScrollFactor", Math.round(value))
            valueText: `${Math.round(value)}`
        }
    }
}
