import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Bar configuration — elaborate settings with visual bar preview,
 * edge selector with diagram, module reorder, scroll actions, weather, tray.
 */
ColumnLayout {
    id: root
    spacing: 16

    readonly property string currentEdge: Config.options?.bars?.[0]?.edge ?? "top"
    readonly property var leftModules: Config.options?.bars?.[0]?.modules?.left ?? ["sidebarButton", "activeWindow"]
    readonly property var centerModules: Config.options?.bars?.[0]?.modules?.center ?? ["workspaces"]
    readonly property var rightModules: Config.options?.bars?.[0]?.modules?.right ?? ["clock", "battery", "network", "bluetooth", "tray", "sidebarButton"]

    // ═══ Bar Position & Style ═══
    SettingsCard {
        icon: "dock_to_bottom"
        title: "Position & Style"
        subtitle: "Bar edge, auto-hide, background, and margin"

        // Visual edge selector
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 160

            Rectangle {
                id: screenPreview
                anchors.centerIn: parent
                width: 200; height: 130
                radius: 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                border.width: 1; border.color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"

                // Desktop label
                StyledText {
                    anchors.centerIn: parent
                    text: "Desktop"
                    font.pixelSize: 11; opacity: 0.3
                }

                // Bar indicator for each edge
                Repeater {
                    model: [
                        { edge: "top", x: 20, y: 2, w: 160, h: 8 },
                        { edge: "bottom", x: 20, y: 120, w: 160, h: 8 },
                        { edge: "left", x: 2, y: 20, w: 8, h: 90 },
                        { edge: "right", x: 190, y: 20, w: 8, h: 90 }
                    ]

                    Rectangle {
                        required property var modelData
                        x: modelData.x; y: modelData.y
                        width: modelData.w; height: modelData.h
                        radius: 4
                        color: root.currentEdge === modelData.edge
                            ? Appearance?.colors.colPrimary ?? "#65558F"
                            : "transparent"
                        border.width: 1
                        border.color: root.currentEdge === modelData.edge
                            ? Appearance?.colors.colPrimary ?? "#65558F"
                            : Appearance?.colors.colOutlineVariant ?? "#44444488"
                        opacity: root.currentEdge === modelData.edge ? 1 : 0.3

                        Behavior on color { ColorAnimation { duration: 200 } }
                        Behavior on opacity { NumberAnimation { duration: 200 } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Config.setNestedValue("bars.0.edge", modelData.edge)
                        }
                    }
                }
            }

            // Edge label
            StyledText {
                anchors { bottom: screenPreview.top; horizontalCenter: screenPreview.horizontalCenter; bottomMargin: 4 }
                text: `Current: ${root.currentEdge}`
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                font.weight: Font.DemiBold
                color: Appearance?.colors.colPrimary ?? "#65558F"
            }
        }

        // Quick edge buttons
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            Repeater {
                model: ["top", "bottom", "left", "right"]
                GroupButton {
                    required property string modelData
                    label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                    iconName: modelData === "top" ? "vertical_align_top" : modelData === "bottom" ? "vertical_align_bottom" : modelData === "left" ? "align_horizontal_left" : "align_horizontal_right"
                    toggled: root.currentEdge === modelData
                    onClicked: Config.setNestedValue("bars.0.edge", modelData)
                    Layout.fillWidth: true
                }
            }
        }

        // Divider
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.2 }

        ConfigSwitch {
            label: "Auto hide"
            sublabel: "Bar slides away when not hovered, revealing more screen"
            checked: Config.options?.bar?.autoHide?.enable ?? false
            onCheckedChanged: Config.setNestedValue("bar.autoHide.enable", checked)
        }

        ConfigSwitch {
            label: "Show background"
            sublabel: "Transparent bar when disabled — modules float directly"
            checked: Config.options?.bar?.showBackground ?? true
            onCheckedChanged: Config.setNestedValue("bar.showBackground", checked)
        }

        ConfigRow {
            label: "Corner style"
            sublabel: "0 = floating (default), 1 = edge-to-edge with bezel padding"
            ButtonGroup {
                buttons: [
                    GroupButton { label: "Floating"; toggled: (Config.options?.bar?.cornerStyle ?? 0) === 0; onClicked: Config.setNestedValue("bar.cornerStyle", 0) },
                    GroupButton { label: "Edge-to-edge"; toggled: (Config.options?.bar?.cornerStyle ?? 0) === 1; onClicked: Config.setNestedValue("bar.cornerStyle", 1) }
                ]
            }
        }
    }

    // ═══ Bar Modules ═══
    SettingsCard {
        icon: "view_module"
        title: "Bar Modules"
        subtitle: "Configure which modules appear in left, center, and right sections"

        // Available modules reference
        StyledText {
            text: "Available: clock, workspaces, battery, network, bluetooth, tray, media, resources, activeWindow, sidebarButton, weather, keyboard, notifications, idle"
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
            opacity: 0.5
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // Left modules
        ColumnLayout {
            spacing: 4
            StyledText { text: "Left section"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14 }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 36; radius: 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                StyledTextInput {
                    anchors { fill: parent; margins: 8 }
                    text: root.leftModules.join(", ")
                    font.family: Appearance?.font.family.mono ?? "monospace"
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    onEditingFinished: Config.setNestedValue("bars.0.modules.left", text.split(",").map(s => s.trim()).filter(s => s.length > 0))
                }
            }
        }

        // Center modules
        ColumnLayout {
            spacing: 4
            StyledText { text: "Center section"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14 }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 36; radius: 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                StyledTextInput {
                    anchors { fill: parent; margins: 8 }
                    text: root.centerModules.join(", ")
                    font.family: Appearance?.font.family.mono ?? "monospace"
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    onEditingFinished: Config.setNestedValue("bars.0.modules.center", text.split(",").map(s => s.trim()).filter(s => s.length > 0))
                }
            }
        }

        // Right modules
        ColumnLayout {
            spacing: 4
            StyledText { text: "Right section"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14 }
            Rectangle {
                Layout.fillWidth: true; implicitHeight: 36; radius: 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                StyledTextInput {
                    anchors { fill: parent; margins: 8 }
                    text: root.rightModules.join(", ")
                    font.family: Appearance?.font.family.mono ?? "monospace"
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    onEditingFinished: Config.setNestedValue("bars.0.modules.right", text.split(",").map(s => s.trim()).filter(s => s.length > 0))
                }
            }
        }

        NoticeBox {
            text: "Edit module lists above as comma-separated names. Changes apply after shell reload."
            iconName: "info"
        }
    }

    // ═══ Layout & Sizing ═══
    SettingsCard {
        icon: "straighten"
        title: "Layout & Sizing"
        subtitle: "Bar height, corner radius, module spacing, padding, and decorations"

        // Live preview bar mockup
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 80

            Rectangle {
                anchors.centerIn: parent
                width: parent.width * 0.85; height: Config.options?.bar?.layout?.height ?? 42
                radius: Config.options?.bar?.layout?.radius ?? 12
                color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
                border.width: 1; border.color: Appearance?.colors.colLayer0Border ?? "#44444488"

                RowLayout {
                    anchors { fill: parent; leftMargin: Config.options?.bar?.layout?.edgePadding ?? 8; rightMargin: Config.options?.bar?.layout?.edgePadding ?? 8 }

                    // Left mock modules
                    RowLayout {
                        spacing: Config.options?.bar?.layout?.leftSpacing ?? 8
                        Repeater { model: 2; Rectangle { width: 40; height: 14; radius: 7; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; opacity: 0.15 } }
                    }

                    Item { Layout.fillWidth: true }

                    // Center mock group
                    Rectangle {
                        implicitWidth: centerMockRow.implicitWidth + (Config.options?.bar?.layout?.centerGroupPadding ?? 5) * 2
                        implicitHeight: parent.height - 8
                        radius: Config.options?.bar?.layout?.centerGroupRadius ?? 8
                        color: (Config.options?.bar?.layout?.showCenterBackground ?? true) ? (Appearance?.colors.colLayer1 ?? "#E5E1EC") : "transparent"
                        RowLayout {
                            id: centerMockRow; anchors.centerIn: parent; spacing: Config.options?.bar?.layout?.centerSpacing ?? 4
                            Repeater { model: 6; Rectangle { width: 8; height: 8; radius: 4; color: Appearance?.colors.colPrimary ?? "#65558F"; opacity: index === 2 ? 1 : 0.3 } }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Right mock modules
                    RowLayout {
                        spacing: Config.options?.bar?.layout?.rightSpacing ?? 8
                        Repeater { model: 4; Rectangle { width: 30; height: 14; radius: 7; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; opacity: 0.15 } }
                    }

                    // Separators if enabled
                    Repeater {
                        model: (Config.options?.bar?.layout?.showSeparators ?? false) ? 2 : 0
                        Rectangle { width: 1; height: parent.height * 0.5; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.3 }
                    }
                }
            }

            StyledText {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                text: `${Config.options?.bar?.layout?.height ?? 42}px tall • ${Config.options?.bar?.layout?.radius ?? 12}px radius`
                font.pixelSize: 10; opacity: 0.4
            }
        }

        ConfigSlider {
            label: "Bar height"
            sublabel: "Total thickness of the bar in pixels"
            from: 28; to: 64; stepSize: 2
            value: Config.options?.bar?.layout?.height ?? 42
            onValueChanged: Config.setNestedValue("bar.layout.height", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Corner radius"
            sublabel: "Rounding of the bar background corners"
            from: 0; to: 28; stepSize: 1
            value: Config.options?.bar?.layout?.radius ?? 12
            onValueChanged: Config.setNestedValue("bar.layout.radius", Math.round(value))
            valueText: `${Math.round(value)}px`
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        ConfigSlider {
            label: "Left section spacing"
            sublabel: "Gap between modules in the left section"
            from: 0; to: 24; stepSize: 1
            value: Config.options?.bar?.layout?.leftSpacing ?? 8
            onValueChanged: Config.setNestedValue("bar.layout.leftSpacing", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Center section spacing"
            sublabel: "Gap between modules in the center group"
            from: 0; to: 16; stepSize: 1
            value: Config.options?.bar?.layout?.centerSpacing ?? 4
            onValueChanged: Config.setNestedValue("bar.layout.centerSpacing", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Right section spacing"
            sublabel: "Gap between modules in the right section"
            from: 0; to: 24; stepSize: 1
            value: Config.options?.bar?.layout?.rightSpacing ?? 8
            onValueChanged: Config.setNestedValue("bar.layout.rightSpacing", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Edge padding"
            sublabel: "Distance from screen edge to first/last module"
            from: 0; to: 32; stepSize: 1
            value: Config.options?.bar?.layout?.edgePadding ?? 8
            onValueChanged: Config.setNestedValue("bar.layout.edgePadding", Math.round(value))
            valueText: `${Math.round(value)}px`
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        ConfigSlider {
            label: "Center group padding"
            sublabel: "Inner padding of the center pill container"
            from: 0; to: 16; stepSize: 1
            value: Config.options?.bar?.layout?.centerGroupPadding ?? 5
            onValueChanged: Config.setNestedValue("bar.layout.centerGroupPadding", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSlider {
            label: "Center group radius"
            sublabel: "Corner rounding of the center pill container"
            from: 0; to: 24; stepSize: 1
            value: Config.options?.bar?.layout?.centerGroupRadius ?? 8
            onValueChanged: Config.setNestedValue("bar.layout.centerGroupRadius", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
        ConfigSwitch {
            label: "Show center group background"
            sublabel: "Visible pill background behind center modules (workspaces)"
            checked: Config.options?.bar?.layout?.showCenterBackground ?? true
            onCheckedChanged: Config.setNestedValue("bar.layout.showCenterBackground", checked)
        }
        ConfigSwitch {
            label: "Show section separators"
            sublabel: "Thin vertical lines between left, center, and right sections"
            checked: Config.options?.bar?.layout?.showSeparators ?? false
            onCheckedChanged: Config.setNestedValue("bar.layout.showSeparators", checked)
        }
    }

    // ═══ Click & Scroll Actions ═══
    SettingsCard {
        icon: "touch_app"
        title: "Click & Scroll Actions"
        subtitle: "What happens when you click or scroll on each bar section"

        readonly property var actionChoices: [
            { id: "sidebarLeft", label: "Left Sidebar", icon: "view_sidebar" },
            { id: "sidebarRight", label: "Right Sidebar", icon: "view_sidebar" },
            { id: "overview", label: "Overview", icon: "overview" },
            { id: "settings", label: "Settings", icon: "settings" },
            { id: "hud", label: "HUD", icon: "dashboard" },
            { id: "session", label: "Session", icon: "power_settings_new" },
            { id: "clipboard", label: "Clipboard", icon: "content_paste" },
            { id: "wallpaper", label: "Wallpaper", icon: "image" },
            { id: "cheatsheet", label: "Cheatsheet", icon: "keyboard" },
            { id: "none", label: "None", icon: "block" },
        ]
        readonly property var scrollChoices: [
            { id: "brightness", label: "Brightness", icon: "brightness_6" },
            { id: "volume", label: "Volume", icon: "volume_up" },
            { id: "workspace", label: "Workspace", icon: "grid_view" },
            { id: "none", label: "None", icon: "block" },
        ]

        // Click actions
        StyledText { text: "Click actions"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14; Layout.fillWidth: true }

        Repeater {
            model: [
                { section: "Left", key: "leftClick", default_: "sidebarLeft" },
                { section: "Right", key: "rightClick", default_: "sidebarRight" },
                { section: "Center (right-click)", key: "centerClick", default_: "overview" },
            ]

            ConfigRow {
                required property var modelData
                label: `${modelData.section} section click`
                RowLayout {
                    spacing: 3
                    Repeater {
                        model: actionChoices
                        GroupButton {
                            required property var modelData
                            label: modelData.label; iconName: modelData.icon; iconSize: 14
                            showLabel: false
                            toggled: (Config.options?.bar?.actions?.[parent.parent.parent.modelData.key] ?? parent.parent.parent.modelData.default_) === modelData.id
                            onClicked: Config.setNestedValue(`bar.actions.${parent.parent.parent.modelData.key}`, modelData.id)
                            implicitWidth: 36; implicitHeight: 32
                            StyledToolTip { text: parent.modelData.label }
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        // Scroll actions
        StyledText { text: "Scroll actions"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14; Layout.fillWidth: true }

        ConfigRow {
            label: "Left section scroll"
            RowLayout {
                spacing: 3
                Repeater {
                    model: scrollChoices
                    GroupButton {
                        required property var modelData
                        label: modelData.label; iconName: modelData.icon
                        toggled: (Config.options?.bar?.actions?.scrollLeft ?? "brightness") === modelData.id
                        onClicked: Config.setNestedValue("bar.actions.scrollLeft", modelData.id)
                    }
                }
            }
        }
        ConfigRow {
            label: "Right section scroll"
            RowLayout {
                spacing: 3
                Repeater {
                    model: scrollChoices
                    GroupButton {
                        required property var modelData
                        label: modelData.label; iconName: modelData.icon
                        toggled: (Config.options?.bar?.actions?.scrollRight ?? "volume") === modelData.id
                        onClicked: Config.setNestedValue("bar.actions.scrollRight", modelData.id)
                    }
                }
            }
        }
        ConfigRow {
            label: "Center section scroll"
            RowLayout {
                spacing: 3
                Repeater {
                    model: scrollChoices
                    GroupButton {
                        required property var modelData
                        label: modelData.label; iconName: modelData.icon
                        toggled: (Config.options?.bar?.actions?.scrollCenter ?? "workspace") === modelData.id
                        onClicked: Config.setNestedValue("bar.actions.scrollCenter", modelData.id)
                    }
                }
            }
        }
    }

    // ═══ Workspaces ═══
    SettingsCard {
        icon: "grid_view"
        title: "Workspaces"
        subtitle: "Workspace indicator count and style"

        ConfigSlider {
            label: "Number of workspaces shown"
            sublabel: "How many workspace dots appear in the bar"
            from: 2; to: 20; stepSize: 1
            value: Config.options?.bar?.workspaces?.shown ?? 10
            onValueChanged: Config.setNestedValue("bar.workspaces.shown", Math.round(value))
            valueText: `${Math.round(value)}`
        }
    }

    // ═══ Weather ═══
    SettingsCard {
        icon: "thermostat"
        title: "Weather"
        subtitle: "Weather data in bar and sidebar"

        ConfigSwitch {
            label: "Show weather module in bar"
            checked: Config.options?.bar?.weather?.enable ?? false
            onCheckedChanged: Config.setNestedValue("bar.weather.enable", checked)
        }

        ConfigRow {
            label: "City name"
            sublabel: "Leave empty for auto-detect via GPS"
            StyledTextInput {
                text: Config.options?.bar?.weather?.city ?? ""
                onEditingFinished: Config.setNestedValue("bar.weather.city", text)
                Layout.preferredWidth: 180
            }
        }

        ConfigSwitch {
            label: "Use Fahrenheit (USCS)"
            sublabel: "Imperial units (°F, mph, inches)"
            checked: Config.options?.bar?.weather?.useUSCS ?? false
            onCheckedChanged: Config.setNestedValue("bar.weather.useUSCS", checked)
        }

        ConfigSwitch {
            label: "Enable GPS positioning"
            sublabel: "Auto-detect location for weather"
            checked: Config.options?.bar?.weather?.enableGPS ?? false
            onCheckedChanged: Config.setNestedValue("bar.weather.enableGPS", checked)
        }

        ConfigSlider {
            label: "Fetch interval"
            sublabel: "How often weather data refreshes"
            from: 1; to: 60; stepSize: 1
            value: Config.options?.bar?.weather?.fetchInterval ?? 15
            onValueChanged: Config.setNestedValue("bar.weather.fetchInterval", Math.round(value))
            valueText: `${Math.round(value)} min`
        }
    }

    // ═══ System Tray ═══
    SettingsCard {
        icon: "more_horiz"
        title: "System Tray"
        subtitle: "Tray icon filtering and pin management"

        ConfigSwitch {
            label: "Filter passive items"
            sublabel: "Hide tray items with 'passive' status (reduces clutter)"
            checked: Config.options?.tray?.filterPassive ?? false
            onCheckedChanged: Config.setNestedValue("tray.filterPassive", checked)
        }

        ConfigSwitch {
            label: "Invert pinned items"
            sublabel: "Swap which items are shown as pinned vs overflow"
            checked: Config.options?.tray?.invertPinnedItems ?? false
            onCheckedChanged: Config.setNestedValue("tray.invertPinnedItems", checked)
        }

        ConfigSwitch {
            label: "Show item ID in tooltip"
            sublabel: "Useful for identifying which items to pin"
            checked: Config.options?.tray?.showItemId ?? false
            onCheckedChanged: Config.setNestedValue("tray.showItemId", checked)
        }
    }
}
