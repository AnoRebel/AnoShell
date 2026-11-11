import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "."

/**
 * Sidebar configuration — elaborate with widget enable/disable,
 * behavior tuning, and preview indicators.
 */
ColumnLayout {
    spacing: 16

    SettingsPageHeader {
        title: "Sidebars"
        subtitle: "Behavior, widget toggles, sliders"
        configRoots: ["sidebar", "notepad", "todo", "pomodoro", "stickyNotes", "screenTime", "scratchpad", "clock"]
    }

    // ═══ Sidebar Behavior ═══
    SettingsCard {
        icon: "speed"
        title: "Sidebar Behavior"
        subtitle: "Animation, loading, and dismissal settings"
        configKeys: ["sidebar.instantOpen", "sidebar.keepLeftSidebarLoaded", "sidebar.keepRightSidebarLoaded"]

        ConfigSwitch {
            label: "Instant open (skip animation)"
            configKey: "sidebar.instantOpen"
            sublabel: "Sidebars appear immediately without slide-in transition"
            checked: Config.options?.sidebar?.instantOpen ?? false
            onCheckedChanged: Config.setNestedValue("sidebar.instantOpen", checked)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ConfigSwitch {
                Layout.fillWidth: true
                label: "Keep left sidebar loaded"
                configKey: "sidebar.keepLeftSidebarLoaded"
                sublabel: "Faster re-open at the cost of ~20MB memory"
                checked: Config.options?.sidebar?.keepLeftSidebarLoaded ?? true
                onCheckedChanged: Config.setNestedValue("sidebar.keepLeftSidebarLoaded", checked)
            }
            RestartRequiredBadge {}
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ConfigSwitch {
                Layout.fillWidth: true
                label: "Keep right sidebar loaded"
                configKey: "sidebar.keepRightSidebarLoaded"
                sublabel: "Faster re-open at the cost of ~15MB memory"
                checked: Config.options?.sidebar?.keepRightSidebarLoaded ?? true
                onCheckedChanged: Config.setNestedValue("sidebar.keepRightSidebarLoaded", checked)
            }
            RestartRequiredBadge {}
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
        id: rightWidgetsCard
        icon: "widgets"
        title: "Right Sidebar Widgets"
        subtitle: "Choose which modules appear in the right sidebar"
        configKeys: ["sidebar.right"]

        readonly property var _enabled: Config.options?.sidebar?.right?.enabledWidgets ?? [
            "systemButtons", "quickSliders", "quickToggles", "media", "notifications", "calendar", "systemInfo"
        ]

        NoticeBox {
            visible: rightWidgetsCard._enabled.length === 0
            iconName: "warning"
            text: "Right sidebar is empty — re-enable at least one widget below or it won't render anything."
        }

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
                    // onToggled (user-driven only) — bind-time mutations
                    // never fire it, so the array can't be corrupted by
                    // initial-bind cascades like ModulesConfig had.
                    onToggled: {
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
        configKeys: ["sidebar.quickSliders"]
        // Sub-toggles only matter when the parent "Quick Sliders" widget
        // is enabled. Disable them visually rather than hide so the page
        // doesn't reflow when the parent toggle flips.
        readonly property bool _parentEnabled: rightWidgetsCard._enabled.includes("quickSliders")
        subtitle: _parentEnabled
            ? "Configure which sliders appear in the right sidebar"
            : "Enable the Quick Sliders widget above to use these"
        enabled: _parentEnabled

        ConfigSwitch {
            label: "Show brightness slider"
            configKey: "sidebar.quickSliders.showBrightness"
            checked: Config.options?.sidebar?.quickSliders?.showBrightness ?? true
            onCheckedChanged: Config.setNestedValue("sidebar.quickSliders.showBrightness", checked)
        }

        ConfigSwitch {
            label: "Show volume slider"
            configKey: "sidebar.quickSliders.showVolume"
            checked: Config.options?.sidebar?.quickSliders?.showVolume ?? true
            onCheckedChanged: Config.setNestedValue("sidebar.quickSliders.showVolume", checked)
        }

        ConfigSwitch {
            label: "Show microphone slider"
            configKey: "sidebar.quickSliders.showMic"
            sublabel: "Additional slider for microphone input volume"
            checked: Config.options?.sidebar?.quickSliders?.showMic ?? false
            onCheckedChanged: Config.setNestedValue("sidebar.quickSliders.showMic", checked)
        }
    }

    // ═══ Productivity ═══
    SettingsCard {
        icon: "task_alt"
        title: "Productivity"
        subtitle: "Notepad, to-do and pomodoro in the right sidebar; a sticky note on the desktop · all off by default"
        configKeys: ["notepad", "todo", "pomodoro", "stickyNotes", "screenTime", "scratchpad"]

        ConfigSwitch {
            label: "Notepad"; configKey: "notepad.enable"
            sublabel: "Tabs of text, kept in ~/.local/share/anoshell/notepad.json"
            checked: Config.options?.notepad?.enable ?? false
            onCheckedChanged: Config.setNestedValue("notepad.enable", checked)
        }
        ConfigSwitch {
            label: "To-do"; configKey: "todo.enable"
            sublabel: "Synced both ways with a todo.txt you can edit anywhere"
            checked: Config.options?.todo?.enable ?? false
            onCheckedChanged: Config.setNestedValue("todo.enable", checked)
        }
        ConfigSwitch {
            label: "Scratchpad & Pins"; configKey: "scratchpad.enable"
            sublabel: "Notes, to-do, clipboard and calendar in one panel that grows from the pill (Super+Y), with pinned commands and a prompt; uses the notepad and to-do even when they're off here"
            checked: Config.options?.scratchpad?.enable ?? false
            onCheckedChanged: Config.setNestedValue("scratchpad.enable", checked)
        }
        ConfigRow {
            visible: Config.options?.todo?.enable ?? false
            label: "todo.txt"; configKey: "todo.file"
            sublabel: "Empty: ~/.local/share/anoshell/todo.txt"
            StyledTextInput {
                boxed: true
                text: Config.options?.todo?.file ?? ""
                onEditingFinished: Config.setNestedValue("todo.file", text.trim())
                Layout.fillWidth: true
            }
        }
        ConfigSwitch {
            label: "Pomodoro and stopwatch"; configKey: "pomodoro.enable"
            sublabel: "Separate from Focus Time: no Do Not Disturb, no tracking"
            checked: Config.options?.pomodoro?.enable ?? false
            onCheckedChanged: Config.setNestedValue("pomodoro.enable", checked)
        }
        Repeater {
            model: [
                { key: "focusMinutes", label: "Focus", from: 5, to: 90 },
                { key: "breakMinutes", label: "Short break", from: 1, to: 30 },
                { key: "longBreakMinutes", label: "Long break", from: 5, to: 60 },
                { key: "cyclesBeforeLongBreak", label: "Focus sessions before a long break", from: 2, to: 8 }
            ]
            delegate: ConfigSlider {
                required property var modelData
                visible: Config.options?.pomodoro?.enable ?? false
                label: modelData.label
                configKey: `pomodoro.${modelData.key}`
                from: modelData.from; to: modelData.to; stepSize: 1
                value: Config.options?.pomodoro?.[modelData.key] ?? modelData.from
                onValueChanged: Config.setNestedValue(`pomodoro.${modelData.key}`, Math.round(value))
                valueText: modelData.key.endsWith("Minutes") ? `${Math.round(value)} min` : `${Math.round(value)}`
            }
        }
        ConfigSwitch {
            label: "Screen time"; configKey: "screenTime.enable"
            sublabel: "Time per app and window title, kept only on this machine (needs anod); idle and locked time isn't counted"
            checked: Config.options?.screenTime?.enable ?? false
            onCheckedChanged: Config.setNestedValue("screenTime.enable", checked)
        }
        ConfigSlider {
            visible: Config.options?.screenTime?.enable ?? false
            label: "Idle after"; configKey: "screenTime.idleSeconds"
            sublabel: "No input this long (and nothing playing) stops the count"
            from: 30; to: 600; stepSize: 30
            value: Config.options?.screenTime?.idleSeconds ?? 120
            onValueChanged: Config.setNestedValue("screenTime.idleSeconds", Math.round(value))
            valueText: Format.formatDuration(value * 1000)
        }
        ConfigSlider {
            visible: Config.options?.screenTime?.enable ?? false
            label: "Keep"; configKey: "screenTime.keepDays"
            sublabel: "Older days are deleted"
            from: 7; to: 365; stepSize: 1
            value: Config.options?.screenTime?.keepDays ?? 30
            onValueChanged: Config.setNestedValue("screenTime.keepDays", Math.round(value))
            valueText: `${Math.round(value)} days`
        }
        ConfigSlider {
            visible: Config.options?.screenTime?.enable ?? false
            label: "Daily limit"; configKey: "screenTime.dailyLimitMinutes"
            sublabel: "A notification when today's total reaches it (nothing is blocked)"
            from: 0; to: 720; stepSize: 15
            value: Config.options?.screenTime?.dailyLimitMinutes ?? 0
            onValueChanged: Config.setNestedValue("screenTime.dailyLimitMinutes", Math.round(value))
            valueText: Math.round(value) === 0 ? "off" : Format.formatDuration(value * 60000)
        }
        // Per-app limits: { appId: minutes }.
        ColumnLayout {
            id: appLimitsBox
            visible: Config.options?.screenTime?.enable ?? false
            Layout.fillWidth: true
            spacing: 4
            readonly property var limits: Config.options?.screenTime?.appLimits ?? ({})
            function setLimit(app, min) {
                const l = JSON.parse(JSON.stringify(appLimitsBox.limits))
                if (min > 0) l[app] = min; else delete l[app]
                Config.setNestedValue("screenTime.appLimits", l)
            }
            StyledText { text: "App limits"; font.weight: Font.DemiBold }
            Repeater {
                model: Object.keys(appLimitsBox.limits)
                delegate: RowLayout {
                    required property string modelData
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: `${modelData} — ${appLimitsBox.limits[modelData]} min a day`; elide: Text.ElideRight }
                    RippleButtonWithIcon { iconName: "delete"; buttonText: "Remove"; onClicked: appLimitsBox.setLimit(modelData, 0) }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ConfigTextInput { id: limitApp; Layout.fillWidth: true; placeholderText: "App id (as in the screen time card, e.g. firefox)" }
                ConfigTextInput { id: limitMin; Layout.preferredWidth: 90; placeholderText: "minutes" }
                RippleButton {
                    buttonText: "Add"
                    enabled: /^[A-Za-z0-9._-]+$/.test(limitApp.text.trim()) && parseInt(limitMin.text, 10) > 0
                    onClicked: { appLimitsBox.setLimit(limitApp.text.trim(), Math.min(1440, parseInt(limitMin.text, 10))); limitApp.text = ""; limitMin.text = "" }
                }
            }
        }
        ConfigSwitch {
            label: "Sticky note"; configKey: "stickyNotes.enable"
            sublabel: "On the desktop, kept in ~/.local/share/anoshell/sticky.md"
            checked: Config.options?.stickyNotes?.enable ?? false
            onCheckedChanged: Config.setNestedValue("stickyNotes.enable", checked)
        }
        ConfigSwitch {
            visible: Config.options?.stickyNotes?.enable ?? false
            label: "Click-through"; configKey: "stickyNotes.clickThrough"
            sublabel: "Clicks go to the windows below (its pin turns this off)"
            checked: Config.options?.stickyNotes?.clickThrough ?? false
            onCheckedChanged: Config.setNestedValue("stickyNotes.clickThrough", checked)
        }
    }

    // ═══ Clock ═══
    SettingsCard {
        icon: "alarm"
        title: "Clock"
        subtitle: "Alarms, world clocks, timer and stopwatch · middle-click the bar clock, or qs ipc call clock toggle"
        configKeys: ["clock"]

        ConfigSwitch {
            label: "Alarm sound"; configKey: "clock.alarmSound"
            sublabel: "Alarms and the timer play a sound (the sound theme's alarm-clock-elapsed) even though other shell sounds are off"
            checked: Config.options?.clock?.alarmSound ?? true
            onCheckedChanged: Config.setNestedValue("clock.alarmSound", checked)
        }
        ConfigSlider {
            label: "Snooze"; configKey: "clock.snoozeMinutes"
            from: 1; to: 30; stepSize: 1
            value: Config.options?.clock?.snoozeMinutes ?? 10
            onValueChanged: Config.setNestedValue("clock.snoozeMinutes", Math.round(value))
            valueText: `${Math.round(value)} min`
        }
        ConfigSlider {
            label: "Ring for"; configKey: "clock.ringMinutes"
            sublabel: "An unanswered alarm then stops and leaves a \"Missed alarm\" notification"
            from: 1; to: 30; stepSize: 1
            value: Config.options?.clock?.ringMinutes ?? 5
            onValueChanged: Config.setNestedValue("clock.ringMinutes", Math.round(value))
            valueText: `${Math.round(value)} min`
        }
        ConfigSwitch {
            label: "Next alarm on the lock screen"; configKey: "clock.showOnLock"
            checked: Config.options?.clock?.showOnLock ?? true
            onCheckedChanged: Config.setNestedValue("clock.showOnLock", checked)
        }
    }
}
