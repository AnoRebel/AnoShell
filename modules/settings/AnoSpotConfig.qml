import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.bar.modules
import qs.services
import "."

/**
 * AnoSpot settings page — toggle, position selector (4-way), per-widget toggles,
 * and a non-blocking warning when bar.edge collides with anoSpot.position.
 */
ColumnLayout {
    id: root
    spacing: 16

    SettingsPageHeader {
        title: "AnoSpot"
        subtitle: "Position, widgets, click bindings, event border, drag/drop"
        configRoots: ["anoSpot"]
    }

    // The pill where it is, among the bar and dock: drag it to another edge.
    BarPreview { Layout.fillWidth: true }
    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: -8
        text: "Drag the pill (or the dock) to another edge."
        wrapMode: Text.Wrap
        color: Appearance?.colors.colSubtext ?? "#CAC4D0"
        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
    }

    readonly property bool enabled: Config.options?.anoSpot?.enable ?? false
    readonly property string currentPosition: Config.options?.anoSpot?.position ?? "top"

    // Iterate over every configured bar — multi-monitor / multi-bar
    // setups would otherwise miss collisions on bars beyond the first.
    readonly property var collidingBars: {
        if (!enabled) return []
        const bars = Config.options?.bars ?? []
        const out = []
        for (let i = 0; i < bars.length; ++i) {
            if ((bars[i]?.edge ?? "top") === currentPosition) {
                out.push(bars[i]?.id || `bar ${i}`)
            }
        }
        return out
    }
    readonly property bool collides: collidingBars.length > 0

    // ═══ Enable + collision warning ═══
    SettingsCard {
        icon: "view_compact_alt"
        title: "AnoSpot"
        subtitle: "Dynamic-island-style overlay for now playing, notifications, recording, clock"
        configKeys: ["anoSpot.enable", "anoSpot.pillOnly"]

        ConfigSwitch {
            label: "Enable AnoSpot"
            configKey: "anoSpot.enable"
            sublabel: "Compositor-agnostic. Works on Hyprland and Niri."
            checked: root.enabled
            onCheckedChanged: Config.setNestedValue("anoSpot.enable", checked)
        }

        ConfigSwitch {
            label: "Pill only"
            configKey: "anoSpot.pillOnly"
            sublabel: "Use the pill as the whole shell: hide the bar and the dock (your Modules choices for them are kept)"
            checked: Config.options?.anoSpot?.pillOnly ?? false
            onCheckedChanged: {
                Config.setNestedValue("anoSpot.pillOnly", checked)
                if (checked) Config.setNestedValue("anoSpot.enable", true)
            }
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
                    text: {
                        const list = root.collidingBars.join(", ")
                        return `Heads-up: AnoSpot position (${root.currentPosition}) matches the edge of: ${list}. They may visually overlap.`
                    }
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
        configKeys: ["anoSpot.position", "anoSpot.draggable", "anoSpot.floating", "anoSpot.inBar", "anoSpot.autoHide", "anoSpot.hideOnFullscreen"]

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
                    font.pixelSize: Appearance.font.pixelSize.smaller
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

                        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }
                        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(200) } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BarStyle.moveEdge("pill", modelData.pos)
                        }
                    }
                }
            }
        }

        ConfigSwitch {
            label: "Allow drag to reposition"
            configKey: "anoSpot.draggable"
            sublabel: "Show a drag handle on the leading edge; releasing snaps to the nearest screen edge"
            checked: Config.options?.anoSpot?.draggable ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.draggable", checked)
        }

        ConfigSwitch {
            label: "Floating"
            configKey: "anoSpot.floating"
            sublabel: "Keep the pill as its own rounded island with a gap, instead of fusing it into the connected frame"
            checked: Config.options?.anoSpot?.floating ?? false
            onCheckedChanged: Config.setNestedValue("anoSpot.floating", checked)
        }

        ConfigSwitch {
            label: "Inside the bar"
            configKey: "anoSpot.inBar"
            sublabel: (Config.options?.anoSpot?.floating ?? false) ? "Not while floating: a floating pill sits beside the bar"
                : "On a bar's edge, sit in the bar's band (the bar's centre makes way) instead of beside it; keeps sidebars clear of the pill"
            enabled: !(Config.options?.anoSpot?.floating ?? false)
            checked: Config.options?.anoSpot?.inBar ?? false
            onCheckedChanged: Config.setNestedValue("anoSpot.inBar", checked)
        }

        ConfigSwitch {
            label: "Auto-hide"
            configKey: "anoSpot.autoHide"
            sublabel: "Stay tucked into the edge; point at the edge to bring it out"
            checked: Config.options?.anoSpot?.autoHide ?? false
            onCheckedChanged: Config.setNestedValue("anoSpot.autoHide", checked)
        }

        ConfigSwitch {
            label: "Hide in fullscreen"
            configKey: "anoSpot.hideOnFullscreen"
            sublabel: "Slide into the edge while a window is fullscreen; hover the edge to bring it back"
            checked: Config.options?.anoSpot?.hideOnFullscreen ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.hideOnFullscreen", checked)
        }
    }

    // ═══ Widgets ═══
    SettingsCard {
        icon: "widgets"
        title: "Widgets"
        subtitle: "Which slots to render"
        configKeys: ["anoSpot.showMpris", "anoSpot.showNotification", "anoSpot.showRecording", "anoSpot.showTimer", "anoSpot.showPrivacy", "anoSpot.showClockWeather", "anoSpot.showWorkspace", "anoSpot.workspaceHoverPreview", "anoSpot.showBattery", "anoSpot.showLyrics", "anoSpot.accordion"]

        ConfigSwitch {
            label: "Collapse to icons"
            configKey: "anoSpot.accordion"
            sublabel: "The track, notification and battery show as icons and open when you hover them"
            checked: Config.options?.anoSpot?.accordion ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.accordion", checked)
        }

        ConfigSwitch {
            label: "Now playing (Mpris)"
            configKey: "anoSpot.showMpris"
            checked: Config.options?.anoSpot?.showMpris ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showMpris", checked)
        }
        ConfigSwitch {
            label: "Latest notification"
            configKey: "anoSpot.showNotification"
            checked: Config.options?.anoSpot?.showNotification ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showNotification", checked)
        }
        ConfigSwitch {
            label: "Recording indicator"
            configKey: "anoSpot.showRecording"
            checked: Config.options?.anoSpot?.showRecording ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showRecording", checked)
        }
        ConfigSwitch {
            label: "Running timer"
            configKey: "anoSpot.showTimer"
            sublabel: "Countdown, pomodoro or stopwatch time left while one runs; click opens it"
            checked: Config.options?.anoSpot?.showTimer ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showTimer", checked)
        }
        ConfigSwitch {
            label: "Camera & microphone in use"
            configKey: "anoSpot.showPrivacy"
            sublabel: "A green (camera) or orange (microphone) dot; hover for the app"
            checked: Config.options?.anoSpot?.showPrivacy ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showPrivacy", checked)
        }
        ConfigSwitch {
            label: "Clock & weather"
            configKey: "anoSpot.showClockWeather"
            checked: Config.options?.anoSpot?.showClockWeather ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showClockWeather", checked)
        }
        ConfigSwitch {
            label: "Workspace"
            configKey: "anoSpot.showWorkspace"
            sublabel: "Active workspace number/name (click → overview)"
            checked: Config.options?.anoSpot?.showWorkspace ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showWorkspace", checked)
        }
        ConfigSwitch {
            label: "Workspace preview"
            configKey: "anoSpot.workspaceHoverPreview.enable"
            sublabel: "Hovering the workspace shows its windows as live thumbnails; click one to focus it"
            enabled: Config.options?.anoSpot?.showWorkspace ?? true
            checked: Config.options?.anoSpot?.workspaceHoverPreview?.enable ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.workspaceHoverPreview.enable", checked)
        }
        ConfigSwitch {
            label: "Preview every workspace"
            configKey: "anoSpot.workspaceHoverPreview.allWorkspaces"
            sublabel: "Windows of all workspaces, labelled with their workspace; off: this screen's current workspace"
            enabled: (Config.options?.anoSpot?.showWorkspace ?? true) && (Config.options?.anoSpot?.workspaceHoverPreview?.enable ?? true)
            checked: Config.options?.anoSpot?.workspaceHoverPreview?.allWorkspaces ?? false
            onCheckedChanged: Config.setNestedValue("anoSpot.workspaceHoverPreview.allWorkspaces", checked)
        }
        ConfigSwitch {
            label: "Battery"
            configKey: "anoSpot.showBattery"
            sublabel: "Hidden automatically on desktops without a battery"
            checked: Config.options?.anoSpot?.showBattery ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.showBattery", checked)
        }
    }

    // ═══ Bar modules ═══
    SettingsCard {
        icon: "extension"
        title: "Bar modules"
        subtitle: "Any bar module can sit on the pill too (after the zones above). Most hide themselves when idle: drives while nothing is plugged in, privacy while nothing records."
        configKeys: ["anoSpot.modules"]
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: BarModuleLoader.availableModuleIds
                delegate: Rectangle {
                    id: modChip
                    required property string modelData
                    readonly property var current: Config.options?.anoSpot?.modules ?? []
                    readonly property bool on: current.includes(modelData)
                    implicitWidth: modRow.implicitWidth + 20
                    implicitHeight: 30
                    radius: Appearance?.rounding.small ?? 8
                    color: on ? Appearance.colors.colPrimaryContainer
                        : modMA.containsMouse ? Appearance.colors.colLayer1Hover : Appearance.colors.colLayer1
                    border.width: on ? 0 : 1
                    border.color: Appearance.colors.colOutlineVariant
                    RowLayout {
                        id: modRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: modChip.on ? "check" : "add"; iconSize: 14
                            color: modChip.on ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                        }
                        StyledText {
                            text: BarModuleLoader.labelFor(modChip.modelData)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: modChip.on ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                        }
                    }
                    MouseArea {
                        id: modMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Kept in catalogue order, so the pill reads the same as the bar editor.
                        onClicked: {
                            const want = modChip.on ? modChip.current.filter(m => m !== modChip.modelData) : modChip.current.concat([modChip.modelData])
                            Config.setNestedValue("anoSpot.modules", BarModuleLoader.availableModuleIds.filter(m => want.includes(m)))
                        }
                    }
                }
            }
        }
    }

    // ═══ Faces ═══
    SettingsCard {
        icon: "swipe"
        title: "Faces"
        subtitle: "Resting faces you swipe between (horizontal scroll, or drag along the pill). Status is always first."
        configKeys: ["anoSpot.faces"]
        ConfigSwitch {
            label: "Media"
            configKey: "anoSpot.faces.media"
            sublabel: "Title, artist and transport; while a player is running"
            checked: Config.options?.anoSpot?.faces?.media ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.faces.media", checked)
        }
        ConfigSwitch {
            label: "Spectrum"
            configKey: "anoSpot.faces.spectrum"
            sublabel: "Audio visualiser; cava runs only while this face is in view"
            checked: Config.options?.anoSpot?.faces?.spectrum ?? false
            onCheckedChanged: Config.setNestedValue("anoSpot.faces.spectrum", checked)
        }
        ConfigSwitch {
            label: "Lyrics"
            configKey: "anoSpot.faces.lyrics"
            sublabel: "Time-synced lyrics; needs Lyrics turned on in Services"
            checked: Config.options?.anoSpot?.faces?.lyrics ?? false
            onCheckedChanged: Config.setNestedValue("anoSpot.faces.lyrics", checked)
        }
    }

    // ═══ Grow into ═══
    SettingsCard {
        icon: "open_in_full"
        title: "Grow into"
        subtitle: "Clicking grows the pill into the panel (the same panel content, inline) instead of opening it separately"
        configKeys: ["anoSpot.growInto"]
        ConfigSwitch {
            label: "Media controls"
            configKey: "anoSpot.growInto.mediaControls"
            sublabel: "Left click by default"
            checked: Config.options?.anoSpot?.growInto?.mediaControls ?? false
            onCheckedChanged: Config.setNestedValue("anoSpot.growInto.mediaControls", checked)
        }
        ConfigSwitch {
            label: "Control panel"
            configKey: "anoSpot.growInto.controlPanel"
            sublabel: "Right click by default"
            checked: Config.options?.anoSpot?.growInto?.controlPanel ?? false
            onCheckedChanged: Config.setNestedValue("anoSpot.growInto.controlPanel", checked)
        }
        ConfigSwitch {
            label: "Calendar"
            configKey: "anoSpot.growInto.calendar"
            sublabel: "When an action opens the calendar"
            checked: Config.options?.anoSpot?.growInto?.calendar ?? false
            onCheckedChanged: Config.setNestedValue("anoSpot.growInto.calendar", checked)
        }
    }

    // ═══ Transient states ═══
    SettingsCard {
        icon: "notifications_active"
        title: "Transient states"
        subtitle: "The pill briefly morphs to show these; the ones it shows, the separate on-screen display doesn't"
        configKeys: ["anoSpot.transients"]
        ConfigSwitch {
            label: "Volume"
            configKey: "anoSpot.transients.volume"
            sublabel: "Level capsule"
            checked: Config.options?.anoSpot?.transients?.volume ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.volume", checked)
        }
        ConfigSwitch {
            label: "Brightness"
            configKey: "anoSpot.transients.brightness"
            sublabel: "Level capsule"
            checked: Config.options?.anoSpot?.transients?.brightness ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.brightness", checked)
        }
        ConfigSwitch {
            label: "Microphone mute"
            configKey: "anoSpot.transients.mic"
            checked: Config.options?.anoSpot?.transients?.mic ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.mic", checked)
        }
        ConfigSwitch {
            label: "Keyboard layout"
            configKey: "anoSpot.transients.keyboard"
            checked: Config.options?.anoSpot?.transients?.keyboard ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.keyboard", checked)
        }
        ConfigSwitch {
            label: "Notifications"
            configKey: "anoSpot.transients.notification"
            sublabel: "Summary of incoming notifications"
            checked: Config.options?.anoSpot?.transients?.notification ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.notification", checked)
        }
        ConfigSwitch {
            label: "Charging"
            configKey: "anoSpot.transients.charging"
            sublabel: "Plugged in / on battery"
            checked: Config.options?.anoSpot?.transients?.charging ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.charging", checked)
        }
        ConfigSwitch {
            label: "Recording"
            configKey: "anoSpot.transients.recording"
            sublabel: "Started / saved (click opens the file)"
            checked: Config.options?.anoSpot?.transients?.recording ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.recording", checked)
        }
        ConfigSwitch {
            label: "Download finished"
            configKey: "anoSpot.transients.download"
            sublabel: "Click opens the file (needs anod)"
            checked: Config.options?.anoSpot?.transients?.download ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.download", checked)
        }
        ConfigSwitch {
            label: "Screenshot taken"
            configKey: "anoSpot.transients.screenshot"
            sublabel: "Click opens the picture"
            checked: Config.options?.anoSpot?.transients?.screenshot ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.screenshot", checked)
        }
        ConfigSwitch {
            label: "Device events"
            configKey: "anoSpot.transients.device"
            sublabel: "Bluetooth, USB, audio output, displays (Settings → Modules → Device events)"
            checked: Config.options?.anoSpot?.transients?.device ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.transients.device", checked)
        }
    }

    // ═══ Drag and drop ═══
    SettingsCard {
        icon: "place_item"
        title: "Drag and drop"
        subtitle: "Stage files dropped on AnoSpot for triage and actions"
        configKeys: ["anoSpot.acceptDrops", "anoSpot.stashDir"]

        ConfigSwitch {
            id: dropEnable
            label: "Accept drops"
            configKey: "anoSpot.acceptDrops"
            sublabel: "When off, drags pass through AnoSpot to whatever is below"
            checked: Config.options?.anoSpot?.acceptDrops ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.acceptDrops", checked)
        }

        ConfigRow {
            label: "Stash directory"
            configKey: "anoSpot.stashDir"
            sublabel: "Empty = auto ($XDG_RUNTIME_DIR/anoSpot, falls back to /tmp/anoSpot-<UID>)"
            enabled: dropEnable.checked

            ConfigTextInput {
                Layout.fillWidth: true
                Layout.preferredWidth: 240
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                placeholderText: "(auto)"
                text: Config.options?.anoSpot?.stashDir ?? ""
                // Validation: an absolute path or empty for auto-resolution.
                // Catches the common typo of accidental leading whitespace
                // or an unwritable relative path before drops start failing.
                validator: (s) => {
                    const t = (s || "").trim()
                    if (t.length === 0) return null
                    if (!t.startsWith("/") && !t.startsWith("~")) return "Use an absolute or ~ path"
                    return null
                }
                onEditingFinished: Config.setNestedValue("anoSpot.stashDir", text.trim())
            }
        }
    }

    // ═══ Custom drop actions ═══
    SettingsCard {
        icon: "construction"
        title: "Custom drop actions"
        subtitle: "User-defined commands shown as buttons in the stash popout"
        configKeys: ["anoSpot.dropTargets"]

        // ─── API help / placeholder docs ─────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: helpCol.implicitHeight + 16
            radius: Appearance?.rounding.small ?? 8
            color: Appearance?.colors.colLayer2 ?? "#3a3845"
            border.width: 1
            border.color: Appearance?.colors.colOutlineVariant ?? "#44444466"

            ColumnLayout {
                id: helpCol
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                StyledText {
                    Layout.fillWidth: true
                    text: "Each rule becomes a button in the popout footer. Placeholders are substituted in the command:"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                    opacity: 0.8
                    color: Appearance?.colors.colOnLayer0 ?? "#cdd6f4"
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "  {path}   first item's full path        {paths}  newline-joined paths\n" +
                          "  {name}   first item's basename         {names}  newline-joined basenames\n" +
                          "  {dir}    first item's parent dir       {ext}    first item's extension"
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.family: Appearance?.font.family.monospace ?? "monospace"
                    wrapMode: Text.NoWrap
                    color: Appearance?.colors.colOnLayer0 ?? "#cdd6f4"
                    opacity: 0.7
                }
                StyledText {
                    Layout.fillWidth: true
                    text: "Action: 'exec' = argv-split (safe; no shell). 'shell' = bash -c (pipes work; quote your paths). " +
                          "Toggle 'Per item' to invoke the command once per staged file instead of once with all paths."
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                    opacity: 0.8
                    color: Appearance?.colors.colOnLayer0 ?? "#cdd6f4"
                }
            }
        }

        // ─── Existing rules ──────────────────────────────────────────────
        Repeater {
            model: Config.options?.anoSpot?.dropTargets ?? []

            Rectangle {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                implicitHeight: ruleCol.implicitHeight + 16
                radius: Appearance?.rounding.small ?? 8
                color: Appearance?.colors.colLayer1 ?? "#2b2930"
                border.width: 1
                border.color: Appearance?.colors.colOutlineVariant ?? "#44444466"

                ColumnLayout {
                    id: ruleCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 6

                    RowLayout {
                        spacing: 6
                        StyledText {
                            text: "Name"
                            font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.7
                            Layout.preferredWidth: 64
                        }
                        StyledTextInput {
                            Layout.fillWidth: true
                            text: modelData.name ?? ""
                            onEditingFinished: root._updateRule(index, "name", text)
                        }
                        StyledText {
                            text: "Icon"
                            font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.7
                        }
                        StyledTextInput {
                            Layout.preferredWidth: 110
                            text: modelData.icon ?? "play_arrow"
                            onEditingFinished: root._updateRule(index, "icon", text)
                        }
                        RippleButton {
                            implicitHeight: 26
                            buttonRadius: 6
                            contentItem: RowLayout {
                                spacing: 4
                                MaterialSymbol {
                                    text: "delete"; iconSize: 12
                                    color: Appearance?.colors.colError ?? "#f38ba8"
                                }
                            }
                            onClicked: root._removeRule(index)
                        }
                    }

                    RowLayout {
                        spacing: 6
                        StyledText {
                            text: "Action"
                            font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.7
                            Layout.preferredWidth: 64
                        }
                        // exec/shell selector — ChoiceRow keeps the click
                        // semantics consistent with every other binary
                        // choice on the page (no more "click to flip").
                        ChoiceRow {
                            compact: false
                            itemSpacing: 4
                            model: [
                                { value: "exec", label: "exec", icon: "terminal" },
                                { value: "shell", label: "shell", icon: "code" }
                            ]
                            current: modelData.action ?? "exec"
                            onChose: value => root._updateRule(index, "action", value)
                        }
                        ConfigSwitch {
                            label: "Per item"
                            Layout.fillWidth: true
                            checked: modelData.perItem ?? false
                            onCheckedChanged: root._updateRule(index, "perItem", checked)
                        }
                    }

                    RowLayout {
                        spacing: 6
                        StyledText {
                            text: "Command"
                            font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.7
                            Layout.preferredWidth: 64
                        }
                        StyledTextInput {
                            Layout.fillWidth: true
                            text: modelData.command ?? ""
                            font.family: Appearance?.font.family.monospace ?? "monospace"
                            onEditingFinished: root._updateRule(index, "command", text)
                        }
                    }
                }
            }
        }

        // ─── Add new rule ────────────────────────────────────────────────
        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 32
            buttonRadius: 8
            contentItem: RowLayout {
                spacing: 6
                MaterialSymbol { text: "add"; iconSize: 14 }
                StyledText {
                    text: "Add custom action"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            onClicked: root._addRule()
        }
    }

    // ─── Helpers (live at the page root so cards can call them) ─────────
    function _addRule() {
        const cur = (Config.options?.anoSpot?.dropTargets ?? []).slice();
        cur.push({
            name: "New action",
            icon: "play_arrow",
            action: "exec",
            command: "",
            perItem: false
        });
        Config.setNestedValue("anoSpot.dropTargets", cur);
    }
    function _removeRule(idx) {
        const cur = (Config.options?.anoSpot?.dropTargets ?? []).slice();
        if (idx < 0 || idx >= cur.length) return;
        cur.splice(idx, 1);
        Config.setNestedValue("anoSpot.dropTargets", cur);
    }
    function _updateRule(idx, key, value) {
        const cur = (Config.options?.anoSpot?.dropTargets ?? []).slice();
        if (idx < 0 || idx >= cur.length) return;
        const rule = Object.assign({}, cur[idx]);
        rule[key] = value;
        cur[idx] = rule;
        Config.setNestedValue("anoSpot.dropTargets", cur);
    }

    // ═══ Event border animation ═══
    SettingsCard {
        id: eventBorderCard
        icon: "auto_awesome"
        title: "Event border animation"
        subtitle: "Pulsing gradient halo when configured events occur"
        configKeys: ["anoSpot.eventBorder"]

        ConfigSwitch {
            id: borderEnable
            label: "Enable"
            configKey: "anoSpot.eventBorder.enable"
            checked: Config.options?.anoSpot?.eventBorder?.enable ?? true
            onCheckedChanged: Config.setNestedValue("anoSpot.eventBorder.enable", checked)
        }

        ConfigSlider {
            label: "Hold duration"
            configKey: "anoSpot.eventBorder.holdMs"
            sublabel: "How long the halo stays visible before fading out"
            from: 500; to: 5000; stepSize: 100
            value: Config.options?.anoSpot?.eventBorder?.holdMs ?? 1500
            valueText: Format.formatDuration(value)
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
            else return; // No change — writing anyway re-creates the array,
                         // re-fires _hasEvent → checked → onCheckedChanged loop.
            Config.setNestedValue("anoSpot.eventBorder.events", current);
        }

        ConfigSwitch {
            label: "On notification"
            checked: eventBorderCard._hasEvent("notification")
            enabled: borderEnable.checked
            onCheckedChanged: eventBorderCard._setEvent("notification", checked)
        }
        ConfigSwitch {
            label: "On track change"
            checked: eventBorderCard._hasEvent("track")
            enabled: borderEnable.checked
            onCheckedChanged: eventBorderCard._setEvent("track", checked)
        }
        ConfigSwitch {
            label: "On recording start/stop"
            checked: eventBorderCard._hasEvent("recording")
            enabled: borderEnable.checked
            onCheckedChanged: eventBorderCard._setEvent("recording", checked)
        }
        ConfigSwitch {
            label: "On workspace change"
            sublabel: "Fires often if you switch workspaces frequently"
            checked: eventBorderCard._hasEvent("workspace")
            enabled: borderEnable.checked
            onCheckedChanged: eventBorderCard._setEvent("workspace", checked)
        }
    }
}
