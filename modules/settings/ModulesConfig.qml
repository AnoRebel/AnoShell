import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "."

/**
 * Modules configuration — master enable/disable panel for every shell module.
 * Also includes OSD indicator toggles, screen corner actions, alt-switcher,
 * task view, search, control panel, apps, compositor, and advanced settings.
 */
ColumnLayout {
    id: root
    spacing: 16

    // configRoots: kept in sync with the keys this page actually writes
    // via Config.setNestedValue. Dotted paths cover keys whose top-level
    // root is owned by another page (bar.morphingPanels → BarConfig owns
    // "bar"; display.primaryMonitor → no other page owns "display";
    // sounds.theme → GeneralConfig owns "sounds.battery"). Verified
    // against `grep setNestedValue` on this file as of audit-fixes.
    SettingsPageHeader {
        title: "Modules"
        subtitle: "Enable/disable shell modules, OSD, hot corners, apps, advanced"
        configRoots: [
            "disabledPanels", "enabledPanels", "panelFamily", "familyTransitionAnimation",
            "osd", "deviceEvents", "screenCorners", "altSwitcher", "apps", "focusTime",
            "taskView", "media", "compositor", "hacks", "displayManager",
            "display.primaryMonitor", "sounds.theme", "bar.morphingPanels", "reader", "search", "screenshot", "livePins", "controlPanel", "pieces"
        ]
    }

    PiecesCard {}

    // ═══ Panel Modules Enable/Disable ═══
    SettingsCard {
        id: modulesCard
        icon: "extension"
        title: "Enabled Modules"
        subtitle: `Toggle individual shell modules on and off · ${enabledCount} of ${allModules.length} enabled`
        collapsible: false
        configKeys: ["disabledPanels", "enabledPanels"]

        property string moduleSearchQuery: ""

        readonly property int enabledCount: allModules.filter(m => PanelGate.userEnabled(m.id)).length

        // Shared catalogue (PanelGate) — the same list shell.qml loads from.
        readonly property var allModules: PanelGate.modules.filter(m => m.listed !== false)

        // Search filter — case-insensitive substring match against name + desc.
        function _matchesQuery(mod) {
            const q = modulesCard.moduleSearchQuery.trim().toLowerCase()
            if (q.length === 0) return true
            return mod.name.toLowerCase().includes(q) || mod.desc.toLowerCase().includes(q)
        }

        ConfigTextInput {
            Layout.fillWidth: true
            placeholderText: "Search modules…"
            text: modulesCard.moduleSearchQuery
            onTextChanged: modulesCard.moduleSearchQuery = text
            iconAction: text.length > 0 ? "close" : "search"
            onIconClicked: { if (text.length > 0) text = "" }
        }

        Repeater {
            // Filter by search query, then group by category. Each
            // category emits a header row + the matching module rows
            // beneath it. Empty categories collapse to nothing.
            model: {
                const filtered = modulesCard.allModules.filter(modulesCard._matchesQuery)
                const cats = []
                const seen = {}
                for (const m of filtered) {
                    if (!seen[m.category]) {
                        seen[m.category] = true
                        cats.push({ _isCategory: true, name: m.category })
                    }
                }
                const out = []
                for (const cat of cats) {
                    out.push(cat)
                    for (const m of filtered) if (m.category === cat.name) out.push(m)
                }
                return out
            }

            // One delegate handles either category headers or module rows.
            // Loader picks the right component based on _isCategory.
            Loader {
                required property var modelData
                Layout.fillWidth: true
                sourceComponent: modelData._isCategory ? categoryHeader : moduleEntry

                Component {
                    id: categoryHeader
                    StyledText {
                        text: parent.modelData.name
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        font.weight: Font.DemiBold
                        opacity: 0.6
                        Layout.topMargin: 6
                    }
                }

                Component {
                    id: moduleEntry
                    RowLayout {
                        id: moduleRow
                        readonly property var modelData: parent.modelData
                        Layout.fillWidth: true; spacing: 12

                Rectangle {
                    width: 32; height: 32; radius: 8
                    color: Qt.rgba((Appearance?.colors.colPrimary ?? "#65558F").r, (Appearance?.colors.colPrimary ?? "#65558F").g, (Appearance?.colors.colPrimary ?? "#65558F").b, 0.12)
                    MaterialSymbol { anchors.centerIn: parent; text: moduleRow.modelData.icon; iconSize: 18; color: Appearance?.colors.colPrimary ?? "#65558F" }
                }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 0
                    StyledText { text: moduleRow.modelData.name; font.pixelSize: Appearance?.font.pixelSize.small ?? 14 }
                    StyledText {
                        readonly property string why: PanelGate.reason(moduleRow.modelData.id)
                        text: why.length > 0 ? why : moduleRow.modelData.desc
                        font.pixelSize: Appearance?.font.pixelSize.smallest ?? 10; opacity: 0.4; Layout.fillWidth: true; elide: Text.ElideRight
                    }
                }

                StyledSwitch {
                    id: moduleSwitch
                    // Unavailable in this family/compositor, or always required: shown, not toggleable.
                    enabled: PanelGate.reason(moduleRow.modelData.id) === "" && !(moduleRow.modelData.required ?? false)
                    checked: PanelGate.userEnabled(moduleRow.modelData.id)

                    // toggled() only fires on user-driven changes (mouse
                    // click, Space-key activation, accessibility action).
                    // Bind-time mutations to `checked` do NOT fire it,
                    // which is exactly what we want — the initial-bind
                    // race that corrupted enabledPanels can't happen here.
                    onToggled: {
                        // Store what is switched OFF, so modules added later default to on
                        // and unchecking everything can't wrap around to "all".
                        let off = [...(Config.options?.disabledPanels ?? [])]
                        const legacy = Config.options?.enabledPanels ?? []
                        if (legacy.length > 0) { // convert an old allow-list once
                            off = modulesCard.allModules.map(m => m.id).filter(id => !legacy.includes(id))
                            Config.resetToDefault("enabledPanels")
                        }
                        const id = moduleRow.modelData.id
                        off = checked ? off.filter(p => p !== id) : (off.includes(id) ? off : off.concat([id]))
                        Config.setNestedValue("disabledPanels", off)
                    }
                }
                    } // close RowLayout (moduleRow)
                } // close Component moduleEntry
            } // close Loader delegate
        } // close Repeater
    }

    // ═══ OSD Indicators ═══
    SettingsCard {
        icon: "volume_up"
        title: "OSD Indicators"
        subtitle: "Choose which on-screen display indicators are shown"
        configKeys: ["osd"]

        ConfigSlider {
            label: "Auto-hide timeout"
            configKey: "osd.timeout"
            sublabel: "How long the OSD pill stays visible"
            from: 500; to: 5000; stepSize: 250
            value: Config.options?.osd?.timeout ?? 1500
            onValueChanged: Config.setNestedValue("osd.timeout", Math.round(value))
            valueText: Format.formatDuration(value)
        }

        NotificationPreview { Layout.fillWidth: true }

        ConfigRow {
            label: "OSD position"
            configKey: "osd.position"
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
                { key: "micVolume", label: "Microphone volume (calls' gain control moves it often)", icon: "settings_voice", def: false },
                { key: "media", label: "Media track changes", icon: "music_note" },
                { key: "keyboard", label: "Keyboard layout switch", icon: "keyboard" },
                { key: "network", label: "Network status changes", icon: "wifi" },
                { key: "lockKeys", label: "Caps Lock and Num Lock (Hyprland: bundled binds)", icon: "keyboard_capslock" },
            ]

            RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 12
                MaterialSymbol { text: modelData.icon; iconSize: 18; color: Appearance?.colors.colPrimary ?? "#65558F" }
                StyledText { text: modelData.label; font.pixelSize: Appearance?.font.pixelSize.small ?? 14; Layout.fillWidth: true }
                StyledSwitch {
                    checked: Config.options?.osd?.indicators?.[modelData.key] ?? (modelData.def ?? true)
                    onCheckedChanged: Config.setNestedValue(`osd.indicators.${modelData.key}`, checked)
                }
            }
        }
    }

    // ═══ Device events ═══
    SettingsCard {
        icon: "devices"
        title: "Device events"
        subtitle: "A short pill (or the OSD) when devices come and go. Nothing polls: Bluetooth, audio and displays come from what the shell already watches, USB from one udevadm monitor while it's on."
        configKeys: ["deviceEvents"]

        ConfigSwitch {
            id: devEnable
            label: "Show device events"
            configKey: "deviceEvents.enable"
            checked: Config.options?.deviceEvents?.enable ?? true
            onCheckedChanged: Config.setNestedValue("deviceEvents.enable", checked)
        }
        Repeater {
            model: [
                { key: "bluetooth", label: "Bluetooth devices connecting" },
                { key: "usb", label: "USB devices plugged in or removed (not hubs)" },
                { key: "audio", label: "Audio output changing" },
                { key: "displays", label: "Displays connected or disconnected" },
            ]
            ConfigSwitch {
                required property var modelData
                label: modelData.label
                configKey: `deviceEvents.${modelData.key}`
                enabled: devEnable.checked
                checked: Config.options?.deviceEvents?.[modelData.key] ?? true
                onCheckedChanged: Config.setNestedValue(`deviceEvents.${modelData.key}`, checked)
            }
        }
    }

    // ═══ Screen Corners ═══
    SettingsCard {
        icon: "fullscreen"
        title: "Hot Screen Corners"
        subtitle: "Trigger actions by moving cursor to screen corners"
        configKeys: ["screenCorners"]

        ConfigSwitch {
            label: "Enable hot corners"
            configKey: "screenCorners.enable"
            checked: Config.options?.screenCorners?.enable ?? false
            onCheckedChanged: Config.setNestedValue("screenCorners.enable", checked)
        }

        ConfigSlider {
            label: "Dwell time"
            configKey: "screenCorners.dwellMs"
            sublabel: "How long cursor must stay in corner before activation"
            from: 100; to: 1500; stepSize: 50
            value: Config.options?.screenCorners?.dwellMs ?? 300
            onValueChanged: Config.setNestedValue("screenCorners.dwellMs", Math.round(value))
            valueText: Format.formatDuration(value)
        }

        ConfigSlider {
            label: "Hit zone size"
            configKey: "screenCorners.hitSize"
            sublabel: "Size of the invisible corner trigger area in pixels"
            from: 1; to: 10; stepSize: 1
            value: Config.options?.screenCorners?.hitSize ?? 2
            onValueChanged: Config.setNestedValue("screenCorners.hitSize", Math.round(value))
            valueText: `${Math.round(value)}px`
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.15 }

        // Corner action selectors. ChoiceRow renders compact icon+label
        // pills with ≥32px hit targets — replaces the previous 36-button
        // GroupButton wall (9 actions × 4 corners) that had 28×40 cells.
        readonly property var cornerActions: [
            { value: "sidebarLeftOpen", label: "Left Sidebar", icon: "view_sidebar" },
            { value: "sidebarRightOpen", label: "Right Sidebar", icon: "view_sidebar" },
            { value: "overviewOpen", label: "Overview", icon: "overview" },
            { value: "settingsOpen", label: "Settings", icon: "settings" },
            { value: "hudVisible", label: "HUD", icon: "dashboard" },
            { value: "searchOpen", label: "App Launcher", icon: "search" },
            { value: "clipboardOpen", label: "Clipboard", icon: "content_paste" },
            { value: "controlPanelOpen", label: "Control Panel", icon: "tune" },
            { value: "", label: "None", icon: "block" },
        ]

        Repeater {
            model: [
                { corner: "topLeft", label: "Top Left", icon: "north_west" },
                { corner: "topRight", label: "Top Right", icon: "north_east" },
                { corner: "bottomLeft", label: "Bottom Left", icon: "south_west" },
                { corner: "bottomRight", label: "Bottom Right", icon: "south_east" },
            ]

            ColumnLayout {
                id: cornerRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    spacing: 6
                    MaterialSymbol {
                        text: cornerRow.modelData.icon; iconSize: 16
                        color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                    }
                    StyledText {
                        text: cornerRow.modelData.label
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        font.weight: Font.DemiBold
                    }
                }

                ChoiceRow {
                    Layout.fillWidth: true
                    compact: true
                    itemSpacing: 4
                    model: modulesCard.cornerActions
                    current: Config.options?.screenCorners?.actions?.[cornerRow.modelData.corner] ?? ""
                    onChose: value => Config.setNestedValue(`screenCorners.actions.${cornerRow.modelData.corner}`, value)
                }
            }
        }
    }

    // ═══ Alt-Switcher ═══
    SettingsCard {
        icon: "tab"
        title: "Alt-Tab Window Switcher"
        subtitle: "Window switching overlay appearance and behavior"
        configKeys: ["altSwitcher"]

        ConfigRow {
            label: "Style"
            configKey: "altSwitcher.style"
            sublabel: ({ fan: "Cards on an arc from the pill's edge", list: "A list with thumbnails", fullscreen: "The overview" })[Config.options?.altSwitcher?.style ?? "fan"] ?? ""
            ChoiceRow {
                model: [{ value: "fan", label: "Fan", icon: "view_carousel" }, { value: "list", label: "List", icon: "view_list" }, { value: "fullscreen", label: "Overview", icon: "grid_view" }]
                current: Config.options?.altSwitcher?.style ?? "fan"
                onChose: value => Config.setNestedValue("altSwitcher.style", value)
            }
        }

        ConfigSwitch {
            label: "Enable animations"
            configKey: "altSwitcher.enableAnimation"
            checked: Config.options?.altSwitcher?.enableAnimation ?? true
            onCheckedChanged: Config.setNestedValue("altSwitcher.enableAnimation", checked)
        }

        ConfigSlider {
            label: "Animation duration"
            configKey: "altSwitcher.animationDurationMs"
            from: 50; to: 500; stepSize: 25
            value: Config.options?.altSwitcher?.animationDurationMs ?? 200
            onValueChanged: Config.setNestedValue("altSwitcher.animationDurationMs", Math.round(value))
            valueText: Format.formatDuration(value)
        }

        ConfigSwitch {
            label: "Most recent first (MRU)"
            configKey: "altSwitcher.useMostRecentFirst"
            sublabel: "Order windows by most recently used instead of creation order"
            checked: Config.options?.altSwitcher?.useMostRecentFirst ?? true
            onCheckedChanged: Config.setNestedValue("altSwitcher.useMostRecentFirst", checked)
        }

        ConfigSwitch {
            label: "Compact style"
            configKey: "altSwitcher.compactStyle"
            sublabel: "Smaller thumbnails, more windows visible"
            checked: Config.options?.altSwitcher?.compactStyle ?? false
            onCheckedChanged: Config.setNestedValue("altSwitcher.compactStyle", checked)
        }

        ConfigSlider {
            label: "Background opacity"
            configKey: "altSwitcher.backgroundOpacity"
            from: 0.3; to: 1.0; stepSize: 0.05
            value: Config.options?.altSwitcher?.backgroundOpacity ?? 0.85
            onValueChanged: Config.setNestedValue("altSwitcher.backgroundOpacity", value)
            valueText: `${Math.round(value * 100)}%`
        }

        ConfigSlider {
            label: "Scrim dimming"
            configKey: "altSwitcher.scrimDim"
            from: 0; to: 80; stepSize: 5
            value: Config.options?.altSwitcher?.scrimDim ?? 0
            onValueChanged: Config.setNestedValue("altSwitcher.scrimDim", Math.round(value))
            valueText: `${Math.round(value)}%`
        }

        ConfigSlider {
            label: "Max visible windows"
            configKey: "altSwitcher.maxVisible"
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
        configKeys: ["taskView"]

        ConfigRow {
            label: "Layout algorithm"
            configKey: "taskView.layout"
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

    // ═══ Screenshots ═══
    SettingsCard {
        icon: "screenshot_region"
        title: "Screenshots"
        subtitle: "Print, Shift+Print, Ctrl+Print, Super+Shift+S, Super+Shift+X (text) · the card shown after a capture"
        configKeys: ["screenshot"]

        ConfigSwitch {
            label: "Copy to the clipboard"
            sublabel: "Every capture goes on the clipboard at once"
            configKey: "screenshot.copyOnCapture"
            checked: Config.options?.screenshot?.copyOnCapture ?? true
            onCheckedChanged: Config.setNestedValue("screenshot.copyOnCapture", checked)
        }
        ConfigRow {
            label: "Card position"
            configKey: "screenshot.previewEdge"
            ChoiceRow {
                model: [{ value: "topLeft", label: "Top left", icon: "north_west" }, { value: "topRight", label: "Top right", icon: "north_east" },
                        { value: "bottomLeft", label: "Bottom left", icon: "south_west" }, { value: "bottomRight", label: "Bottom right", icon: "south_east" }]
                current: Config.options?.screenshot?.previewEdge ?? "bottomRight"
                onChose: value => Config.setNestedValue("screenshot.previewEdge", value)
            }
        }
        ConfigSlider {
            label: "Card stays for"
            configKey: "screenshot.previewSeconds"
            sublabel: "0 keeps it until you close it; the pointer on it keeps it too"
            from: 0; to: 30; stepSize: 1
            value: Config.options?.screenshot?.previewSeconds ?? 6
            onValueChanged: Config.setNestedValue("screenshot.previewSeconds", Math.round(value))
            valueText: Math.round(value) === 0 ? "until closed" : `${Math.round(value)} s`
        }
        ConfigRow {
            label: "Then"
            configKey: "screenshot.onTimeout"
            sublabel: "What happens to the capture when the card leaves on its own"
            ChoiceRow {
                model: [{ value: "keep", label: "Keep (temp)", icon: "schedule" }, { value: "save", label: "Save", icon: "save" }, { value: "delete", label: "Delete", icon: "delete" }]
                current: Config.options?.screenshot?.onTimeout ?? "keep"
                onChose: value => Config.setNestedValue("screenshot.onTimeout", value)
            }
        }
        ConfigRow {
            label: "Save to"
            configKey: "screenshot.saveDir"
            sublabel: "Empty: Pictures/Screenshots"
            StyledTextInput {
                text: Config.options?.screenshot?.saveDir ?? ""
                onEditingFinished: Config.setNestedValue("screenshot.saveDir", text.trim())
                Layout.preferredWidth: 200
            }
        }
        ConfigSwitch {
            label: "Freeze the screen while picking a region"
            configKey: "screenshot.freezeRegion"
            sublabel: "The region shot is the moment you started, not what moved meanwhile (Hyprland and other wlroots compositors)"
            checked: Config.options?.screenshot?.freezeRegion ?? false
            onCheckedChanged: Config.setNestedValue("screenshot.freezeRegion", checked)
        }
        ConfigRow {
            label: "Text recognition languages"
            configKey: "screenshot.ocrLanguages"
            sublabel: "Super+Shift+X copies the text in a region. tesseract codes, comma separated (eng, deu, fra, chi_sim…); each needs its tesseract-data package"
            StyledTextInput {
                text: (Config.options?.screenshot?.ocrLanguages ?? ["eng"]).join(", ")
                onEditingFinished: {
                    const l = text.split(/[\s,+]+/).filter(x => /^[A-Za-z_]+$/.test(x))
                    Config.setNestedValue("screenshot.ocrLanguages", l.length ? l : ["eng"])
                }
                Layout.preferredWidth: 200
            }
        }
    }

    // ═══ Live pins ═══
    SettingsCard {
        icon: "picture_in_picture"
        title: "Live pins"
        subtitle: "Super+Alt+P: pick a window, drag over a part of it, and that part stays on screen, live. Drag a pin to move it, its corner to resize; hover for the layer and close buttons (Hyprland)"
        configKeys: ["livePins"]

        ConfigSlider {
            label: "Frames a second"
            configKey: "livePins.fps"
            sublabel: "Per pin; each frame is a window capture, so lower is lighter. Paused while hidden, locked or covered"
            from: 1; to: 30; stepSize: 1
            value: Config.options?.livePins?.fps ?? 10
            onValueChanged: Config.setNestedValue("livePins.fps", Math.round(value))
            valueText: `${Math.round(value)} fps`
        }
        ConfigRow {
            label: "New pins open"
            configKey: "livePins.layer"
            sublabel: "Each pin's hover button moves it between the two"
            ChoiceRow {
                model: [{ value: "top", label: "Above windows", icon: "flip_to_front" }, { value: "bottom", label: "On the desktop", icon: "flip_to_back" }]
                current: Config.options?.livePins?.layer ?? "top"
                onChose: value => Config.setNestedValue("livePins.layer", value)
            }
        }
    }

    // ═══ Control panel ═══
    SettingsCard {
        icon: "tune"
        title: "Control panel"
        subtitle: "Extra rows in the control panel, on its own and grown from the pill"
        configKeys: ["controlPanel"]
        ConfigSwitch {
            label: "System tray"
            sublabel: "The tray's items and menus, while an app has one (also without a tray in the bar)"
            configKey: "controlPanel.tray"
            checked: Config.options?.controlPanel?.tray ?? true
            onCheckedChanged: Config.setNestedValue("controlPanel.tray", checked)
        }
        ConfigSwitch {
            label: "Capture"
            sublabel: "Screenshot a region, copy the text in a region, or start and stop a region recording"
            configKey: "controlPanel.capture"
            checked: Config.options?.controlPanel?.capture ?? true
            onCheckedChanged: Config.setNestedValue("controlPanel.capture", checked)
        }
    }

    // ═══ App Launcher / Search ═══
    SettingsCard {
        icon: "search"
        title: "App Launcher"
        subtitle: "Extra results above your apps · each off until you turn it on"
        configKeys: ["search"]

        Repeater {
            model: [
                { id: "calculator", label: "Calculator", sub: "Type a sum or a conversion; Enter copies the answer (needs qalc)" },
                { id: "emoji", label: "Emoji", sub: "Emoji whose names match; \":\" alone lists only emoji; Enter copies" },
                { id: "packages", label: "Packages", sub: "\"pkg <name>\" searches with paru or yay; Enter installs in your terminal" },
                { id: "actions", label: "Actions", sub: "Lock, suspend, reboot, power off… (search.plugins.actions.items)" },
                { id: "schemes", label: "Colour schemes", sub: "\"scheme …\" switches the Material variant or a fixed theme, live" },
                { id: "looks", label: "Looks", sub: "\"look …\" switches the look, live" }
            ]
            delegate: ConfigSwitch {
                required property var modelData
                label: modelData.label
                sublabel: modelData.sub
                configKey: `search.plugins.${modelData.id}.enable`
                checked: Config.options?.search?.plugins?.[modelData.id]?.enable ?? false
                onCheckedChanged: Config.setNestedValue(`search.plugins.${modelData.id}.enable`, checked)
            }
        }
        ConfigSwitch {
            label: "Allow dangerous actions"
            sublabel: "Reboot and power off run from the launcher (otherwise they are refused)"
            configKey: "search.plugins.actions.enableDangerous"
            visible: Config.options?.search?.plugins?.actions?.enable ?? false
            checked: Config.options?.search?.plugins?.actions?.enableDangerous ?? false
            onCheckedChanged: Config.setNestedValue("search.plugins.actions.enableDangerous", checked)
        }
        ConfigRow {
            label: "Package helper"
            configKey: "search.plugins.packages.helper"
            sublabel: "Empty: paru if installed, else yay"
            visible: Config.options?.search?.plugins?.packages?.enable ?? false
            StyledTextInput {
                text: Config.options?.search?.plugins?.packages?.helper ?? ""
                onEditingFinished: Config.setNestedValue("search.plugins.packages.helper", text.trim())
                Layout.preferredWidth: 120
            }
        }

        // Plugin packages (docs/plugins.md): bundled, yours, or from the Atelier.
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 8
            visible: LauncherPlugins.list.length > 0
            text: "Plugins"
            font.weight: Font.DemiBold
        }
        Repeater {
            model: LauncherPlugins.list
            delegate: ConfigSwitch {
                required property var modelData
                readonly property var problems: LauncherPlugins.registry.errorsOf(modelData.id)
                label: modelData.name + (modelData.source === "user" ? "  ·  yours" : "")
                sublabel: problems.length ? `Doesn't load: ${problems.join("; ")}` : (modelData.description || modelData.id)
                configKey: "search.userPlugins"
                enabled: problems.length === 0
                checked: LauncherPlugins.isEnabled(modelData.id)
                onCheckedChanged: if (checked !== LauncherPlugins.isEnabled(modelData.id)) LauncherPlugins.setEnabled(modelData.id, checked)
            }
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.6
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: "Plugins run with the shell's rights. Add your own in ~/.config/anoshell/plugins/ or get them from Settings → Atelier → Plugins."
        }
    }

    // ═══ Default Applications ═══
    SettingsCard {
        icon: "apps"
        title: "Default Applications"
        subtitle: "Used by keybinds (ano run …) and every shell action that opens one"
        configKeys: ["apps"]

        Repeater {
            model: [
                { key: "terminal", label: "Terminal", icon: "terminal" },
                { key: "browser", label: "Browser", icon: "language" },
                { key: "fileManager", label: "File manager", icon: "folder" }
            ]
            delegate: ColumnLayout {
                id: appCol
                required property var modelData
                readonly property string key: modelData.key
                readonly property var entries: DefaultApps.catalog[key] ?? []
                readonly property string configured: (Config.options?.apps?.[key] ?? "").trim()
                readonly property string program: configured.split(/\s+/)[0] ?? ""
                readonly property string effective: DefaultApps.command(key).join(" ")
                Layout.fillWidth: true
                spacing: 6

                ConfigRow {
                    label: appCol.modelData.label
                    configKey: `apps.${appCol.key}`
                    sublabel: !DefaultApps.detected ? "Looking for installed apps…"
                        : appCol.effective === "" ? "None installed"
                        : appCol.configured !== "" && !DefaultApps.installed[appCol.program]
                            ? `${appCol.program} is not installed — using ${appCol.effective}`
                        : `Opens: ${appCol.effective}`
                    StyledTextInput {
                        // Any command line (e.g. "kitty -1"); the picks below fill it in.
                        text: appCol.configured
                        onEditingFinished: Config.setNestedValue(`apps.${appCol.key}`, text.trim())
                        Layout.preferredWidth: 160
                        font.family: Appearance?.font.family.mono ?? "monospace"
                    }
                }
                ChoiceRow {
                    Layout.fillWidth: true
                    compact: false // names, not one repeated icon
                    itemSpacing: 4
                    visible: model.length > 0
                    model: appCol.entries.filter(a => DefaultApps.installed[a.command])
                        .map(a => ({ value: a.command, label: a.name, icon: appCol.modelData.icon }))
                    current: appCol.program
                    onChose: value => Config.setNestedValue(`apps.${appCol.key}`, value)
                }
                // Well-known apps that aren't installed: shown, not selectable.
                StyledText {
                    Layout.fillWidth: true
                    readonly property var missing: appCol.entries.filter(a => DefaultApps.detected && !DefaultApps.installed[a.command])
                    visible: missing.length > 0
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    text: "Suggested — not installed:  " + missing.map(a => {
                        const cmd = DefaultApps.installCommand(a)
                        return cmd ? `${a.name} (${cmd})` : a.name
                    }).join("  ·  ")
                }
            }
        }
    }

    // ═══ Compositor ═══
    SettingsCard {
        icon: "computer"
        title: "Compositor"
        subtitle: "Wayland compositor settings"
        configKeys: ["compositor", "display.primaryMonitor"]
        expanded: false

        ConfigRow {
            label: "Compositor backend"
            sublabel: CompositorService.experimental ? "Experimental backend — some features may be missing" : "Detected from the session"
            RowLayout {
                spacing: 6
                StyledText { text: CompositorService.backendName; font.family: Appearance?.font.family.mono ?? "monospace"; font.weight: Font.DemiBold }
                Rectangle {
                    visible: CompositorService.experimental
                    implicitWidth: expLabel.implicitWidth + 12; implicitHeight: 20; radius: 10
                    color: Appearance?.colors.colTertiaryContainer ?? "#633B48"
                    StyledText { id: expLabel; anchors.centerIn: parent; text: "experimental"; font.pixelSize: Appearance?.font.pixelSize.smallest ?? 10 }
                }
            }
        }

        ConfigRow {
            label: "Force backend"
            configKey: "compositor.backend"
            sublabel: "auto, hyprland, niri, sway, mango, labwc, umbriel or generic — auto detects from the session; sway, mango, labwc and umbriel are experimental"
            RowLayout {
                spacing: 6
                StyledTextInput {
                    text: Config.options?.compositor?.backend ?? "auto"
                    onEditingFinished: Config.setNestedValue("compositor.backend", text.trim() || "auto")
                    Layout.preferredWidth: 120
                    font.family: Appearance?.font.family.mono ?? "monospace"
                }
                RestartRequiredBadge {}
            }
        }

        ConfigRow {
            label: "Primary monitor"
            configKey: "display.primaryMonitor"
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
        id: familyCard
        icon: "swap_horiz"
        title: "Panel Families"
        subtitle: "Switch between different shell presets — changes which modules are active"
        configKeys: ["panelFamily", "familyTransitionAnimation"]
        collapsible: false

        readonly property string currentFamily: Config.options?.panelFamily ?? "ano"
        readonly property var familyDefs: [
            {
                id: "ano", name: "Ano (Full)", icon: "terminal",
                desc: "Everything enabled — bar, dock, sidebars, HUD, AI chat, overview, clipboard, hot corners, all overlays. The complete experience.",
                color: Appearance.colors.colPrimary
            },
            {
                id: "minimal", name: "Minimal", icon: "remove_circle_outline",
                desc: "Bar + essential overlays only. No dock, no sidebars, no HUD, no hot corners. Lightweight shell for minimal setups.",
                color: Appearance.colors.colInfo
            },
            {
                id: "hefty", name: "Hefty", icon: "auto_awesome",
                desc: "Full experience + morphing bar panels. Bars use polygon ShapeCanvas backgrounds that morph into popout detail panels. The hefty-hype-inspired mode.",
                color: Appearance.colors.colWarning
            },
            {
                id: "clean", name: "Clean", icon: "spa",
                desc: "Bar + sidebars + essentials. No dock, no hot corners. A focused middle ground for distraction-free work.",
                color: Appearance.colors.colSuccess
            }
        ]

        // Family selector cards
        GridLayout {
            Layout.fillWidth: true
            columns: 2; columnSpacing: 10; rowSpacing: 10

            Repeater {
                model: familyCard.familyDefs

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: familyCardCol.implicitHeight + 20
                    radius: Appearance?.rounding.normal ?? 12
                    color: familyCard.currentFamily === modelData.id
                        ? Qt.rgba(modelData.color.r ?? 0.4, modelData.color.g ?? 0.33, modelData.color.b ?? 0.56, 0.15)
                        : Appearance?.colors.colLayer2 ?? "#2B2930"
                    border.width: familyCard.currentFamily === modelData.id ? 2 : 1
                    border.color: familyCard.currentFamily === modelData.id
                        ? modelData.color
                        : Appearance?.colors.colOutlineVariant ?? "#44444488"

                    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }
                    Behavior on border.color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }

                    scale: familyMA.pressed ? 0.96 : (familyMA.containsMouse ? 1.02 : 1)
                    Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(120); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

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
                                    fill: familyCard.currentFamily === modelData.id ? 1 : 0
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 0
                                StyledText {
                                    text: modelData.name
                                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                                    font.weight: Font.DemiBold
                                    color: familyCard.currentFamily === modelData.id ? modelData.color : Appearance?.m3colors.m3onBackground ?? "#E6E1E5"
                                }
                                Loader {
                                    active: familyCard.currentFamily === modelData.id; visible: active
                                    sourceComponent: StyledText {
                                        text: "Active"
                                        font.pixelSize: Appearance.font.pixelSize.smallest; color: modelData.color
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
                            if (familyCard.currentFamily !== modelData.id) {
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
            configKey: "familyTransitionAnimation"
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
        configKeys: ["focusTime"]

        ConfigSwitch {
            label: "Enable Focus Time"
            configKey: "focusTime.enable"
            sublabel: "Track time spent in each application"
            checked: Config.options?.focusTime?.enable ?? true
            onCheckedChanged: Config.setNestedValue("focusTime.enable", checked)
        }

        ConfigRow {
            label: "Excluded apps"
            configKey: "focusTime.excludeApps"
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
        configKeys: ["displayManager"]

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ConfigSwitch {
                Layout.fillWidth: true
                label: "Enable Display Manager"
                configKey: "displayManager.enable"
                sublabel: "Show monitor resolution/refresh rate controls"
                checked: Config.options?.displayManager?.enable ?? true
                onCheckedChanged: Config.setNestedValue("displayManager.enable", checked)
            }
            RestartRequiredBadge {}
        }

        NoticeBox {
            text: "Display Manager uses hyprctl and is only available on Hyprland. Keybind: Ctrl+Super+D"
            iconName: "info"
        }
    }

    // ═══ Reader ═══
    SettingsCard {
        icon: "auto_stories"
        title: "Reader"
        subtitle: "Novel, manga and anime panels · keybinds Ctrl+Super+N / M / A"
        configKeys: ["reader"]

        ConfigSwitch {
            label: "Enable the readers"
            configKey: "reader.enable"
            sublabel: "Needs anod; its backend runs only while a panel is open"
            checked: Config.options?.reader?.enable ?? false
            onCheckedChanged: Config.setNestedValue("reader.enable", checked)
        }

        Repeater {
            model: [
                { kind: "novel", label: "Novels", icon: "menu_book" },
                { kind: "manga", label: "Manga", icon: "photo_library" },
                { kind: "anime", label: "Anime", icon: "movie" }
            ]
            delegate: RowLayout {
                id: kindRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                ConfigSwitch {
                    Layout.fillWidth: true
                    label: kindRow.modelData.label
                    configKey: `reader.${kindRow.modelData.kind}.enable`
                    checked: Config.options?.reader?.[kindRow.modelData.kind]?.enable ?? true
                    onCheckedChanged: Config.setNestedValue(`reader.${kindRow.modelData.kind}.enable`, checked)
                }
                ChoiceRow {
                    compact: true
                    itemSpacing: 4
                    model: [{ value: "left", label: "Left", icon: "align_horizontal_left" }, { value: "right", label: "Right", icon: "align_horizontal_right" }]
                    current: Config.options?.reader?.[kindRow.modelData.kind]?.edge ?? "left"
                    onChose: value => Config.setNestedValue(`reader.${kindRow.modelData.kind}.edge`, value)
                }
            }
        }

        ConfigSwitch {
            label: "Anime: resume where you stopped"
            configKey: "reader.anime.resume"
            sublabel: "anod follows mpv's position per episode (also marks episodes watched)"
            checked: Config.options?.reader?.anime?.resume ?? true
            onCheckedChanged: Config.setNestedValue("reader.anime.resume", checked)
        }
        ConfigSwitch {
            label: "Anime: skip openings and endings"
            configKey: "reader.anime.skipIntro"
            sublabel: "Times from AniSkip (api.aniskip.com, community-submitted), looked up by the show's MyAnimeList id"
            checked: Config.options?.reader?.anime?.skipIntro ?? false
            onCheckedChanged: Config.setNestedValue("reader.anime.skipIntro", checked)
        }
        ConfigSwitch {
            label: "Anime: Airing tab and new-episode badges"
            configKey: "reader.anime.airing"
            sublabel: "This week's episodes, this season and top airing from AniList (graphql.anilist.co, no account); library shows get a badge when a newer episode is out"
            checked: Config.options?.reader?.anime?.airing ?? true
            onCheckedChanged: Config.setNestedValue("reader.anime.airing", checked)
        }
        ConfigSlider {
            label: "Anime: watched after"
            configKey: "reader.anime.finishedRatio"
            from: 0.5; to: 1; stepSize: 0.05
            value: Config.options?.reader?.anime?.finishedRatio ?? 0.9
            onValueChanged: Config.setNestedValue("reader.anime.finishedRatio", Math.round(value * 100) / 100)
            valueText: `${Math.round(value * 100)}%`
        }

        ConfigSlider {
            label: "Stop the backend after"
            configKey: "reader.idleTimeout"
            sublabel: "Seconds with every reader closed (and nothing playing)"
            from: 15; to: 900; stepSize: 15
            value: Config.options?.reader?.idleTimeout ?? 120
            onValueChanged: Config.setNestedValue("reader.idleTimeout", Math.round(value))
            valueText: `${Math.round(value)} s`
        }

        ConfigSlider {
            label: "Image cache"
            configKey: "reader.cacheMB"
            sublabel: "Covers and pages kept by the backend (applies on its next start)"
            from: 16; to: 512; stepSize: 16
            value: Config.options?.reader?.cacheMB ?? 64
            onValueChanged: Config.setNestedValue("reader.cacheMB", Math.round(value))
            valueText: `${Math.round(value)} MB`
        }

        ConfigSlider {
            label: "Page cache"
            configKey: "reader.metaCacheEntries"
            sublabel: "Lists, details and chapters kept by the backend (applies on its next start)"
            from: 64; to: 4096; stepSize: 64
            value: Config.options?.reader?.metaCacheEntries ?? 512
            onValueChanged: Config.setNestedValue("reader.metaCacheEntries", Math.round(value))
            valueText: `${Math.round(value)}`
        }

        Repeater {
            model: [
                { id: "freewebnovel", label: "FreeWebNovel (novels)" },
                { id: "weebcentral", label: "WeebCentral (manga)" },
                { id: "allanime", label: "AllAnime (anime)" }
            ]
            delegate: ConfigRow {
                id: provRow
                required property var modelData
                label: provRow.modelData.label
                configKey: `reader.providers.${provRow.modelData.id}.backend`
                sublabel: "Go (anod) or the legacy Python server"
                ChoiceRow {
                    compact: false
                    itemSpacing: 4
                    model: [{ value: "go", label: "Go", icon: "bolt" }, { value: "python", label: "Python", icon: "code" }]
                    current: Config.options?.reader?.providers?.[provRow.modelData.id]?.backend ?? "go"
                    onChose: value => Config.setNestedValue(`reader.providers.${provRow.modelData.id}.backend`, value)
                }
            }
        }

        ConfigRow {
            label: "Python"
            configKey: "reader.python"
            sublabel: "Interpreter for sources set to Python (a venv with flask, requests, curl_cffi)"
            StyledTextInput {
                text: Config.options?.reader?.python ?? "python3"
                onEditingFinished: Config.setNestedValue("reader.python", text.trim() || "python3")
                Layout.fillWidth: true
            }
        }
    }

    // ═══ Advanced / Hacks ═══
    SettingsCard {
        icon: "code"
        title: "Advanced"
        advanced: true // hidden unless Settings shows advanced options (search still finds it)
        subtitle: "Debug settings and workarounds"
        configKeys: ["hacks", "media", "sounds.theme", "bar.morphingPanels"]
        expanded: false

        ConfigSlider {
            label: "Race condition delay"
            configKey: "hacks.arbitraryRaceConditionDelay"
            sublabel: "Delay (ms) for file reload operations to avoid race conditions"
            from: 50; to: 500; stepSize: 25
            value: Config.options?.hacks?.arbitraryRaceConditionDelay ?? 100
            onValueChanged: Config.setNestedValue("hacks.arbitraryRaceConditionDelay", Math.round(value))
            valueText: Format.formatDuration(value)
        }

        ConfigRow {
            label: "Sound theme"
            configKey: "sounds.theme"
            StyledTextInput {
                text: Config.options?.sounds?.theme ?? "freedesktop"
                onEditingFinished: Config.setNestedValue("sounds.theme", text)
                Layout.preferredWidth: 160
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            ConfigSwitch {
                Layout.fillWidth: true
                label: "Morphing bar panels"
                configKey: "bar.morphingPanels"
                sublabel: PanelGate.family === "ano"
                    ? "Use polygon-based ShapeCanvas bars (experimental, from hefty-hype)"
                    : (PanelGate.family === "hefty" ? "Always on in the Hefty family" : `Not available in the ${PanelGate.family} family`)
                enabled: PanelGate.family === "ano"
                checked: Config.options?.bar?.morphingPanels ?? false
                onCheckedChanged: Config.setNestedValue("bar.morphingPanels", checked)
            }
            RestartRequiredBadge {}
        }

        ConfigSwitch {
            label: "Duplicate player filter"
            configKey: "media.filterDuplicatePlayers"
            sublabel: "Filter duplicate MPRIS players from browser integrations"
            checked: Config.options?.media?.filterDuplicatePlayers ?? true
            onCheckedChanged: Config.setNestedValue("media.filterDuplicatePlayers", checked)
        }

        ConfigRow {
            label: "Preferred player"
            configKey: "media.preferredPlayer"
            sublabel: "Name to track first when nothing is playing (e.g. spotify); empty = automatic"
            StyledTextInput {
                text: Config.options?.media?.preferredPlayer ?? ""
                onEditingFinished: Config.setNestedValue("media.preferredPlayer", text.trim())
                Layout.preferredWidth: 160
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }
    }
}
