import QtQuick
import QtQuick.Layouts
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

/**
 * Sidebar configuration — elaborate with widget enable/disable,
 * behavior tuning, and preview indicators.
 */
ColumnLayout {
    spacing: 16

    // ═══ Sidebar Behavior ═══
    SettingsCard {
        icon: "speed"
        title: "Sidebar Behavior"
        subtitle: "Animation, loading, and dismissal settings"

        ConfigSwitch {
            label: "Instant open (skip animation)"
            sublabel: "Sidebars appear immediately without slide-in transition"
            checked: Config.options?.sidebar?.instantOpen ?? false
            onCheckedChanged: Config.setNestedValue("sidebar.instantOpen", checked)
        }

        ConfigSwitch {
            label: "Keep left sidebar loaded"
            sublabel: "Faster re-open at the cost of ~20MB memory"
            checked: Config.options?.sidebar?.keepLeftSidebarLoaded ?? true
            onCheckedChanged: Config.setNestedValue("sidebar.keepLeftSidebarLoaded", checked)
        }

        ConfigSwitch {
            label: "Keep right sidebar loaded"
            sublabel: "Faster re-open at the cost of ~15MB memory"
            checked: Config.options?.sidebar?.keepRightSidebarLoaded ?? true
            onCheckedChanged: Config.setNestedValue("sidebar.keepRightSidebarLoaded", checked)
        }
    }

    // ═══ Left Sidebar ═══
    SettingsCard {
        icon: "view_sidebar"
        title: "Left Sidebar"
        subtitle: "AI Chat and Notifications panel"

        NoticeBox {
            text: "The left sidebar contains two tabs: AI Chat and Notifications with a compact media player. AI model configuration is in the Services page."
            iconName: "info"
        }
    }

    // ═══ Right Sidebar Widgets ═══
    SettingsCard {
        icon: "widgets"
        title: "Right Sidebar Widgets"
        subtitle: "Choose which modules appear in the right sidebar"

        // Widget toggles
        Repeater {
            model: [
                { key: "systemButtons", label: "System Buttons", sublabel: "Uptime, reload, settings, power", icon: "power_settings_new" },
                { key: "quickSliders", label: "Quick Sliders", sublabel: "Volume, brightness, microphone", icon: "tune" },
                { key: "quickToggles", label: "Quick Toggles", sublabel: "WiFi, Bluetooth, DND, Idle inhibit", icon: "toggle_on" },
                { key: "media", label: "Media Player", sublabel: "Compact media controls with vinyl art", icon: "music_note" },
                { key: "notifications", label: "Notifications", sublabel: "Recent notification list", icon: "notifications" },
                { key: "calendar", label: "Calendar", sublabel: "Month calendar grid", icon: "calendar_month" },
                { key: "systemInfo", label: "System Info", sublabel: "CPU/RAM/battery gauges + network speed", icon: "monitor_heart" },
            ]

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 12

                MaterialSymbol {
                    text: modelData.icon; iconSize: 20
                    color: Appearance?.colors.colPrimary ?? "#65558F"
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    StyledText { text: modelData.label; font.pixelSize: Appearance?.font.pixelSize.small ?? 14 }
                    StyledText { text: modelData.sublabel; font.pixelSize: Appearance?.font.pixelSize.smallest ?? 11; opacity: 0.4 }
                }
                StyledSwitch {
                    checked: (Config.options?.sidebar?.right?.enabledWidgets ?? [
                        "systemButtons", "quickSliders", "quickToggles", "media", "notifications", "calendar", "systemInfo"
                    ]).includes(modelData.key)
                    onCheckedChanged: {
                        const widgets = Config.options?.sidebar?.right?.enabledWidgets ?? [
                            "systemButtons", "quickSliders", "quickToggles", "media", "notifications", "calendar", "systemInfo"
                        ]
                        if (checked && !widgets.includes(modelData.key)) {
                            Config.setNestedValue("sidebar.right.enabledWidgets", [...widgets, modelData.key])
                        } else if (!checked && widgets.includes(modelData.key)) {
                            Config.setNestedValue("sidebar.right.enabledWidgets", widgets.filter(w => w !== modelData.key))
                        }
                    }
                }
            }
        }
    }

    // ═══ Quick Sliders ═══
    SettingsCard {
        icon: "tune"
        title: "Quick Sliders"
        subtitle: "Configure which sliders appear in the right sidebar"

        ConfigSwitch {
            label: "Show brightness slider"
            checked: Config.options?.sidebar?.quickSliders?.showBrightness ?? true
            onCheckedChanged: Config.setNestedValue("sidebar.quickSliders.showBrightness", checked)
        }

        ConfigSwitch {
            label: "Show volume slider"
            checked: Config.options?.sidebar?.quickSliders?.showVolume ?? true
            onCheckedChanged: Config.setNestedValue("sidebar.quickSliders.showVolume", checked)
        }

        ConfigSwitch {
            label: "Show microphone slider"
            sublabel: "Additional slider for microphone input volume"
            checked: Config.options?.sidebar?.quickSliders?.showMic ?? false
            onCheckedChanged: Config.setNestedValue("sidebar.quickSliders.showMic", checked)
        }
    }
}
