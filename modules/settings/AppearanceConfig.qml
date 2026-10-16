import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "."

/**
 * Appearance settings — elaborate with color preview, bezel visualization,
 * animation controls, and wallpaper rotation config.
 */
ColumnLayout {
    id: appearanceRoot
    spacing: 16

    SettingsPageHeader {
        title: "Appearance"
        subtitle: "Look, theme and colours, bezel, animations, wallpaper rotation"
        configRoots: ["appearance", "background", "animations"]
    }

    // Track the originally-selected theme so hover-preview can revert
    // when the cursor leaves a card without the user clicking. Captured
    // once on entry into the picker, restored on cancel/exit.
    readonly property string committedSource: Config.options?.appearance?.theme?.source ?? "materialYou"
    readonly property string committedStatic: Config.options?.appearance?.theme?.name ?? ""

    // True while the user is hovering a non-selected theme card. Pinned
    // by mouse-enter, cleared on click (commits) or mouse-leave (reverts).
    property bool previewing: false
    property string previewingName: ""

    // Preview a theme without writing to the user delta. Sets
    // Appearance.previewTokens; both theme loaders defer to it for the
    // duration of the hover.
    function _previewTheme(name: string): void {
        const tokens = ThemeRegistry.themeContents ? ThemeRegistry.themeContents[name] : null
        if (!tokens) return
        Appearance.previewTokens = tokens
        previewing = true
        previewingName = name
    }

    // Clear the preview overlay. The active source (Material You or the
    // committed static theme) re-renders on the next tick.
    function _revertPreview(): void {
        if (!previewing) return
        Appearance.previewTokens = null
        previewing = false
        previewingName = ""
    }

    // Commit the previewed theme to the user delta. Clears previewTokens
    // synchronously *before* the disk write so there's no stale-overlay
    // tick.
    function _commitTheme(name: string): void {
        Appearance.previewTokens = null
        previewing = false
        previewingName = ""
        Config.setNestedValue("appearance.theme.source", "static")
        Config.setNestedValue("appearance.theme.name", name)
    }

    function _commitMaterialYou(): void {
        Appearance.previewTokens = null
        previewing = false
        previewingName = ""
        Config.setNestedValue("appearance.theme.source", "materialYou")
    }

    // ═══ Theme Source ═══
    // ═══ Look ═══
    SettingsCard {
        id: lookCard
        icon: "palette"
        title: "Look"
        subtitle: "The shell's visual identity: shape, material, texture, type and motion"
        configKeys: ["appearance.look", "appearance.familyLooks", "appearance.lookTextures"]

        readonly property string chosen: Config.options?.appearance?.look ?? ""
        readonly property string familyDefault: Looks.familyDefaults[Looks.family] ?? "liquid"

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            // "Auto": the current panel family's default look.
            RippleButton {
                Layout.fillWidth: true; Layout.columnSpan: 2
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                toggled: lookCard.chosen === ""
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                onClicked: Config.setNestedValue("appearance.look", "")
                contentItem: RowLayout {
                    spacing: 8
                    MaterialSymbol { Layout.leftMargin: 12; text: "auto_mode"; iconSize: 18 }
                    StyledText {
                        Layout.fillWidth: true; elide: Text.ElideRight
                        text: `Auto — ${Looks.entries[lookCard.familyDefault]?.name ?? lookCard.familyDefault} (the ${Looks.family} layout's default)`
                    }
                }
            }

            Repeater {
                model: Looks.list
                SurfaceMaterial {
                    id: tile
                    required property var modelData
                    readonly property bool valid: modelData.errors.length === 0
                    readonly property bool active: Looks.activeId === modelData.id
                    surface: "settings"
                    Layout.fillWidth: true
                    implicitHeight: tileCol.implicitHeight + 24
                    radius: Math.round(14 * ((Looks.entries[modelData.id]?.look?.shape?.radiusScale) ?? 1))
                    color: active ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer2
                    border.width: active ? 2 : 1
                    border.color: active ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    opacity: valid ? 1 : 0.75

                    ColumnLayout {
                        id: tileCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                        spacing: 4
                        RowLayout {
                            spacing: 6
                            StyledText {
                                text: tile.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                            }
                            StyledText {
                                visible: tile.modelData.source === "user"
                                text: "yours"; font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.6
                            }
                            Item { Layout.fillWidth: true }
                            MaterialSymbol { visible: tile.active; text: "check_circle"; iconSize: 18; color: Appearance.colors.colPrimary }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: tile.valid
                            text: Looks.entries[tile.modelData.id]?.description ?? ""
                            wrapMode: Text.WordWrap; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.7
                        }
                        // Error badge: an invalid look is listed but can't be applied.
                        Rectangle {
                            visible: !tile.valid
                            Layout.fillWidth: true
                            implicitHeight: errText.implicitHeight + 10
                            radius: 6
                            color: Appearance.colors.colErrorContainer
                            StyledText {
                                id: errText
                                anchors { fill: parent; margins: 5 }
                                wrapMode: Text.WordWrap; font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colOnErrorContainer
                                text: "Can't apply: " + tile.modelData.errors.join("; ")
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: tile.valid
                        cursorShape: tile.valid ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                        onClicked: Config.setNestedValue("appearance.look", tile.modelData.id)
                    }
                }
            }
        }

        ConfigSwitch {
            label: "Surface textures"
            configKey: "appearance.lookTextures"
            sublabel: "The look's texture on panels (caustics, paper grain, grid, clay light). Animated ones move only while you hover."
            checked: Config.options?.appearance?.lookTextures ?? true
            onCheckedChanged: Config.setNestedValue("appearance.lookTextures", checked)
        }
    }

    // ═══ Theme Source ═══
    SettingsCard {
        icon: "auto_awesome"
        title: "Theme source"
        subtitle: "Dynamic Material You (wallpaper-derived) or pick a static theme"
        configKeys: ["appearance.theme", "appearance.colors"]

        ConfigRow {
            label: "Source"
            configKey: "appearance.theme.source"
            sublabel: appearanceRoot.committedSource === "materialYou"
                ? "Dynamic — palette derived from the active wallpaper"
                : `Static — ${appearanceRoot.committedStatic || "(none selected)"}`

            RowLayout {
                spacing: 4
                Repeater {
                    model: ["materialYou", "static"]
                    RippleButton {
                        required property string modelData
                        implicitHeight: 28
                        buttonRadius: 8
                        toggled: appearanceRoot.committedSource === modelData
                        colBackgroundToggled: Appearance?.colors.colSecondaryContainer ?? "#E8DEF8"
                        contentItem: StyledText {
                            text: modelData === "materialYou" ? "Material You" : "Static"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                        }
                        onClicked: {
                            if (modelData === "materialYou") appearanceRoot._commitMaterialYou()
                            else if (appearanceRoot.committedStatic.length > 0)
                                appearanceRoot._commitTheme(appearanceRoot.committedStatic)
                            else
                                Config.setNestedValue("appearance.theme.source", "static")
                        }
                    }
                }
            }
        }

        ConfigRow {
            label: "Colour mode"
            configKey: "appearance.theme.colorMode"
            visible: appearanceRoot.committedSource === "materialYou"
            sublabel: ({ dynamicAccent: "Wallpaper palette, with the AnoShell violet/teal accent for brand moments",
                         dynamic: "Wallpaper palette everywhere, accent included",
                         fixed: "The AnoShell palette; wallpaper changes leave colours (and app colours) alone" })[Config.options?.appearance?.theme?.colorMode ?? "dynamicAccent"] ?? ""
            ChoiceRow {
                model: [{ value: "dynamicAccent", label: "Wallpaper + accent", icon: "auto_awesome" }, { value: "dynamic", label: "Wallpaper", icon: "wallpaper" }, { value: "fixed", label: "Fixed", icon: "lock" }]
                current: Config.options?.appearance?.theme?.colorMode ?? "dynamicAccent"
                onChose: value => Config.setNestedValue("appearance.theme.colorMode", value)
            }
        }

        ConfigRow {
            label: "Shell mode"
            configKey: "appearance.colors.darkMode"
            sublabel: "Dark or light shell; a wallpaper palette is regenerated in the new mode"
            ChoiceRow {
                model: [{ value: true, label: "Dark", icon: "dark_mode" }, { value: false, label: "Light", icon: "light_mode" }]
                current: Config.options?.appearance?.colors?.darkMode ?? true
                onChose: value => {
                    Config.setNestedValue("appearance.colors.darkMode", value)
                    const wp = Config.options?.background?.wallpaperPath ?? ""
                    if (appearanceRoot.committedSource === "materialYou" && wp.length > 0) Wallpapers.apply(wp, value)
                }
            }
        }

        ConfigRow {
            label: "Apps"
            configKey: "appearance.theme.appColorScheme"
            sublabel: "Light or dark for your apps (GTK, and Qt apps via the portal), independent of the shell"
            ChoiceRow {
                model: [{ value: "follow", label: "Follow shell", icon: "sync" }, { value: "light", label: "Light", icon: "light_mode" }, { value: "dark", label: "Dark", icon: "dark_mode" }]
                current: Config.options?.appearance?.theme?.appColorScheme ?? "follow"
                onChose: value => Config.setNestedValue("appearance.theme.appColorScheme", value)
            }
        }

        // ─── Theme grid (visible only when source = static or while previewing) ───
        Item {
            Layout.fillWidth: true
            implicitHeight: visible ? grid.implicitHeight + 16 : 0
            visible: appearanceRoot.committedSource === "static" || appearanceRoot.previewing

            // Two-column grid of theme cards. Hover previews; click commits.
            GridLayout {
                id: grid
                anchors.fill: parent
                anchors.topMargin: 8
                columns: 2
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: ThemeRegistry.themes

                    Rectangle {
                        required property var modelData
                        readonly property string themeName: modelData.name
                        readonly property bool isCommitted:
                            appearanceRoot.committedSource === "static"
                            && appearanceRoot.committedStatic === themeName
                        readonly property bool isPreviewing:
                            appearanceRoot.previewing
                            && appearanceRoot.previewingName === themeName

                        Layout.fillWidth: true
                        Layout.preferredHeight: cellCol.implicitHeight + 16
                        radius: Appearance?.rounding.small ?? 8
                        color: themeMa.containsMouse
                            ? (Appearance?.colors.colLayer2 ?? "#3a3845")
                            : (Appearance?.colors.colLayer1 ?? "#2b2930")
                        border.width: (isCommitted || isPreviewing) ? 2 : 1
                        border.color: isCommitted
                            ? (Appearance?.colors.colPrimary ?? "#a6e3a1")
                            : isPreviewing
                                ? (Appearance?.colors.colSecondary ?? "#cba6f7")
                                : (Appearance?.colors.colOutlineVariant ?? "#44444466")
                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }
                        Behavior on border.color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }

                        ColumnLayout {
                            id: cellCol
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 6

                            // Header: name + dark/light + source badge
                            RowLayout {
                                spacing: 6
                                StyledText {
                                    text: modelData.displayName
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    font.weight: Font.DemiBold
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Rectangle {
                                    visible: modelData.source === "user"
                                    radius: 4
                                    color: Appearance?.colors.colTertiaryContainer ?? "#5a4a3a"
                                    implicitWidth: userBadge.implicitWidth + 8
                                    implicitHeight: userBadge.implicitHeight + 4
                                    StyledText {
                                        id: userBadge
                                        anchors.centerIn: parent
                                        text: "user"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                    }
                                }
                                MaterialSymbol {
                                    text: modelData.darkmode ? "dark_mode" : "light_mode"
                                    iconSize: 14
                                    color: modelData.darkmode
                                        ? Qt.rgba(1, 1, 1, 0.55)
                                        : Qt.rgba(1, 0.85, 0.4, 0.85)
                                }
                            }

                            // Swatch row — primary / surface / surface-container / outline
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: [
                                        modelData.primary,
                                        modelData.surface,
                                        modelData.surfaceContainer,
                                        modelData.outline
                                    ]
                                    Rectangle {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 16
                                        radius: 4
                                        color: modelData
                                        border.width: 1
                                        border.color: Qt.rgba(0, 0, 0, 0.25)
                                    }
                                }
                            }

                            // Description
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.description
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                opacity: 0.6
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: themeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                if (!parent.isCommitted) appearanceRoot._previewTheme(parent.themeName)
                            }
                            onExited: {
                                if (appearanceRoot.previewing
                                    && appearanceRoot.previewingName === parent.themeName)
                                    appearanceRoot._revertPreview()
                            }
                            onClicked: appearanceRoot._commitTheme(parent.themeName)
                        }
                    }
                }
            }
        }

        NoticeBox {
            visible: appearanceRoot.committedSource === "static" && ThemeRegistry.count === 0
            text: "No themes found. Bundled themes live in assets/themes/. Drop additional .json files into ~/.config/anoshell/themes/ to add your own."
            iconName: "info"
        }

        NoticeBox {
            visible: appearanceRoot.previewing
            text: `Previewing "${appearanceRoot.previewingName}". Click a card to apply, or move the cursor away to revert.`
            iconName: "preview"
        }
    }

    // ═══ Theme Colors ═══
    SettingsCard {
        icon: "palette"
        title: "Theme Colors"
        subtitle: "Live color swatches from the active palette"
        configKeys: ["appearance.colors"]
        collapsible: true
        expanded: false

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
                        font.pixelSize: Appearance.font.pixelSize.smallest
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
        subtitle: "Font families used across the shell — pick from installed fonts"
        configKeys: ["appearance.fonts"]
        expanded: false

        FontPickerRow {
            label: "Main font"
            sublabel: "Primary UI text"
            value: Config.options?.appearance?.fonts?.main ?? ""
            onChosen: v => Config.setNestedValue("appearance.fonts.main", v)
        }
        FontPickerRow {
            label: "Title font"
            sublabel: "Headings and large labels"
            value: Config.options?.appearance?.fonts?.title ?? ""
            onChosen: v => Config.setNestedValue("appearance.fonts.title", v)
        }
        FontPickerRow {
            label: "Numbers font"
            sublabel: "Clock, percentages, counters"
            value: Config.options?.appearance?.fonts?.numbers ?? ""
            onChosen: v => Config.setNestedValue("appearance.fonts.numbers", v)
        }
        FontPickerRow {
            label: "Monospace font"
            sublabel: "Code, mono readouts (network speed, etc.)"
            value: Config.options?.appearance?.fonts?.monospace ?? ""
            onChosen: v => Config.setNestedValue("appearance.fonts.monospace", v)
        }
        FontPickerRow {
            label: "Reading font"
            sublabel: "Long-form text (AI chat, notes)"
            value: Config.options?.appearance?.fonts?.reading ?? ""
            onChosen: v => Config.setNestedValue("appearance.fonts.reading", v)
        }
        FontPickerRow {
            label: "Expressive font"
            sublabel: "Stylized headings and accents"
            value: Config.options?.appearance?.fonts?.expressive ?? ""
            onChosen: v => Config.setNestedValue("appearance.fonts.expressive", v)
        }

        NoticeBox {
            visible: !FontService.ready
            text: "Scanning installed fonts…"
            iconName: "hourglass_empty"
        }
    }

    // ═══ Extra Background Tint ═══
    SettingsCard {
        icon: "tonality"
        title: "Background Tint"
        subtitle: "Apply extra color tinting to layer backgrounds"
        configKeys: ["appearance.extraBackgroundTint"]

        ConfigSwitch {
            label: "Extra background tint"
            configKey: "appearance.extraBackgroundTint"
            sublabel: "Adds a subtle color overlay to surfaces for a warmer feel"
            checked: Config.options?.appearance?.extraBackgroundTint ?? false
            onCheckedChanged: Config.setNestedValue("appearance.extraBackgroundTint", checked)
        }
    }

    // ═══ Global Margin (Bezel) ═══
    SettingsCard {
        icon: "fullscreen"
        title: "Global Margin (Bezel)"
        subtitle: "Floating mode: gap between shell elements and the screen edge"
        configKeys: ["appearance.bezel"]

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
                        font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.6
                    }
                }
            }
        }

        ConfigSlider {
            label: "Bezel size"
            configKey: "appearance.bezel"
            sublabel: "Insets floating bars, sidebars, and overlay panels from the screen edge. Ignored in Connected shell mode, which uses Frame thickness instead."
            from: 0; to: 24; stepSize: 1
            value: Config.options?.appearance?.bezel ?? 0
            onValueChanged: Config.setNestedValue("appearance.bezel", Math.round(value))
            valueText: `${Math.round(value)}px`
        }
    }

    // ═══ Shell Mode ═══
    SettingsCard {
        id: shellModeCard
        icon: "rounded_corner"
        title: "Shell Mode"
        subtitle: "Floating widgets, or a unified surface with rounded screen corners"
        configKeys: ["appearance.connectedCorners"]

        readonly property bool connected: Config.options?.appearance?.connectedCorners?.enable ?? false

        ChoiceRow {
            Layout.fillWidth: true
            compact: false
            itemSpacing: 4
            model: [
                { value: "floating", label: "Floating", icon: "widgets" },
                { value: "connected", label: "Connected", icon: "rounded_corner" }
            ]
            current: shellModeCard.connected ? "connected" : "floating"
            onChose: value => {
                const connected = (value === "connected")
                Config.setNestedValue("appearance.connectedCorners.enable", connected)
                // Bar keeps its own background in BOTH modes — AnoScreen only
                // adds the rounded screen corners (it's stacked above the bar, so
                // it must NOT draw the bar background or it would occlude the
                // content). So showBackground stays true.
                Config.setNestedValue("bar.showBackground", true)
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            wrapMode: Text.WordWrap
            opacity: 0.7
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: shellModeCard.connected
                ? "Connected: bar + panels share one full-screen surface with rounded screen corners (noctalia-style)."
                : "Floating: independent bar and widget windows with gaps between them (classic)."
        }

        ConfigSlider {
            label: "Corner radius"
            configKey: "appearance.connectedCorners.radius"
            sublabel: "Size of the rounded screen corners / bar edge curve"
            from: 4; to: 40; stepSize: 1
            enabled: shellModeCard.connected
            value: Config.options?.appearance?.connectedCorners?.radius ?? 18
            onValueChanged: Config.setNestedValue("appearance.connectedCorners.radius", Math.round(value))
            valueText: `${Math.round(value)}px`
        }

        ConfigSlider {
            label: "Frame thickness"
            configKey: "appearance.connectedCorners.thickness"
            sublabel: "Connected mode's counterpart to Bezel: width of the painted frame band at each screen edge. 0 shows only the rounded corners; raise it for a wider frame (lower it if the band overlaps window borders)."
            from: 0; to: 24; stepSize: 1
            enabled: shellModeCard.connected
            value: Config.options?.appearance?.connectedCorners?.thickness ?? 7
            onValueChanged: Config.setNestedValue("appearance.connectedCorners.thickness", Math.round(value))
            valueText: `${Math.round(value)}px`
        }

        ConfigSwitch {
            label: "Windows sit flush against the frame"
            configKey: "appearance.connectedCorners.manageGaps"
            sublabel: "Drops the compositor's outer gap while connected, so windows meet the frame with no second inset (inner gaps between windows are kept)."
            enabled: shellModeCard.connected
            checked: Config.options?.appearance?.connectedCorners?.manageGaps ?? true
            onCheckedChanged: Config.setNestedValue("appearance.connectedCorners.manageGaps", checked)
        }

        ConfigSlider {
            label: "Frame opacity"
            configKey: "appearance.connectedCorners.opacity"
            sublabel: "Below 100% the frame becomes translucent. Turn on Frame blur too, or you'll see straight through it."
            from: 20; to: 100; stepSize: 1
            enabled: shellModeCard.connected
            value: (Config.options?.appearance?.connectedCorners?.opacity ?? 1.0) * 100
            onValueChanged: Config.setNestedValue("appearance.connectedCorners.opacity", Math.round(value) / 100)
            valueText: `${Math.round(value)}%`
        }

        ConfigSwitch {
            label: "Frame blur"
            configKey: "appearance.connectedCorners.blur"
            sublabel: "Blurs the desktop behind a translucent frame (frosted glass). No visible effect at 100% opacity."
            enabled: shellModeCard.connected
            checked: Config.options?.appearance?.connectedCorners?.blur ?? false
            onCheckedChanged: Config.setNestedValue("appearance.connectedCorners.blur", checked)
        }

        NoticeBox {
            visible: shellModeCard.connected
            iconName: "info"
            text: "Connected mode is best with a top or bottom bar. Vertical bars aren't concave yet."
        }
    }

    // ═══ Shadows (Material 3 elevation) ═══
    SettingsCard {
        id: shadowsCard
        icon: "layers"
        title: "Shadows"
        subtitle: "Material 3 elevation shadows behind shell surfaces"
        configKeys: ["appearance.shadows"]

        readonly property bool shadowsOn: Config.options?.appearance?.shadows?.enable ?? false

        ConfigSwitch {
            label: "Enable elevation shadows"
            configKey: "appearance.shadows.enable"
            sublabel: "Drawn with a GPU signed-distance-field shader (cheap; no blur passes)"
            checked: shadowsCard.shadowsOn
            onCheckedChanged: Config.setNestedValue("appearance.shadows.enable", checked)
        }

        ConfigSlider {
            label: "Intensity"
            configKey: "appearance.shadows.intensity"
            sublabel: "Scales the shadow's blur radius"
            from: 0.25; to: 2.0; stepSize: 0.05
            enabled: shadowsCard.shadowsOn
            value: Config.options?.appearance?.shadows?.intensity ?? 1.0
            onValueChanged: Config.setNestedValue("appearance.shadows.intensity", value)
            valueText: `${value.toFixed(2)}×`
        }

        ConfigSlider {
            label: "Opacity"
            configKey: "appearance.shadows.opacity"
            sublabel: "Scales how dark the shadow is"
            from: 0.1; to: 2.0; stepSize: 0.05
            enabled: shadowsCard.shadowsOn
            value: Config.options?.appearance?.shadows?.opacity ?? 1.0
            onValueChanged: Config.setNestedValue("appearance.shadows.opacity", value)
            valueText: `${value.toFixed(2)}×`
        }
    }

    // ═══ Animations ═══
    SettingsCard {
        icon: "animation"
        title: "Animations"
        subtitle: "On/off, speed, reduced motion and battery saving"
        configKeys: ["animations"]

        ConfigSwitch {
            label: "Enable animations"
            configKey: "animations.enable"
            sublabel: "Disable for better performance on low-end hardware"
            checked: Config.options?.animations?.enable ?? true
            onCheckedChanged: Config.setNestedValue("animations.enable", checked)
        }

        ConfigSlider {
            label: "Animation speed multiplier"
            configKey: "animations.speed"
            sublabel: "1.0 = normal, 0.5 = faster, 2.0 = slower"
            from: 0.2; to: 3; stepSize: 0.1
            value: Config.options?.animations?.speed ?? 1
            onValueChanged: Config.setNestedValue("animations.speed", value)
            valueText: `${value.toFixed(1)}x`
        }

        ConfigSwitch {
            label: "Reduce motion"
            configKey: "animations.reducedMotion"
            sublabel: "Stop looping and ambient motion (spinning art, pulses, visualizers); opening and closing still animate"
            enabled: Config.options?.animations?.enable ?? true
            checked: Config.options?.animations?.reducedMotion ?? false
            onCheckedChanged: Config.setNestedValue("animations.reducedMotion", checked)
        }

        ConfigSwitch {
            label: "Save battery"
            configKey: "animations.batterySaver"
            sublabel: "Stop looping and ambient motion while running on battery"
            enabled: Config.options?.animations?.enable ?? true
            checked: Config.options?.animations?.batterySaver ?? false
            onCheckedChanged: Config.setNestedValue("animations.batterySaver", checked)
        }
    }

    // ═══ Wallpaper Rotation ═══
    SettingsCard {
        icon: "image"
        title: "Wallpaper Rotation"
        subtitle: "Automatically cycle through wallpapers from a directory"
        configKeys: ["background.randomize", "background.wallpaperPath"]

        ConfigSwitch {
            label: "Enable random wallpaper rotation"
            configKey: "background.randomize.enable"
            sublabel: "Periodically change wallpaper from a directory"
            checked: Config.options?.background?.randomize?.enable ?? false
            onCheckedChanged: Config.setNestedValue("background.randomize.enable", checked)
        }

        ConfigRow {
            label: "Wallpaper directory"
            configKey: "background.randomize.directory"
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
            configKey: "background.randomize.interval"
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

    // ═══ Wallpaper Picker (the card deck) ═══
    SettingsCard {
        id: pickerCard
        icon: "style"
        title: "Wallpaper Picker"
        subtitle: "The card deck: its folder, live preview and the Wallhaven key"
        configKeys: ["background.wallpaperDir", "background.picker", "background.wallhaven", "background.favourites"]

        property string keyStatus: ""

        ConfigRow {
            label: "Wallpaper folder"
            configKey: "background.wallpaperDir"
            sublabel: "What the picker deals from; Wallhaven downloads are saved here (supports ~)"
            ConfigTextInput {
                Layout.preferredWidth: 260
                placeholderText: "~/Pictures/hyprwallpapers"
                text: Config.options?.background?.wallpaperDir ?? ""
                onEditingFinished: if (text.trim() !== "") Config.setNestedValue("background.wallpaperDir", text.trim())
            }
        }

        ConfigSwitch {
            label: "Live preview"
            configKey: "background.picker.livePreview"
            sublabel: "Videos and animated images play in the picker's preview (V in the picker)"
            checked: Config.options?.background?.picker?.livePreview ?? true
            onCheckedChanged: Config.setNestedValue("background.picker.livePreview", checked)
        }

        ConfigRow {
            label: "Wallhaven API key"
            sublabel: pickerCard.keyStatus !== "" ? pickerCard.keyStatus
                : Wallhaven.hasKey ? "Saved in ~/.local/share/anoshell/secrets/wallhaven (0600). Paste a new one to replace it, or save an empty field to remove it."
                : "Optional (wallhaven.cc → Settings → Account): unlocks NSFW results. Stored by anod in ~/.local/share/anoshell/secrets/wallhaven, never in config.json."
            ConfigTextInput {
                id: wallhavenKeyInput
                Layout.preferredWidth: 260
                echoMode: TextInput.Password
                placeholderText: Wallhaven.hasKey ? "•••••• (saved)" : "Paste key"
                iconAction: "save"
                function save() {
                    pickerCard.keyStatus = "Saving…"
                    const value = text
                    Wallhaven.setApiKey(value, err => {
                        pickerCard.keyStatus = err !== "" ? err : value.trim() === "" ? "Key removed" : "Key saved"
                        if (err === "") wallhavenKeyInput.text = ""
                    })
                }
                onIconClicked: save()
            }
        }
    }

    // ═══ Wallpaper Transitions ═══
    SettingsCard {
        icon: "swap_horiz"
        title: "Wallpaper Transitions"
        subtitle: "Animation when switching between wallpapers (from inir backdrop)"
        configKeys: ["background.transition"]

        ConfigSwitch {
            label: "Enable wallpaper transitions"
            configKey: "background.transition.enable"
            sublabel: "Smooth crossfade or slide when changing wallpapers"
            checked: Config.options?.background?.transition?.enable ?? true
            onCheckedChanged: Config.setNestedValue("background.transition.enable", checked)
        }

        ConfigRow {
            label: "Transition type"
            configKey: "background.transition.type"
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
            configKey: "background.transition.duration"
            sublabel: "How long the crossfade/slide animation takes"
            from: 200; to: 2000; stepSize: 100
            value: Config.options?.background?.transition?.duration ?? 800
            onValueChanged: Config.setNestedValue("background.transition.duration", Math.round(value))
            valueText: Format.formatDuration(value)
        }

        ConfigRow {
            label: "Slide direction"
            configKey: "background.transition.direction"
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
