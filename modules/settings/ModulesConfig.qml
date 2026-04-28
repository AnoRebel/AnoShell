import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Modules configuration — master enable/disable panel for every shell module.
 * Also includes OSD indicator toggles, screen corner actions, alt-switcher,
 * task view, search, control panel, apps, compositor, and advanced settings.
 */
ColumnLayout {
    id: root
    spacing: 16

    // ═══ Panel Modules Enable/Disable ═══
    SettingsCard {
        icon: "extension"
        title: "Enabled Modules"
        subtitle: "Toggle individual shell modules on and off"
        collapsible: false

        readonly property var allModules: [
            { id: "anoBar", name: "Bar", icon: "dock_to_bottom", desc: "Status bar with configurable modules" },
            { id: "anoOverview", name: "AnoView Overview", icon: "overview", desc: "Window overview with 10 layout algorithms" },
            { id: "anoNotificationPopup", name: "Notification Popups", icon: "notifications", desc: "Floating notification bubbles" },
            { id: "anoOnScreenDisplay", name: "OSD", icon: "volume_up", desc: "Volume/brightness/media indicators" },
            { id: "anoSessionScreen", name: "Session Screen", icon: "power_settings_new", desc: "Lock/logout/suspend/reboot/shutdown" },
            { id: "anoSidebarLeft", name: "Left Sidebar", icon: "view_sidebar", desc: "AI Chat, Notifications, Translator" },
            { id: "anoSidebarRight", name: "Right Sidebar", icon: "view_sidebar", desc: "Quick controls, media, calendar, system info" },
            { id: "anoWallpaperSelector", name: "Wallpaper Selector", icon: "image", desc: "Browse and apply wallpapers" },
            { id: "anoCheatsheet", name: "Keybind Cheatsheet", icon: "keyboard", desc: "Searchable keyboard shortcuts" },
            { id: "anoScreenCorners", name: "Hot Corners", icon: "fullscreen", desc: "Screen corner triggers" },
            { id: "anoSettings", name: "Settings Overlay", icon: "settings", desc: "This settings panel" },
            { id: "anoFamilyTransition", name: "Family Transition", icon: "swap_horiz", desc: "Panel family switch animation" },
            { id: "anoDock", name: "Dock", icon: "space_dashboard", desc: "Application dock with pinned apps" },
            { id: "anoClipboard", name: "Clipboard Manager", icon: "content_paste", desc: "Clipboard history browser" },
            { id: "anoAltSwitcher", name: "Alt-Tab Switcher", icon: "tab", desc: "Window switcher with thumbnails" },
            { id: "anoSearch", name: "App Launcher", icon: "search", desc: "Application search and launch" },
            { id: "anoTaskView", name: "Task View", icon: "view_comfy", desc: "Current workspace window view" },
            { id: "anoMediaControls", name: "Media Controls", icon: "music_note", desc: "Full media player panel" },
            { id: "anoControlPanel", name: "Control Panel", icon: "tune", desc: "Quick-access system controls" },
            { id: "anoWeatherPanel", name: "Weather Panel", icon: "thermostat", desc: "Detailed weather information" },
            { id: "anoLockScreen", name: "Lock Screen", icon: "lock", desc: "Niri lock screen (Hyprland uses hyprlock)" },
            { id: "anoHUD", name: "HUD", icon: "dashboard", desc: "System dashboard overlay" },
            { id: "anoFocusTime", name: "Focus Time", icon: "timer", desc: "App usage tracker with daily/weekly stats" },
            { id: "anoDisplayManager", name: "Display Manager", icon: "desktop_windows", desc: "Monitor configuration (Hyprland only)" },
        ]

        Repeater {
            model: allModules

            RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 12

                Rectangle {
                    width: 32; height: 32; radius: 8
                    color: Qt.rgba((Appearance?.colors.colPrimary ?? "#65558F").r, (Appearance?.colors.colPrimary ?? "#65558F").g, (Appearance?.colors.colPrimary ?? "#65558F").b, 0.12)
                    MaterialSymbol { anchors.centerIn: parent; text: modelData.icon; iconSize: 18; color: Appearance?.colors.colPrimary ?? "#65558F" }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    StyledText { text: modelData.name; font.pixelSize: Appearance?.font.pixelSize.small ?? 14 }
                    StyledText { text: modelData.desc; font.pixelSize: Appearance?.font.pixelSize.smallest ?? 10; opacity: 0.4; Layout.fillWidth: true; elide: Text.ElideRight }
                }

                StyledSwitch {
                    checked: (Config.options?.enabledPanels ?? []).includes(modelData.id) || (Config.options?.enabledPanels ?? []).length === 0
                    onCheckedChanged: {
                        let panels = [...(Config.options?.enabledPanels ?? [])]
                        if (panels.length === 0) {
                            // First time — populate from defaults
                            panels = root.parent.allModules.map(m => m.id)
                        }
                        if (checked && !panels.includes(modelData.id)) panels.push(modelData.id)
                        else if (!checked) panels = panels.filter(p => p !== modelData.id)
                        Config.setNestedValue("enabledPanels", panels)
                    }
                }
            }
        }
    }

    // ═══ OSD Indicators ═══
    SettingsCard {
        icon: "volume_up"
        title: "OSD Indicators"
        subtitle: "Choose which on-screen display indicators are shown"

        ConfigSlider {
            label: "Auto-hide timeout"
            sublabel: "How long the OSD pill stays visible"
            from: 500; to: 5000; stepSize: 250
            value: Config.options?.osd?.timeout ?? 1500
            onValueChanged: Config.setNestedValue("osd.timeout", Math.round(value))
            valueText: `${(Math.round(value) / 1000).toFixed(1)}s`
        }

        ConfigRow {
            label: "OSD position"
            ButtonGroup {
                buttons: [
                    GroupButton { label: "Top"; toggled: (Config.options?.osd?.position ?? "bottom") === "top"; onClicked: Config.setNestedValue("osd.position", "top") },
                    GroupButton { label: "Bottom"; toggled: (Config.options?.osd?.position ?? "bottom") === "bottom"; onClicked: Config.setNestedValue("osd.position", "bottom") }
                ]
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        Repeater {
            model: [
                { key: "volume", label: "Volume changes", icon: "volume_up" },
                { key: "brightness", label: "Brightness changes", icon: "brightness_6" },
                { key: "mic", label: "Microphone mute", icon: "mic" },
                { key: "media", label: "Media track changes", icon: "music_note" },
                { key: "keyboard", label: "Keyboard layout switch", icon: "keyboard" },
                { key: "network", label: "Network status changes", icon: "wifi" },
            ]

            RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 12
                MaterialSymbol { text: modelData.icon; iconSize: 18; color: Appearance?.colors.colPrimary ?? "#65558F" }
                StyledText { text: modelData.label; font.pixelSize: Appearance?.font.pixelSize.small ?? 14; Layout.fillWidth: true }
                StyledSwitch {
                    checked: Config.options?.osd?.indicators?.[modelData.key] ?? true
                    onCheckedChanged: Config.setNestedValue(`osd.indicators.${modelData.key}`, checked)
                }
            }
        }
    }

    // ═══ Screen Corners ═══
    SettingsCard {
        icon: "fullscreen"
        title: "Hot Screen Corners"
        subtitle: "Trigger actions by moving cursor to screen corners"

        ConfigSwitch {
            label: "Enable hot corners"
            checked: Config.options?.screenCorners?.enable ?? false
            onCheckedChanged: Config.setNestedValue("screenCorners.enable", checked)
        }

        ConfigSlider {
            label: "Dwell time"
            sublabel: "How long cursor must stay in corner before activation"
            from: 100; to: 1500; stepSize: 50
            value: Config.options?.screenCorners?.dwellMs ?? 300
            onValueChanged: Config.setNestedValue("screenCorners.dwellMs", Math.round(value))
            valueText: `${Math.round(value)}ms`
        }

        ConfigSlider {
            label: "Hit zone size"
            sublabel: "Size of the invisible corner trigger area in pixels"
            from: 1; to: 10; stepSize: 1
            value: Config.options?.screenCorners?.hitSize ?? 2
            onValueChanged: Config.setNestedValue("screenCorners.hitSize", Math.round(value))
            valueText: `${Math.round(value)}px`
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        // Corner action selectors
        readonly property var cornerActions: [
            { id: "sidebarLeftOpen", label: "Left Sidebar" },
            { id: "sidebarRightOpen", label: "Right Sidebar" },
            { id: "overviewOpen", label: "Overview" },
            { id: "settingsOpen", label: "Settings" },
            { id: "hudVisible", label: "HUD" },
            { id: "searchOpen", label: "App Launcher" },
            { id: "clipboardOpen", label: "Clipboard" },
            { id: "controlPanelOpen", label: "Control Panel" },
            { id: "", label: "None" },
        ]

        Repeater {
            model: [
                { corner: "topLeft", label: "Top Left", icon: "north_west" },
                { corner: "topRight", label: "Top Right", icon: "north_east" },
                { corner: "bottomLeft", label: "Bottom Left", icon: "south_west" },
                { corner: "bottomRight", label: "Bottom Right", icon: "south_east" },
            ]

            ConfigRow {
                required property var modelData
                label: modelData.label

                RowLayout {
                    spacing: 3
                    Repeater {
                        model: cornerActions
                        GroupButton {
                            required property var modelData
                            label: modelData.label
                            showLabel: true
                            toggled: (Config.options?.screenCorners?.actions?.[parent.parent.parent.modelData.corner] ?? "") === modelData.id
                            onClicked: Config.setNestedValue(`screenCorners.actions.${parent.parent.parent.modelData.corner}`, modelData.id)
                            implicitHeight: 28
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }

    // ═══ Alt-Switcher ═══
    SettingsCard {
        icon: "tab"
        title: "Alt-Tab Window Switcher"
        subtitle: "Window switching overlay appearance and behavior"

        ConfigSwitch {
            label: "Enable animations"
            checked: Config.options?.altSwitcher?.enableAnimation ?? true
            onCheckedChanged: Config.setNestedValue("altSwitcher.enableAnimation", checked)
        }

        ConfigSlider {
            label: "Animation duration"
            from: 50; to: 500; stepSize: 25
            value: Config.options?.altSwitcher?.animationDurationMs ?? 200
            onValueChanged: Config.setNestedValue("altSwitcher.animationDurationMs", Math.round(value))
            valueText: `${Math.round(value)}ms`
        }

        ConfigSwitch {
            label: "Most recent first (MRU)"
            sublabel: "Order windows by most recently used instead of creation order"
            checked: Config.options?.altSwitcher?.useMostRecentFirst ?? true
            onCheckedChanged: Config.setNestedValue("altSwitcher.useMostRecentFirst", checked)
        }

        ConfigSwitch {
            label: "Compact style"
            sublabel: "Smaller thumbnails, more windows visible"
            checked: Config.options?.altSwitcher?.compactStyle ?? false
            onCheckedChanged: Config.setNestedValue("altSwitcher.compactStyle", checked)
        }

        ConfigSlider {
            label: "Background opacity"
            from: 0.3; to: 1.0; stepSize: 0.05
            value: Config.options?.altSwitcher?.backgroundOpacity ?? 0.85
            onValueChanged: Config.setNestedValue("altSwitcher.backgroundOpacity", value)
            valueText: `${Math.round(value * 100)}%`
        }

        ConfigSlider {
            label: "Scrim dimming"
            from: 0; to: 80; stepSize: 5
            value: Config.options?.altSwitcher?.scrimDim ?? 40
            onValueChanged: Config.setNestedValue("altSwitcher.scrimDim", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSlider {
            label: "Max visible windows"
            from: 4; to: 30; stepSize: 1
            value: Config.options?.altSwitcher?.maxVisible ?? 12
            onValueChanged: Config.setNestedValue("altSwitcher.maxVisible", Math.round(value))
            valueText: `${Math.round(value)}`
        }
    }

    // ═══ Task View ═══
    SettingsCard {
        icon: "view_comfy"
        title: "Task View"
        subtitle: "Current workspace window layout"

        ConfigRow {
            label: "Layout algorithm"
            sublabel: "How windows are arranged in task view"
            ButtonGroup {
                buttons: [
                    GroupButton { label: "Hero"; toggled: (Config.options?.taskView?.layout ?? "hero") === "hero"; onClicked: Config.setNestedValue("taskView.layout", "hero") },
                    GroupButton { label: "Grid"; toggled: (Config.options?.taskView?.layout ?? "hero") === "smartgrid"; onClicked: Config.setNestedValue("taskView.layout", "smartgrid") },
                    GroupButton { label: "Justified"; toggled: (Config.options?.taskView?.layout ?? "hero") === "justified"; onClicked: Config.setNestedValue("taskView.layout", "justified") },
                    GroupButton { label: "Masonry"; toggled: (Config.options?.taskView?.layout ?? "hero") === "masonry"; onClicked: Config.setNestedValue("taskView.layout", "masonry") }
                ]
            }
        }
    }

    // ═══ App Launcher / Search ═══
    SettingsCard {
        icon: "search"
        title: "App Launcher"
        subtitle: "Application search and recent apps"
        expanded: false

        NoticeBox {
            text: "Recent apps are tracked automatically. Clear history by removing entries from config.json search.recentApps array."
            iconName: "info"
        }
    }

    // ═══ Default Applications ═══
    SettingsCard {
        icon: "apps"
        title: "Default Applications"
        subtitle: "Preferred applications for various actions"

        ConfigRow {
            label: "Terminal"
            StyledTextInput {
                text: Config.options?.apps?.terminal ?? "kitty"
                onEditingFinished: Config.setNestedValue("apps.terminal", text)
                Layout.preferredWidth: 160
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }
        ConfigRow {
            label: "File Manager"
            StyledTextInput {
                text: Config.options?.apps?.fileManager ?? "nemo"
                onEditingFinished: Config.setNestedValue("apps.fileManager", text)
                Layout.preferredWidth: 160
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }
        ConfigRow {
            label: "Browser"
            StyledTextInput {
                text: Config.options?.apps?.browser ?? "zen-browser"
                onEditingFinished: Config.setNestedValue("apps.browser", text)
                Layout.preferredWidth: 160
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }
    }

    // ═══ Compositor ═══
    SettingsCard {
        icon: "computer"
        title: "Compositor"
        subtitle: "Wayland compositor settings"
        expanded: false

        ConfigRow {
            label: "Current compositor"
            StyledText { text: CompositorService.compositor; font.family: Appearance?.font.family.mono ?? "monospace"; font.weight: Font.DemiBold }
        }

        ConfigRow {
            label: "Default compositor"
            sublabel: "Fallback when auto-detection fails"
            StyledTextInput {
                text: Config.options?.compositor?.defaultCompositor ?? "hyprland"
                onEditingFinished: Config.setNestedValue("compositor.defaultCompositor", text)
                Layout.preferredWidth: 120
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }

        ConfigRow {
            label: "Primary monitor"
            sublabel: "Leave empty for auto"
            StyledTextInput {
                text: Config.options?.display?.primaryMonitor ?? ""
                onEditingFinished: Config.setNestedValue("display.primaryMonitor", text)
                Layout.preferredWidth: 160
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }
    }

    // ═══ Panel Families ═══
    SettingsCard {
        icon: "swap_horiz"
        title: "Panel Families"
        subtitle: "Switch between different shell presets — changes which modules are active"
        collapsible: false

        readonly property string currentFamily: Config.options?.panelFamily ?? "ano"
        readonly property var familyDefs: [
            {
                id: "ano", name: "Ano (Full)", icon: "terminal",
                desc: "Everything enabled — bar, dock, sidebars, HUD, AI chat, overview, clipboard, hot corners, all overlays. The complete experience.",
                color: "#65558F"
            },
            {
                id: "minimal", name: "Minimal", icon: "remove_circle_outline",
                desc: "Bar + essential overlays only. No dock, no sidebars, no HUD, no hot corners. Lightweight shell for minimal setups.",
                color: "#42A5F5"
            },
            {
                id: "hefty", name: "Hefty", icon: "auto_awesome",
                desc: "Full experience + morphing bar panels. Bars use polygon ShapeCanvas backgrounds that morph into popout detail panels. The hefty-hype-inspired mode.",
                color: "#FFB74D"
            },
            {
                id: "clean", name: "Clean", icon: "spa",
                desc: "Bar + sidebars + essentials. No dock, no hot corners. A focused middle ground for distraction-free work.",
                color: "#81C784"
            }
        ]

        // Family selector cards
        GridLayout {
            Layout.fillWidth: true
            columns: 2; columnSpacing: 10; rowSpacing: 10

            Repeater {
                model: familyDefs

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: familyCardCol.implicitHeight + 20
                    radius: Appearance?.rounding.normal ?? 12
                    color: currentFamily === modelData.id
                        ? Qt.rgba(modelData.color.r ?? 0.4, modelData.color.g ?? 0.33, modelData.color.b ?? 0.56, 0.15)
                        : Appearance?.colors.colLayer2 ?? "#2B2930"
                    border.width: currentFamily === modelData.id ? 2 : 1
                    border.color: currentFamily === modelData.id
                        ? modelData.color
                        : Appearance?.colors.colOutlineVariant ?? "#44444488"

                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    scale: familyMA.pressed ? 0.96 : (familyMA.containsMouse ? 1.02 : 1)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        id: familyCardCol
                        anchors { fill: parent; margins: 10 }
                        spacing: 6

                        RowLayout {
                            spacing: 8
                            Rectangle {
                                width: 32; height: 32; radius: 16
                                color: Qt.rgba(modelData.color.r ?? 0.4, modelData.color.g ?? 0.33, modelData.color.b ?? 0.56, 0.2)
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: modelData.icon; iconSize: 18
                                    color: modelData.color
                                    fill: currentFamily === modelData.id ? 1 : 0
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                StyledText {
                                    text: modelData.name
                                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                                    font.weight: Font.DemiBold
                                    color: currentFamily === modelData.id ? modelData.color : Appearance?.m3colors.m3onBackground ?? "#E6E1E5"
                                }
                                Loader {
                                    active: currentFamily === modelData.id; visible: active
                                    sourceComponent: StyledText {
                                        text: "Active"
                                        font.pixelSize: 10; color: modelData.color
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }

                        StyledText {
                            text: modelData.desc
                            font.pixelSize: Appearance?.font.pixelSize.smallest ?? 10
                            opacity: 0.5
                            wrapMode: Text.Wrap
                            Layout.fillWidth: true
                        }
                    }

                    MouseArea {
                        id: familyMA
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (currentFamily !== modelData.id) {
                                // Use IPC to trigger family transition with animation
                                Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "panelFamily", "set", modelData.id])
                            }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        ConfigSwitch {
            label: "Family transition animation"
            sublabel: "Animated ripple effect when switching between panel families"
            checked: Config.options?.familyTransitionAnimation ?? true
            onCheckedChanged: Config.setNestedValue("familyTransitionAnimation", checked)
        }

        NoticeBox {
            text: "Switching families changes which modules are enabled and may toggle settings like morphing panels. Use Ctrl+Super+P to cycle families via keyboard."
            iconName: "info"
        }
    }

    // ═══ Focus Time ═══
    SettingsCard {
        icon: "timer"
        title: "Focus Time"
        subtitle: "App usage tracking with daily and weekly statistics"

        ConfigSwitch {
            label: "Enable Focus Time"
            sublabel: "Track time spent in each application"
            checked: Config.options?.focusTime?.enable ?? true
            onCheckedChanged: Config.setNestedValue("focusTime.enable", checked)
        }

        ConfigRow {
            label: "Excluded apps"
            sublabel: "Comma-separated list of apps to ignore"
            StyledTextInput {
                text: (Config.options?.focusTime?.excludeApps ?? []).join(", ")
                onEditingFinished: Config.setNestedValue("focusTime.excludeApps", text.split(",").map(s => s.trim()).filter(s => s.length > 0))
                Layout.fillWidth: true
            }
        }
    }

    // ═══ Display Manager ═══
    SettingsCard {
        icon: "desktop_windows"
        title: "Display Manager"
        subtitle: "Monitor configuration panel (Hyprland only)"

        ConfigSwitch {
            label: "Enable Display Manager"
            sublabel: "Show monitor resolution/refresh rate controls"
            checked: Config.options?.displayManager?.enable ?? true
            onCheckedChanged: Config.setNestedValue("displayManager.enable", checked)
        }

        NoticeBox {
            text: "Display Manager uses hyprctl and is only available on Hyprland. Keybind: Ctrl+Super+D"
            iconName: "info"
        }
    }

    // ═══ Advanced / Hacks ═══
    SettingsCard {
        icon: "code"
        title: "Advanced"
        subtitle: "Debug settings and workarounds"
        expanded: false

        ConfigSlider {
            label: "Race condition delay"
            sublabel: "Delay (ms) for file reload operations to avoid race conditions"
            from: 50; to: 500; stepSize: 25
            value: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
            onValueChanged: Config.setNestedValue("hacks.arbitraryRaceConditionDelay", Math.round(value))
            valueText: `${Math.round(value)}ms`
        }

        ConfigRow {
            label: "Sound theme"
            StyledTextInput {
                text: Config.options?.sounds?.theme ?? "freedesktop"
                onEditingFinished: Config.setNestedValue("sounds.theme", text)
                Layout.preferredWidth: 160
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }

        ConfigSwitch {
            label: "Morphing bar panels"
            sublabel: "Use polygon-based ShapeCanvas bars (experimental, from hefty-hype)"
            checked: Config.options?.bar?.morphingPanels ?? false
            onCheckedChanged: Config.setNestedValue("bar.morphingPanels", checked)
        }

        ConfigSwitch {
            label: "Duplicate player filter"
            sublabel: "Filter duplicate MPRIS players from browser integrations"
            checked: Config.options?.media?.filterDuplicatePlayers ?? true
            onCheckedChanged: Config.setNestedValue("media.filterDuplicatePlayers", checked)
        }
    }
}
