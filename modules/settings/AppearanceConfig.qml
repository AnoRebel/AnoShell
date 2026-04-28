import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Appearance settings — elaborate with color preview, bezel visualization,
 * animation controls, and wallpaper rotation config.
 */
ColumnLayout {
    spacing: 16

    // ═══ Theme Colors ═══
    SettingsCard {
        icon: "palette"
        title: "Theme Colors"
        subtitle: "Material You color scheme derived from your wallpaper"
        collapsible: true

        // Live color swatch grid
        GridLayout {
            Layout.fillWidth: true
            columns: 6; columnSpacing: 6; rowSpacing: 6

            Repeater {
                model: [
                    { name: "Primary", color: Appearance?.colors.colPrimary ?? "#65558F" },
                    { name: "On Primary", color: Appearance?.m3colors.m3onPrimary ?? "white" },
                    { name: "Secondary", color: Appearance?.colors.colSecondaryContainer ?? "#E8DEF8" },
                    { name: "Background", color: Appearance?.m3colors.m3background ?? "#1C1B1F" },
                    { name: "Surface", color: Appearance?.colors.colLayer0 ?? "#1C1B1F" },
                    { name: "Error", color: Appearance?.m3colors.m3error ?? "#BA1A1A" },
                    { name: "Layer 1", color: Appearance?.colors.colLayer1 ?? "#E5E1EC" },
                    { name: "Layer 2", color: Appearance?.colors.colLayer2 ?? "#2B2930" },
                    { name: "On Surface", color: Appearance?.m3colors.m3onBackground ?? "#E6E1E5" },
                    { name: "Outline", color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5" },
                    { name: "Tooltip", color: Appearance?.colors.colTooltip ?? "#3C4043" },
                    { name: "Shadow", color: Appearance?.colors.colShadow ?? "#000000" },
                ]

                ColumnLayout {
                    required property var modelData
                    spacing: 2

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 28
                        radius: 6
                        color: modelData.color
                        border.width: 1
                        border.color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            StyledToolTip { text: `${modelData.name}\n${modelData.color}` }
                        }
                    }
                    StyledText {
                        text: modelData.name
                        font.pixelSize: 9
                        opacity: 0.4
                        Layout.alignment: Qt.AlignHCenter
                        elide: Text.ElideRight
                        Layout.maximumWidth: parent.width
                    }
                }
            }
        }

        NoticeBox {
            text: "Colors are auto-generated from your wallpaper using Material You. To override, edit the theme JSON or add custom colors in config.json."
            iconName: "auto_awesome"
        }
    }

    // ═══ Fonts ═══
    SettingsCard {
        icon: "font_download"
        title: "Fonts"
        subtitle: "Font families used across the shell"
        expanded: false

        ConfigRow {
            label: "Expressive font"
            sublabel: "Used for stylized headings and accents"
            StyledTextInput {
                text: Config.options?.appearance?.fonts?.expressive ?? "Google Sans Flex"
                onEditingFinished: Config.setNestedValue("appearance.fonts.expressive", text)
                Layout.preferredWidth: 200
            }
        }

        NoticeBox {
            text: "Other fonts (main, numbers, title, monospace, reading) can be changed in config.json under appearance.fonts."
            iconName: "info"
        }
    }

    // ═══ Extra Background Tint ═══
    SettingsCard {
        icon: "tonality"
        title: "Background Tint"
        subtitle: "Apply extra color tinting to layer backgrounds"

        ConfigSwitch {
            label: "Extra background tint"
            sublabel: "Adds a subtle color overlay to surfaces for a warmer feel"
            checked: Config.options?.appearance?.extraBackgroundTint ?? false
            onCheckedChanged: Config.setNestedValue("appearance.extraBackgroundTint", checked)
        }
    }

    // ═══ Global Margin (Bezel) ═══
    SettingsCard {
        icon: "fullscreen"
        title: "Global Margin (Bezel)"
        subtitle: "Gap between all shell elements and screen edges"

        // Visual bezel preview
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 100

            Rectangle {
                anchors.centerIn: parent
                width: 180; height: 80
                radius: 4
                color: "transparent"
                border.width: 1; border.color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"

                // Inner content area (shows effect of bezel)
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Config.options?.appearance?.bezel ?? 0
                    radius: Appearance?.rounding.normal ?? 12
                    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
                    opacity: 0.6

                    StyledText {
                        anchors.centerIn: parent
                        text: `${Config.options?.appearance?.bezel ?? 0}px gap`
                        font.pixelSize: 11; opacity: 0.6
                    }
                }
            }
        }

        ConfigSlider {
            label: "Bezel size"
            sublabel: "Applied to bars, sidebars, and all overlay panels"
            from: 0; to: 24; stepSize: 1
            value: Config.options?.appearance?.bezel ?? 0
            onValueChanged: Config.setNestedValue("appearance.bezel", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
    }

    // ═══ Animations ═══
    SettingsCard {
        icon: "animation"
        title: "Animations"
        subtitle: "Enable/disable and control animation speed"

        ConfigSwitch {
            label: "Enable animations"
            sublabel: "Disable for better performance on low-end hardware"
            checked: Config.options?.animations?.enable ?? true
            onCheckedChanged: Config.setNestedValue("animations.enable", checked)
        }

        ConfigSlider {
            label: "Animation speed multiplier"
            sublabel: "1.0 = normal, 0.5 = faster, 2.0 = slower"
            from: 0.2; to: 3; stepSize: 0.1
            value: Config.options?.animations?.speed ?? 1
            onValueChanged: Config.setNestedValue("animations.speed", value)
            valueText: `${value.toFixed(1)}x`
        }
    }

    // ═══ Wallpaper Rotation ═══
    SettingsCard {
        icon: "image"
        title: "Wallpaper Rotation"
        subtitle: "Automatically cycle through wallpapers from a directory"

        ConfigSwitch {
            label: "Enable random wallpaper rotation"
            sublabel: "Periodically change wallpaper from a directory"
            checked: Config.options?.background?.randomize?.enable ?? false
            onCheckedChanged: Config.setNestedValue("background.randomize.enable", checked)
        }

        ConfigRow {
            label: "Wallpaper directory"
            sublabel: "Path to folder containing wallpapers (supports ~)"
            StyledTextInput {
                text: Config.options?.background?.randomize?.directory ?? "~/Pictures/Wallpapers"
                onEditingFinished: Config.setNestedValue("background.randomize.directory", text)
                Layout.fillWidth: true
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }

        ConfigSlider {
            label: "Rotation interval"
            sublabel: "Time between wallpaper changes"
            from: 30; to: 7200; stepSize: 30
            value: Config.options?.background?.randomize?.interval ?? 300
            onValueChanged: Config.setNestedValue("background.randomize.interval", Math.round(value))
            valueText: {
                const v = Math.round(value)
                if (v >= 3600) return `${(v / 3600).toFixed(1)}h`
                if (v >= 60) return `${Math.round(v / 60)}min`
                return `${v}s`
            }
        }
    }

    // ═══ Wallpaper Transitions ═══
    SettingsCard {
        icon: "swap_horiz"
        title: "Wallpaper Transitions"
        subtitle: "Animation when switching between wallpapers (from inir backdrop)"

        ConfigSwitch {
            label: "Enable wallpaper transitions"
            sublabel: "Smooth crossfade or slide when changing wallpapers"
            checked: Config.options?.background?.transition?.enable ?? true
            onCheckedChanged: Config.setNestedValue("background.transition.enable", checked)
        }

        ConfigRow {
            label: "Transition type"
            sublabel: "Visual style of the wallpaper change"
            ButtonGroup {
                buttons: [
                    GroupButton { label: "Crossfade"; toggled: (Config.options?.background?.transition?.type ?? "crossfade") === "crossfade"; onClicked: Config.setNestedValue("background.transition.type", "crossfade") },
                    GroupButton { label: "Slide"; toggled: (Config.options?.background?.transition?.type ?? "crossfade") === "slideRight"; onClicked: Config.setNestedValue("background.transition.type", "slideRight") },
                    GroupButton { label: "Zoom"; toggled: (Config.options?.background?.transition?.type ?? "crossfade") === "zoom"; onClicked: Config.setNestedValue("background.transition.type", "zoom") },
                    GroupButton { label: "None"; toggled: (Config.options?.background?.transition?.type ?? "crossfade") === "none"; onClicked: Config.setNestedValue("background.transition.type", "none") }
                ]
            }
        }

        ConfigSlider {
            label: "Transition duration"
            sublabel: "How long the crossfade/slide animation takes"
            from: 200; to: 2000; stepSize: 100
            value: Config.options?.background?.transition?.duration ?? 800
            onValueChanged: Config.setNestedValue("background.transition.duration", Math.round(value))
            valueText: `${Math.round(value)}ms`
        }

        ConfigRow {
            label: "Slide direction"
            sublabel: "Only applies to slide transition type"
            ButtonGroup {
                buttons: [
                    GroupButton { label: "→"; toggled: (Config.options?.background?.transition?.direction ?? "right") === "right"; onClicked: Config.setNestedValue("background.transition.direction", "right") },
                    GroupButton { label: "←"; toggled: (Config.options?.background?.transition?.direction ?? "right") === "left"; onClicked: Config.setNestedValue("background.transition.direction", "left") },
                    GroupButton { label: "↓"; toggled: (Config.options?.background?.transition?.direction ?? "right") === "down"; onClicked: Config.setNestedValue("background.transition.direction", "down") },
                    GroupButton { label: "↑"; toggled: (Config.options?.background?.transition?.direction ?? "right") === "up"; onClicked: Config.setNestedValue("background.transition.direction", "up") }
                ]
            }
        }
    }
}
