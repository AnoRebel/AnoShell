import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "."

/**
 * Services settings — elaborate AI model configuration, weather service,
 * resource monitor, brightness device, and clipboard config.
 */
ColumnLayout {
    spacing: 16

    // ResourceUsage polls only while a visible consumer holds a lease.
    ServiceLease { service: ResourceUsage; name: "settingsServices"; active: true }

    SettingsPageHeader {
        title: "Services"
        subtitle: "AI, Startup applications, GameMode, Performance mode, Updates, PowerProfiles, Network, VPN, NightLight, Lyrics, Calendar, Resources, Brightness, Weather, Recording, Screen sharing, Drives"
        configRoots: [
            "ai", "autostart", "gameMode", "performance", "updates", "musicRecognition", "powerProfiles", "network", "vpn", "kdeConnect",
            "nightLight", "location", "lyrics", "calendar", "resources", "light",
            "shell", "weather", "recording", "sharePicker", "screenFilter", "drives"
        ]
    }

    // ═══ Removable drives ═══
    SettingsCard {
        icon: "usb"
        title: "Removable drives"
        subtitle: "USB sticks and SD cards: the bar's \"drives\" module mounts, opens and ejects them"
        configKeys: ["drives"]

        ConfigSwitch {
            label: "Notify when a drive is plugged in"
            configKey: "drives.notify"
            sublabel: "Also when it's safe to remove after Eject, or when an action fails"
            checked: Config.options?.drives?.notify ?? true
            onCheckedChanged: Config.setNestedValue("drives.notify", checked)
        }
    }

    // ═══ Screen recording ═══
    SettingsCard {
        icon: "screen_record"
        title: "Screen recording"
        subtitle: "Which recorder to use, audio, and where recordings go"
        configKeys: ["recording"]

        ConfigRow {
            label: "Recorder"
            configKey: "recording.backend"
            sublabel: RecorderStatus.available
                ? `Using ${RecorderStatus.backend}` + ((Config.options?.recording?.backend ?? "auto") === "auto" ? " (auto: first installed)" : "")
                : "No recorder installed"
            ChoiceRow {
                model: [{ value: "auto", label: "Auto", icon: "auto_mode" }].concat(RecorderStatus.known.map(b => ({
                    value: b, label: b.replace("-screen-recorder", "-sr"), icon: "videocam",
                    enabled: RecorderStatus.installed.includes(b)
                })))
                current: Config.options?.recording?.backend ?? "auto"
                onChose: value => Config.setNestedValue("recording.backend", value)
            }
        }

        // Nothing installed: what to install, and why each.
        NoticeBox {
            visible: !RecorderStatus.available
            Layout.fillWidth: true
            iconName: "download"
            level: "warning"
            text: "Install one of: " + RecorderStatus.suggestions.map(x => `${x.name} (${x.why})`).join("; ") + ". Then reopen Settings."
        }
        StyledText {
            visible: RecorderStatus.available && RecorderStatus.installed.length < RecorderStatus.known.length
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            opacity: 0.6
            font.pixelSize: Appearance.font.pixelSize.smaller
            text: "Also available: " + RecorderStatus.suggestions.filter(x => !RecorderStatus.installed.includes(x.name)).map(x => `${x.name} — ${x.why}`).join("; ")
        }

        ConfigRow {
            label: "Audio"
            configKey: "recording.audioSource"
            sublabel: RecorderStatus.audioSource === "both" && RecorderStatus.backend !== "gpu-screen-recorder"
                ? "Both: mixed through a temporary sink while recording, removed afterwards"
                : "What you hear, your microphone, or both"
            ChoiceRow {
                model: [
                    { value: "none", label: "None", icon: "volume_off" },
                    { value: "system", label: "System", icon: "volume_up" },
                    { value: "mic", label: "Mic", icon: "mic" },
                    { value: "both", label: "Both", icon: "graphic_eq" }
                ]
                current: RecorderStatus.audioSource
                onChose: value => Config.setNestedValue("recording.audioSource", value)
            }
        }
        ConfigRow {
            label: "Frame rate"
            configKey: "recording.fps"
            ChoiceRow {
                model: [30, 60, 120].map(f => ({ value: f, label: `${f} fps` }))
                current: RecorderStatus.fps
                onChose: value => Config.setNestedValue("recording.fps", value)
            }
        }
        ConfigRow {
            label: "Folder"
            configKey: "recording.dir"
            sublabel: "Empty: ~/Videos"
            ConfigTextInput {
                Layout.preferredWidth: 240
                placeholderText: "~/Videos"
                text: Config.options?.recording?.dir ?? ""
                onEditingFinished: Config.setNestedValue("recording.dir", text.trim())
            }
        }
    }

    // ═══ Screen sharing (Hyprland) ═══
    SettingsCard {
        id: shareCard
        visible: CompositorService.compositor === "hyprland"
        icon: "screen_share"
        title: "Screen sharing"
        subtitle: "AnoShell's picker when an app asks to share a screen, window or region"
        configKeys: ["sharePicker"]

        // `ano share-pick status`: ano | other | stock | missing, then the path set.
        property string xdph: ""
        property string xdphPath: ""
        property string installLog: ""
        readonly property string picker: `${Directories.shellRoot}/scripts/share-picker`
        // ano may live outside xdph's (and the shell's) PATH: ~/.local/bin by default.
        readonly property string _ano: 'A=$(command -v ano || echo "$HOME/.local/bin/ano"); exec "$A" share-pick'
        Component.onCompleted: if (visible) xdphStatus.running = true
        Process {
            id: xdphStatus
            command: ["sh", "-c", `${shareCard._ano} status`]
            stdout: StdioCollector {
                onStreamFinished: {
                    const t = text.trim()
                    const i = t.indexOf(" ")
                    shareCard.xdph = i < 0 ? t : t.slice(0, i)
                    shareCard.xdphPath = i < 0 ? "" : t.slice(i + 1)
                }
            }
        }
        Process {
            id: xdphInstall
            // The picker path goes in as an argument, never into the command line.
            command: ["sh", "-c", `${shareCard._ano} install --picker "$1"`, "sh", shareCard.picker]
            stdout: StdioCollector { onStreamFinished: shareCard.installLog = text.trim() }
            stderr: StdioCollector { onStreamFinished: if (text.trim()) shareCard.installLog = text.trim() }
            onExited: xdphStatus.running = true
        }

        ConfigSwitch {
            label: "Use AnoShell's picker"
            configKey: "sharePicker.enable"
            sublabel: "Screens and windows with live previews, or a region you drag out. Off: the stock hyprland-share-picker answers"
            checked: Config.options?.sharePicker?.enable ?? true
            onCheckedChanged: Config.setNestedValue("sharePicker.enable", checked)
        }
        NoticeBox {
            Layout.fillWidth: true
            iconName: shareCard.xdph === "ano" ? "check_circle" : "info"
            level: shareCard.xdph === "ano" ? "info" : "warning"
            text: shareCard.xdph === "ano" ? "xdph.conf points at AnoShell's picker."
                : shareCard.xdph === "other" ? `xdph.conf uses another picker: ${shareCard.xdphPath}. The button below replaces it (after a backup).`
                : shareCard.xdph === "" ? "Checking ~/.config/hypr/xdph.conf… (needs the ano command)"
                : "The portal (xdg-desktop-portal-hyprland) only shows this picker once ~/.config/hypr/xdph.conf names it: screencopy { custom_picker_binary = … }. Settings writes that only when you press the button, and backs the file up first."
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            RippleButton {
                visible: shareCard.xdph !== "ano"
                enabled: !xdphInstall.running
                toggled: true
                buttonText: "Set in xdph.conf"
                onClicked: xdphInstall.running = true
            }
            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.6
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: shareCard.installLog || "Then restart the portal (systemctl --user restart xdg-desktop-portal-hyprland) or log in again. Undo: restore the xdph.conf.bak-* file."
            }
        }
    }

    // ═══ AI Chat ═══
    SettingsCard {
        icon: "neurology"
        title: "AI Chat"
        subtitle: "Model configuration, API keys, system prompt, and temperature"
        configKeys: ["ai"]

        // Model status indicator
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: modelStatusRow.implicitHeight + 16
            radius: Appearance?.rounding.small ?? 8
            color: Appearance?.colors.colLayer2 ?? "#2B2930"

            RowLayout {
                id: modelStatusRow

                anchors { fill: parent; margins: 8 }
                spacing: 12

                MaterialSymbol {
                    text: Ai.currentModelHasApiKey ? "check_circle" : "error"
                    iconSize: 24; fill: 1
                    color: Ai.currentModelHasApiKey ? Appearance.colors.colSuccess : Appearance?.m3colors.m3error ?? "#BA1A1A"
                }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    StyledText {
                        text: Ai.getModel()?.name ?? "No model selected"
                        font.pixelSize: Appearance?.font.pixelSize.normal ?? 16
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        text: Ai.currentModelHasApiKey ? "API key configured" : "API key missing — use /key in chat"
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        color: Ai.currentModelHasApiKey ? Appearance.colors.colSuccess : Appearance?.m3colors.m3error ?? "#BA1A1A"
                    }
                }
                ColumnLayout {
                    spacing: 1
                    StyledText { text: "Tokens"; font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
                    StyledText {
                        text: Ai.tokenCount.total > 0 ? `${Ai.tokenCount.total}` : "—"
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        font.family: Appearance?.font.family.numbers ?? "monospace"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }

        ConfigRow {
            label: "Default model ID"
            configKey: "ai.defaultModel"
            sublabel: "One of: " + Ai.modelList.join(", ")
            StyledTextInput {
                boxed: true
                text: Config.options?.ai?.defaultModel ?? ""
                onEditingFinished: Config.setNestedValue("ai.defaultModel", text)
                Layout.preferredWidth: 200
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }

        // Available models list
        ColumnLayout {
            spacing: 4
            StyledText { text: "Available models"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14 }

            Repeater {
                model: Ai.modelList

                Rectangle {
                    required property string modelData
                    Layout.fillWidth: true
                    implicitHeight: modelRow.implicitHeight + 12
                    radius: 8
                    color: Ai.currentModelId === modelData
                        ? Qt.rgba((Appearance?.colors.colPrimary ?? "#65558F").r, (Appearance?.colors.colPrimary ?? "#65558F").g, (Appearance?.colors.colPrimary ?? "#65558F").b, 0.15)
                        : "transparent"
                    border.width: Ai.currentModelId === modelData ? 1 : 0
                    border.color: Appearance?.colors.colPrimary ?? "#65558F"

                    RowLayout {
                        id: modelRow
                        anchors { fill: parent; margins: 6 }
                        spacing: 8
                        MaterialSymbol {
                            text: "neurology"; iconSize: 18
                            color: Ai.currentModelId === modelData ? Appearance?.colors.colPrimary ?? "#65558F" : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            StyledText {
                                text: Ai.models[modelData]?.name ?? modelData
                                font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                readonly property bool _hasKey: (Ai.apiKeys[Ai.models[modelData]?.key_id]?.length ?? 0) > 0
                                // Append textual marker when key is missing —
                                // colour-only indication is not enough.
                                text: {
                                    const base = `${Ai.models[modelData]?.api_format ?? "?"} • ${Ai.models[modelData]?.description ?? ""}`
                                    return _hasKey ? base : `${base} · Missing key`
                                }
                                font.pixelSize: Appearance?.font.pixelSize.smallest ?? 11
                                opacity: 0.5; elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }
                        // API key status
                        MaterialSymbol {
                            text: Ai.apiKeys[Ai.models[modelData]?.key_id]?.length > 0 ? "key" : "key_off"
                            iconSize: 16
                            color: Ai.apiKeys[Ai.models[modelData]?.key_id]?.length > 0 ? Appearance.colors.colSuccess : Appearance?.colors.colSubtext ?? "#888"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { Ai.setModel(modelData) }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.2 }

        ConfigSlider {
            label: "Temperature"
            configKey: "ai.temperature"
            sublabel: "Creativity/randomness: 0 = deterministic, 2 = very creative"
            from: 0; to: 2; stepSize: 0.1
            value: Config.options?.ai?.temperature ?? 0.5
            onValueChanged: Config.setNestedValue("ai.temperature", value)
            valueText: `${value.toFixed(1)}`
        }

        ColumnLayout {
            spacing: 4
            RowLayout {
                Layout.fillWidth: true
                StyledText { text: "System prompt"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14; Layout.fillWidth: true }
                StyledText {
                    text: `${promptArea.text.length} chars`
                    font.pixelSize: Appearance?.font.pixelSize.smallest ?? 11
                    opacity: 0.55
                }
            }
            StyledTextArea {
                id: promptArea
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                text: Config.options?.ai?.systemPrompt ?? "You are a helpful assistant integrated into a Linux desktop shell called Ano."
                onEditingFinished: Config.setNestedValue("ai.systemPrompt", text)
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 13
            }
        }

        NoticeBox {
            text: "API keys are managed via the /key command in the AI chat sidebar and stored in ~/.local/share/anoshell/secrets/ai-keys.json (readable only by you). Supported providers: OpenAI, Google Gemini, Anthropic Claude."
            iconName: "security"
        }
    }

    // ═══ Resources Monitor ═══
    SettingsCard {
        icon: "monitor_heart"
        title: "Resources Monitor"
        advanced: true // hidden unless Settings shows advanced options (search still finds it)
        subtitle: "CPU, RAM, network polling frequency and history"
        configKeys: ["resources"]

        // Live mini-dashboard
        RowLayout {
            Layout.fillWidth: true; spacing: 16
            Repeater {
                model: [
                    { label: "CPU", value: ResourceUsage.cpuUsage, text: `${Math.round(ResourceUsage.cpuUsage * 100)}%` },
                    { label: "RAM", value: ResourceUsage.memoryUsedPercentage, text: ResourceUsage.kbToGbString(ResourceUsage.memoryUsed) },
                ]
                ColumnLayout {
                    required property var modelData
                    spacing: 4; Layout.fillWidth: true
                    CircularProgress { implicitSize: 36; lineWidth: 3; value: modelData.value; Layout.alignment: Qt.AlignHCenter }
                    StyledText { text: modelData.text; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace"; Layout.alignment: Qt.AlignHCenter }
                    StyledText { text: modelData.label; font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.2 }

        ConfigSlider {
            label: "Update interval"
            configKey: "resources.updateInterval"
            sublabel: "How often /proc is polled for CPU/RAM/network data"
            from: 500; to: 10000; stepSize: 500
            value: Config.options?.resources?.updateInterval ?? 3000
            onValueChanged: Config.setNestedValue("resources.updateInterval", Math.round(value))
            valueText: Format.formatDuration(value)
        }

        ConfigSlider {
            label: "History length"
            configKey: "resources.historyLength"
            sublabel: "Number of data points stored for graph display"
            from: 10; to: 180; stepSize: 10
            value: Config.options?.resources?.historyLength ?? 60
            onValueChanged: Config.setNestedValue("resources.historyLength", Math.round(value))
            valueText: `${Math.round(value)} pts`
        }
    }

    // ═══ Brightness Device ═══
    SettingsCard {
        icon: "brightness_6"
        title: "Brightness"
        advanced: true // hidden unless Settings shows advanced options (search still finds it)
        subtitle: "Backlight device override"
        configKeys: ["light"]

        ConfigRow {
            label: "Device name"
            configKey: "light.device"
            sublabel: "Leave empty for auto-detect. Use 'brightnessctl -l' to list devices."
            StyledTextInput {
                boxed: true
                text: Config.options?.light?.device ?? ""
                onEditingFinished: Config.setNestedValue("light.device", text)
                Layout.preferredWidth: 200
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }
    }

    AutostartCard {}

    // ═══ GameMode ═══
    SettingsCard {
        icon: "videogame_asset"
        title: "GameMode"
        subtitle: "Follows gamemoded (games started with gamemoderun or libgamemode) over D-Bus, without polling and without starting it. Needs `gamemode`."
        configKeys: ["gameMode"]

        ConfigSwitch {
            id: gmEnable
            label: "Bar indicator"
            sublabel: "Show a gaming icon in the bar while a game holds GameMode"
            configKey: "gameMode.enable"
            checked: Config.options?.gameMode?.enable ?? false
            onCheckedChanged: Config.setNestedValue("gameMode.enable", checked)
        }

        ConfigRow {
            label: "Status"
            sublabel: GameMode.active ? `Active · ${GameMode.clientCount} client(s)` : "No game holds GameMode"
            StyledText {
                text: GameMode.active ? "●" : "○"
                color: GameMode.active
                    ? (Appearance?.colors.colPrimary ?? "#a6e3a1")
                    : Qt.rgba(1, 1, 1, 0.3)
                font.pixelSize: Appearance.font.pixelSize.larger
            }
        }
    }

    // ═══ Performance mode ═══
    SettingsCard {
        icon: "speed"
        title: "Performance mode"
        subtitle: "Frees the GPU and CPU for a game: pauses the shell's animations, blur, shadows and audio visualisers, puts the desktop pieces away, polls resources less often, and holds notification popups (they still reach the notification centre). On Hyprland it can also turn off the compositor's animations, blur, shadows, gaps and rounding, putting them back as they were after."
        configKeys: ["performance"]

        ConfigRow {
            label: "Now"
            sublabel: GameMode.performance ? `On: ${GameMode.performanceReason}`
                : GameMode.refused ? "Off by hand until the game or app closes" : "Off"
            RippleButton {
                buttonText: GameMode.performance ? "Turn off" : "Turn on"
                toggled: GameMode.performance
                onClicked: GameMode.toggle()
            }
        }
        ConfigSwitch {
            label: "While a game holds GameMode"
            configKey: "performance.onGameMode"
            checked: Config.options?.performance?.onGameMode ?? true
            onCheckedChanged: Config.setNestedValue("performance.onGameMode", checked)
        }
        ConfigSwitch {
            label: "While a window is fullscreen"
            sublabel: "Videos and presentations count too"
            configKey: "performance.onFullscreen"
            checked: Config.options?.performance?.onFullscreen ?? false
            onCheckedChanged: Config.setNestedValue("performance.onFullscreen", checked)
        }
        ConfigRow {
            label: "While these apps are open"
            configKey: "performance.apps"
            sublabel: "App ids, comma-separated; * and ? match anything, case doesn't matter (e.g. steam_app_*, blender)"
            StyledTextInput {
                boxed: true
                text: (Config.options?.performance?.apps ?? []).join(", ")
                onEditingFinished: Config.setNestedValue("performance.apps", text.split(",").map(s => s.trim()).filter(s => s.length > 0))
                Layout.fillWidth: true
            }
        }
        ConfigSwitch {
            label: "Pause animations"
            configKey: "performance.stopAnimations"
            checked: Config.options?.performance?.stopAnimations ?? true
            onCheckedChanged: Config.setNestedValue("performance.stopAnimations", checked)
        }
        ConfigSwitch {
            label: "Pause blur"
            configKey: "performance.stopBlur"
            checked: Config.options?.performance?.stopBlur ?? true
            onCheckedChanged: Config.setNestedValue("performance.stopBlur", checked)
        }
        ConfigSwitch {
            label: "Pause audio visualisers"
            configKey: "performance.stopVisualizers"
            checked: Config.options?.performance?.stopVisualizers ?? true
            onCheckedChanged: Config.setNestedValue("performance.stopVisualizers", checked)
        }
        ConfigSwitch {
            label: "Hold notification popups"
            configKey: "performance.holdPopups"
            checked: Config.options?.performance?.holdPopups ?? true
            onCheckedChanged: Config.setNestedValue("performance.holdPopups", checked)
        }
        ConfigSwitch {
            label: "Turn off shadows"
            configKey: "performance.stopShadows"
            checked: Config.options?.performance?.stopShadows ?? true
            onCheckedChanged: Config.setNestedValue("performance.stopShadows", checked)
        }
        ConfigSwitch {
            label: "Put desktop pieces away"
            configKey: "performance.hidePieces"
            checked: Config.options?.performance?.hidePieces ?? true
            onCheckedChanged: Config.setNestedValue("performance.hidePieces", checked)
        }
        ConfigSwitch {
            label: "Read CPU, memory and network less often"
            configKey: "performance.slowPolling"
            checked: Config.options?.performance?.slowPolling ?? true
            onCheckedChanged: Config.setNestedValue("performance.slowPolling", checked)
        }
        ConfigSlider {
            label: "Read them every"
            configKey: "performance.pollInterval"
            enabled: Config.options?.performance?.slowPolling ?? true
            from: 2000; to: 30000; stepSize: 1000
            value: Config.options?.performance?.pollInterval ?? 10000
            onValueChanged: Config.setNestedValue("performance.pollInterval", Math.round(value))
            valueText: `${Math.round(value / 1000)} s`
        }
        // Hyprland's own options, put back exactly as they were after (services/hyprperf.js).
        Repeater {
            model: CompositorService.isHyprland ? [
                { key: "hyprAnimations", label: "Hyprland: turn off animations", def: true },
                { key: "hyprBlur", label: "Hyprland: turn off blur", def: true },
                { key: "hyprShadows", label: "Hyprland: turn off shadows", def: true },
                { key: "hyprGaps", label: "Hyprland: no gaps", def: false },
                { key: "hyprRounding", label: "Hyprland: square corners", def: false },
                { key: "hyprTearing", label: "Hyprland: allow tearing", def: false,
                  sub: "Only for windows with an immediate window rule (lower latency, may tear)" }] : []
            delegate: ConfigSwitch {
                required property var modelData
                label: modelData.label
                sublabel: modelData.sub ?? ""
                configKey: `performance.${modelData.key}`
                checked: Config.options?.performance?.[modelData.key] ?? modelData.def
                onCheckedChanged: if (checked !== (Config.options?.performance?.[modelData.key] ?? modelData.def))
                    Config.setNestedValue(`performance.${modelData.key}`, checked)
            }
        }
    }

    // ═══ Package updates ═══
    SettingsCard {
        icon: "system_update_alt"
        title: "Package updates"
        subtitle: "Counts pending updates (checkupdates, plus paru/yay -Qua for the AUR) and shows them in the bar module \"updates\". The shell never updates by itself: clicking opens the update in your terminal. Needs `pacman-contrib`."
        configKeys: ["updates"]

        ConfigSwitch {
            label: "Check for updates"
            configKey: "updates.enable"
            checked: Config.options?.updates?.enable ?? false
            onCheckedChanged: Config.setNestedValue("updates.enable", checked)
        }
        ConfigSlider {
            label: "Check every"
            configKey: "updates.intervalMin"
            from: 15; to: 720; stepSize: 15
            enabled: Config.options?.updates?.enable ?? false
            value: Config.options?.updates?.intervalMin ?? 120
            onValueChanged: Config.setNestedValue("updates.intervalMin", Math.round(value))
            valueText: Math.round(value) >= 60 ? `${(Math.round(value) / 60).toFixed(Math.round(value) % 60 ? 1 : 0)} h` : `${Math.round(value)} min`
        }
        ConfigRow {
            label: "Update command"
            configKey: "updates.command"
            sublabel: "Runs in your terminal. Empty: paru/yay -Syu, else sudo pacman -Syu"
            ConfigTextInput {
                Layout.fillWidth: true
                Layout.preferredWidth: 240
                Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                placeholderText: DefaultApps.aurHelper ? `${DefaultApps.aurHelper} -Syu` : "sudo pacman -Syu"
                text: Config.options?.updates?.command ?? ""
                onEditingFinished: Config.setNestedValue("updates.command", text.trim())
            }
        }
        ConfigRow {
            label: "Now"
            sublabel: !(Config.options?.updates?.enable ?? false) ? "Not checking"
                : Updates.checking ? "Checking…"
                : Updates.error ? `Couldn't check: ${Updates.error}`
                : Updates.lastChecked ? `${Updates.count} pending (${Updates.aurCount} AUR)` : "First check a minute after start"
            RippleButton {
                buttonText: "Check now"
                enabled: (Config.options?.updates?.enable ?? false) && !Updates.checking
                onClicked: Updates.check()
            }
        }
    }

    // ═══ Music recognition ═══
    SettingsCard {
        icon: "music_note"
        title: "Music recognition"
        subtitle: "\"What's playing?\" from the quick toggles or `qs -c ano ipc call musicRecognition recognize`: records a few seconds, asks songrec (which uses Shazam's unofficial service), then deletes the recording. Needs `songrec` and PipeWire (pw-record)."
        configKeys: ["musicRecognition"]

        ConfigSwitch {
            label: "Enable"
            configKey: "musicRecognition.enable"
            checked: Config.options?.musicRecognition?.enable ?? false
            onCheckedChanged: Config.setNestedValue("musicRecognition.enable", checked)
        }
        ConfigRow {
            label: "Listen to"
            configKey: "musicRecognition.source"
            ChoiceRow {
                model: [{ value: "output", label: "What's playing", icon: "speaker" }, { value: "mic", label: "Microphone", icon: "mic" }]
                current: Config.options?.musicRecognition?.source ?? "output"
                onChose: value => Config.setNestedValue("musicRecognition.source", value)
            }
        }
        ConfigSlider {
            label: "Listen for"
            configKey: "musicRecognition.seconds"
            from: 4; to: 20; stepSize: 1
            value: Config.options?.musicRecognition?.seconds ?? 8
            onValueChanged: Config.setNestedValue("musicRecognition.seconds", Math.round(value))
            valueText: `${Math.round(value)} s`
        }
    }

    // ═══ Power Profiles ═══
    SettingsCard {
        icon: "battery_saver"
        title: "Power profiles"
        subtitle: "Restores the last-active power-profiles-daemon profile on shell start. Requires `power-profiles-daemon`."
        configKeys: ["powerProfiles"]

        StyledText {
            visible: PowerProfilePersistence.checked && !PowerProfilePersistence.available
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: "power-profiles-daemon isn't installed or running, so there are no profiles to switch."
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
        }
        ConfigSwitch {
            visible: PowerProfilePersistence.available
            label: "Restore on start"
            configKey: "powerProfiles.restoreOnStart"
            sublabel: "When off, power-profiles-daemon decides at boot"
            checked: Config.options?.powerProfiles?.restoreOnStart ?? true
            onCheckedChanged: Config.setNestedValue("powerProfiles.restoreOnStart", checked)
        }

        ConfigRow {
            visible: PowerProfilePersistence.available
            label: "Active profile"
            sublabel: "Persists across reboots when restore-on-start is on"

            RowLayout {
                spacing: 4

                Repeater {
                    model: ({
                        // Filter performance out when the daemon doesn't expose it
                        list: PowerProfiles.hasPerformanceProfile
                            ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
                            : [PowerProfile.PowerSaver, PowerProfile.Balanced]
                    }).list

                    RippleButton {
                        required property int modelData
                        readonly property string label: modelData === PowerProfile.PowerSaver
                            ? "Power saver"
                            : modelData === PowerProfile.Balanced
                                ? "Balanced"
                                : "Performance"
                        readonly property string symbol: modelData === PowerProfile.PowerSaver
                            ? "battery_saver"
                            : modelData === PowerProfile.Balanced
                                ? "balance"
                                : "rocket_launch"
                        implicitHeight: 28
                        buttonRadius: 8
                        toggled: PowerProfiles.profile === modelData
                        colBackgroundToggled: Appearance?.colors.colSecondaryContainer ?? "#E8DEF8"
                        contentItem: RowLayout {
                            spacing: 4
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            MaterialSymbol { text: symbol; iconSize: 14 }
                            StyledText { text: label; font.pixelSize: Appearance.font.pixelSize.smaller }
                        }
                        onClicked: PowerProfiles.profile = modelData
                    }
                }
            }
        }
    }

    // ═══ Location ═══
    SettingsCard {
        icon: "location_on"
        title: "Location"
        subtitle: "Where you are, for the weather, night light's sunset-to-sunrise schedule and the sun and moon of the Bioma pieces"
        configKeys: ["location"]

        ConfigSwitch {
            label: "Use my location"
            configKey: "location.enable"
            sublabel: "Off: nothing is looked up; the weather uses its own city setting"
            checked: Config.options?.location?.enable ?? true
            onCheckedChanged: if (checked !== (Config.options?.location?.enable ?? true)) Config.setNestedValue("location.enable", checked)
        }
        ConfigRow {
            label: "Find it"
            configKey: "location.mode"
            enabled: Config.options?.location?.enable ?? true
            sublabel: Location.valid ? `${Location.city ? Location.city + " · " : ""}${Location.latitude.toFixed(3)}, ${Location.longitude.toFixed(3)} · from ${({ geoclue: "GeoClue", ip: "your IP address", manual: "what you set" })[Location.source] ?? Location.source}`
                : Location.problem
            ChoiceRow {
                model: [{ value: "auto", label: "Automatically", icon: "my_location" }, { value: "manual", label: "Set it myself", icon: "edit_location" }]
                current: Config.options?.location?.mode ?? "auto"
                onChose: value => Config.setNestedValue("location.mode", value)
            }
        }
        StyledText {
            visible: (Config.options?.location?.mode ?? "auto") === "auto"
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "Automatically: GeoClue (Wi-Fi or GPS, needs the geoclue service), else your IP address through ip-api.com, which gives your city, roughly."
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        ConfigRow {
            visible: (Config.options?.location?.mode ?? "auto") === "manual"
            label: "City"
            configKey: "location.city"
            sublabel: "The name shown, and what the weather looks up if no coordinates are set"
            ConfigTextInput {
                Layout.preferredWidth: 180
                text: Config.options?.location?.city ?? ""
                onEditingFinished: Config.setNestedValue("location.city", text.trim())
            }
        }
        ConfigRow {
            visible: (Config.options?.location?.mode ?? "auto") === "manual"
            label: "Latitude"
            configKey: "location.latitude"
            sublabel: "Decimal degrees, north positive (e.g. -6.8)"
            ConfigTextInput {
                Layout.preferredWidth: 110
                text: String(Config.options?.location?.latitude ?? 0)
                validator: t => (isFinite(Number(t)) && Math.abs(Number(t)) <= 90) ? "" : "-90 to 90"
                onEditingFinished: if (valid && text) Config.setNestedValue("location.latitude", Number(text))
            }
        }
        ConfigRow {
            visible: (Config.options?.location?.mode ?? "auto") === "manual"
            label: "Longitude"
            configKey: "location.longitude"
            sublabel: "Decimal degrees, east positive (e.g. 39.3)"
            ConfigTextInput {
                Layout.preferredWidth: 110
                text: String(Config.options?.location?.longitude ?? 0)
                validator: t => (isFinite(Number(t)) && Math.abs(Number(t)) <= 180) ? "" : "-180 to 180"
                onEditingFinished: if (valid && text) Config.setNestedValue("location.longitude", Number(text))
            }
        }
    }

    // ═══ Night Light ═══
    SettingsCard {
        icon: "nightlight"
        title: "Night light"
        subtitle: "Warms the screen at night through wlsunset (Hyprland, niri, sway): now, or on a schedule. Plus eye-care screen filters."
        configKeys: ["nightLight", "screenFilter"]

        ConfigRow {
            label: "Screen filter"
            configKey: "screenFilter.mode"
            sublabel: ScreenFilters.supported ? "Grayscale, sepia, high contrast, or colour correction for protan/deutan/tritan vision"
                : `Not available on ${CompositorService.compositor}: it has no screen shader`
            enabled: ScreenFilters.supported
            ChoiceRow {
                compact: false
                model: ScreenFilters.modes.map(m => ({ value: m.id, label: m.label, icon: m.icon }))
                current: ScreenFilters.mode
                onChose: value => ScreenFilters.set(value)
            }
        }

        ConfigSwitch {
            label: "On now"
            configKey: "nightLight.enable"
            sublabel: "The same switch as the night light toggle in the bar, pill and sidebar. Holds the night temperature over any schedule."
            checked: NightLight.enabled
            onCheckedChanged: if (checked !== NightLight.enabled) Config.setNestedValue("nightLight.enable", checked)
        }

        ConfigRow {
            label: "Automatic"
            configKey: "nightLight.schedule"
            sublabel: NightLight.schedule === "sun" ? "Warm from sunset to sunrise where you are"
                : NightLight.schedule === "times" ? "Warm between the times you set"
                : "Only when you turn it on"
            ChoiceRow {
                model: [
                    { value: "off", label: "Off", icon: "block" },
                    { value: "sun", label: "Sunset to sunrise", icon: "wb_twilight" },
                    { value: "times", label: "Set times", icon: "schedule" }
                ]
                current: NightLight.schedule
                onChose: value => Config.setNestedValue("nightLight.schedule", value)
            }
        }

        ConfigRow {
            visible: NightLight.schedule === "times"
            label: "From"
            configKey: "nightLight.start"
            sublabel: "24-hour time, HH:mm"
            ConfigTextInput {
                Layout.preferredWidth: 90
                placeholderText: "20:00"
                text: NightLight.start
                validator: t => NightLight.validTime(t) ? "" : "Use HH:mm, e.g. 20:00"
                onEditingFinished: if (valid && text) Config.setNestedValue("nightLight.start", text)
            }
        }
        ConfigRow {
            visible: NightLight.schedule === "times"
            label: "Until"
            configKey: "nightLight.end"
            sublabel: "24-hour time, HH:mm"
            ConfigTextInput {
                Layout.preferredWidth: 90
                placeholderText: "07:00"
                text: NightLight.end
                validator: t => NightLight.validTime(t) ? "" : "Use HH:mm, e.g. 07:00"
                onEditingFinished: if (valid && text) Config.setNestedValue("nightLight.end", text)
            }
        }
        ConfigSlider {
            visible: NightLight.schedule === "times"
            label: "Fade"
            configKey: "nightLight.fade"
            sublabel: "How long the change from day to night (and back) takes"
            from: 0; to: 120; stepSize: 5
            value: NightLight.fade
            onValueChanged: Config.setNestedValue("nightLight.fade", Math.round(value))
            valueText: `${Math.round(value)} min`
        }

        StyledText {
            visible: NightLight.schedule === "sun"
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: Location.valid ? `Sunset and sunrise for ${Location.city || `${Location.latitude.toFixed(2)}, ${Location.longitude.toFixed(2)}`} (Location card above)`
                : `${Location.problem}: set your location in the Location card above; until then the schedule waits`
            color: Location.valid ? Appearance.colors.colSubtext : Appearance.colors.colWarning
            font.pixelSize: Appearance.font.pixelSize.smaller
        }

        ConfigSlider {
            label: "Night temperature"
            configKey: "nightLight.nightTemp"
            sublabel: "Lower = warmer / more orange"
            from: 2500; to: 6500; stepSize: 100
            value: NightLight.nightTemp
            onValueChanged: Config.setNestedValue("nightLight.nightTemp", Math.round(value))
            valueText: `${Math.round(value)}K`
        }

        ConfigSlider {
            visible: NightLight.scheduled
            label: "Day temperature"
            configKey: "nightLight.dayTemp"
            sublabel: "Outside the night hours (6500K is neutral)"
            from: 4000; to: 6500; stepSize: 100
            value: NightLight.dayTemp
            onValueChanged: Config.setNestedValue("nightLight.dayTemp", Math.round(value))
            valueText: `${Math.round(value)}K`
        }

        ConfigSlider {
            label: "Gamma"
            configKey: "nightLight.gamma"
            sublabel: "Brightness curve while it's on; 1.0 leaves it as is"
            from: 0.5; to: 1.5; stepSize: 0.05
            value: NightLight.gamma
            onValueChanged: Config.setNestedValue("nightLight.gamma", Math.round(value * 100) / 100)
            valueText: value.toFixed(2)
        }

        ConfigRow {
            label: "Monitors"
            configKey: "nightLight.outputs"
            sublabel: NightLight.outputs.length ? "Only the ones picked" : "All of them (pick some to limit it)"
            ChoiceRow {
                model: Quickshell.screens.map(sc => ({ value: sc.name, label: sc.name, icon: "monitor" }))
                current: NightLight.outputs
                onChose: value => {
                    const o = NightLight.outputs.slice(), i = o.indexOf(value)
                    if (i >= 0) o.splice(i, 1); else o.push(value)
                    Config.setNestedValue("nightLight.outputs", o)
                }
            }
        }
    }

    // ═══ Network panel ═══
    SettingsCard {
        icon: "hub"
        title: "Network panel"
        subtitle: "What the bar's network and Bluetooth icons (and the sidebar's Wi-Fi / Bluetooth chevrons) open"
        configKeys: ["network.panelStyle"]

        ConfigRow {
            label: "Network panel style"
            configKey: "network.panelStyle"
            sublabel: (Config.options?.network?.panelStyle ?? "classic") === "orbit"
                ? "Orbit: the animated Network Orbit panel (Wi-Fi, Bluetooth, Ethernet, VPN tabs)"
                : "Classic: the inline network and device pickers"
            ChoiceRow {
                model: [
                    { value: "classic", label: "Classic", icon: "list" },
                    { value: "orbit", label: "Orbit", icon: "hub", enabled: PanelGate.hosted("anoNetworkOrbit") }
                ]
                current: Config.options?.network?.panelStyle ?? "classic"
                onChose: value => Config.setNestedValue("network.panelStyle", value)
            }
        }
    }

    // ═══ Network Usage ═══
    SettingsCard {
        icon: "monitoring"
        title: "Network usage tracking"
        advanced: true // hidden unless Settings shows advanced options (search still finds it)
        subtitle: "Polls /proc/net/dev for per-interface bandwidth. Powers sparkline widgets when consumed by a UI surface."
        configKeys: ["network.usage"]

        ConfigSwitch {
            id: nuEnable
            label: "Enable"
            configKey: "network.usage.enable"
            checked: Config.options?.network?.usage?.enable ?? false
            onCheckedChanged: Config.setNestedValue("network.usage.enable", checked)
        }

        ConfigSlider {
            label: "Poll interval"
            configKey: "network.usage.intervalMs"
            from: 250; to: 5000; stepSize: 250
            enabled: nuEnable.checked
            value: Config.options?.network?.usage?.intervalMs ?? 1000
            onValueChanged: Config.setNestedValue("network.usage.intervalMs", Math.round(value))
            valueText: Format.formatDuration(value)
        }

        ConfigSlider {
            label: "History length"
            configKey: "network.usage.historyLength"
            sublabel: "Number of samples kept for sparkline display"
            from: 10; to: 120; stepSize: 5
            enabled: nuEnable.checked
            value: Config.options?.network?.usage?.historyLength ?? 30
            onValueChanged: Config.setNestedValue("network.usage.historyLength", Math.round(value))
            valueText: `${Math.round(value)} pts`
        }
    }

    // ═══ KDE Connect ═══
    SettingsCard {
        icon: "smartphone"
        title: "KDE Connect"
        subtitle: "Your phone's battery in the bar (module \"Phone\"), ring, ping, clipboard and files; needs kdeconnectd running · off by default"
        configKeys: ["kdeConnect"]

        ConfigSwitch {
            label: "Enable KDE Connect"
            configKey: "kdeConnect.enable"
            sublabel: !(Config.options?.kdeConnect?.enable ?? false) ? "Off: nothing runs"
                : KdeConnect.daemon === "hung" ? "kdeconnectd is running but not answering: restart it"
                : KdeConnect.daemon === "missing" ? "kdeconnectd isn't running (start it from your compositor's autostart)"
                : `${KdeConnect.devices.filter(d => d.paired).length} paired · ${KdeConnect.devices.filter(d => d.paired && d.reachable).length} reachable`
            checked: Config.options?.kdeConnect?.enable ?? false
            onCheckedChanged: Config.setNestedValue("kdeConnect.enable", checked)
        }
        ConfigRow {
            label: "Device"
            configKey: "kdeConnect.device"
            sublabel: "The one the bar shows and actions go to"
            visible: KdeConnect.devices.filter(d => d.paired).length > 1
            ChoiceRow {
                model: [{ value: "", label: "First reachable", icon: "smartphone" }].concat(KdeConnect.devices.filter(d => d.paired).map(d => ({ value: d.id, label: d.name, icon: "smartphone" })))
                current: Config.options?.kdeConnect?.device ?? ""
                onChose: value => Config.setNestedValue("kdeConnect.device", value)
            }
        }
    }

    // ═══ VPN ═══
    SettingsCard {
        icon: "vpn_key"
        title: "VPN"
        subtitle: "Connection status + control for tailscale, netbird, warp, wireguard, or a custom CLI. The active provider is the first entry below with `enabled: true`."
        configKeys: ["vpn"]

        ConfigSwitch {
            id: vpnEnable
            label: "Enable VPN service"
            configKey: "vpn.enable"
            sublabel: "When off, no provider CLI is queried regardless of `providers` content"
            checked: Config.options?.vpn?.enable ?? true
            onCheckedChanged: Config.setNestedValue("vpn.enable", checked)
        }

        ConfigSwitch {
            label: "Notify on state change"
            configKey: "vpn.notifyOnChange"
            sublabel: "Reserved — surfaces can subscribe to statusChanged for their own toasts"
            enabled: vpnEnable.checked
            checked: Config.options?.vpn?.notifyOnChange ?? true
            onCheckedChanged: Config.setNestedValue("vpn.notifyOnChange", checked)
        }

        // Self-hosted NetBird: its management and admin (dashboard) URLs.
        ConfigRow {
            label: "NetBird management URL"
            configKey: "vpn.netbird.managementUrl"
            sublabel: "Your self-hosted server, passed when you connect from the shell; empty keeps the server the profile already uses"
            ConfigTextInput {
                Layout.preferredWidth: 260
                placeholderText: "https://netbird.example.com:443"
                text: Config.options?.vpn?.netbird?.managementUrl ?? ""
                onEditingFinished: Config.setNestedValue("vpn.netbird.managementUrl", text.trim())
            }
        }
        ConfigRow {
            label: "NetBird admin URL"
            configKey: "vpn.netbird.adminUrl"
            sublabel: "The dashboard of that server (for the login page)"
            ConfigTextInput {
                Layout.preferredWidth: 260
                placeholderText: "https://netbird.example.com"
                text: Config.options?.vpn?.netbird?.adminUrl ?? ""
                onEditingFinished: Config.setNestedValue("vpn.netbird.adminUrl", text.trim())
            }
        }

        ConfigRow {
            label: "Active provider"
            sublabel: vpnEnable.checked && VPN.enabled
                ? `${VPN.providerName} · state: ${VPN.status.state}`
                : "(no provider enabled)"
            StyledText {
                text: VPN.connected ? "●" : "○"
                color: VPN.connected
                    ? (Appearance?.colors.colPrimary ?? "#a6e3a1")
                    : Qt.rgba(1, 1, 1, 0.3)
                font.pixelSize: Appearance.font.pixelSize.larger
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: vpnHelp.implicitHeight + 16
            radius: Appearance?.rounding.small ?? 8
            color: Appearance?.colors.colLayer2 ?? "#3a3845"
            border.width: 1
            border.color: Appearance?.colors.colOutlineVariant ?? "#44444466"
            ColumnLayout {
                id: vpnHelp
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6
                StyledText {
                    Layout.fillWidth: true
                    text: "VPN providers must be configured in config.json — supported builtins: tailscale, netbird, warp, wireguard. Custom providers use { name, enabled, connectCmd, disconnectCmd, interface, displayName }."
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    wrapMode: Text.Wrap
                    opacity: 0.75
                }
                RippleButton {
                    implicitHeight: 28
                    buttonRadius: Appearance?.rounding.small ?? 6
                    contentItem: RowLayout {
                        spacing: 6
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        MaterialSymbol { text: "edit"; iconSize: 14 }
                        StyledText { text: "Open config.json"; font.pixelSize: Appearance.font.pixelSize.smaller }
                    }
                    onClicked: DefaultApps.launch(["xdg-open", Directories.userConfigPath])
                }
            }
        }
    }

    // ═══ NetworkManager VPNs ═══
    SettingsCard {
        icon: "vpn_lock"
        title: "NetworkManager VPNs"
        subtitle: "VPN and WireGuard connections set up in NetworkManager (nm-connection-editor, `nmcli connection import`): on or off. The bar's network icon shows a small shield while one is on."

        StyledText {
            visible: Network.vpnConnections.length === 0
            text: "No VPN or WireGuard connections in NetworkManager"
            font.pixelSize: Appearance.font.pixelSize.smaller
            opacity: 0.6
        }

        Repeater {
            model: Network.vpnConnections
            ConfigRow {
                required property var modelData
                label: modelData.name
                sublabel: `${modelData.type === "wireguard" ? "WireGuard" : "VPN"} · ${Network.vpnBusy === modelData.uuid ? "working…" : (modelData.state || "off")}`
                StyledSwitch {
                    Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
                    enabled: Network.vpnBusy === ""
                    checked: modelData.state !== ""
                    onToggled: Network.setVpnActive(modelData.uuid, checked)
                }
            }
        }

        NoticeBox {
            visible: Network.vpnError.length > 0
            level: "error"
            text: Network.vpnError
        }
    }

    // ═══ Calendar (external sync) ═══
    SettingsCard {
        icon: "event"
        title: "Calendar sync"
        subtitle: "Subscribe to ICS/iCal feeds (Google Calendar, work calendars, public schedules). Events appear wherever the calendar surface is rendered."
        configKeys: ["calendar"]

        ConfigSwitch {
            id: calEnable
            label: "Enable"
            configKey: "calendar.externalSync.enable"
            checked: Config.options?.calendar?.externalSync?.enable ?? false
            onCheckedChanged: Config.setNestedValue("calendar.externalSync.enable", checked)
        }

        ConfigSlider {
            label: "Refresh interval"
            configKey: "calendar.externalSync.refreshMinutes"
            from: 5; to: 240; stepSize: 5
            enabled: calEnable.checked
            value: Config.options?.calendar?.externalSync?.refreshMinutes ?? 15
            onValueChanged: Config.setNestedValue("calendar.externalSync.refreshMinutes", Math.round(value))
            valueText: `${Math.round(value)} min`
        }

        ConfigRow {
            label: "Sources"
            sublabel: {
                const n = (Config.options?.calendar?.externalSync?.sources ?? []).length;
                return n === 0
                    ? "No feeds configured. Add iCal/CalDAV URLs to calendar.externalSync.sources in config.json."
                    : `${n} feed${n === 1 ? "" : "s"} configured · ${CalendarSync.events.length} events loaded`;
            }
            RowLayout {
                spacing: 8
                StyledText {
                    text: CalendarSync.fetching ? "syncing…" : (CalendarSync.ready ? "ready" : "idle")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    opacity: 0.6
                    font.family: Appearance?.font.family.mono ?? "monospace"
                }
                RippleButton {
                    implicitHeight: 28
                    buttonRadius: Appearance?.rounding.small ?? 6
                    contentItem: RowLayout {
                        spacing: 6
                        anchors.leftMargin: 10; anchors.rightMargin: 10
                        MaterialSymbol { text: "edit"; iconSize: 14 }
                        StyledText { text: "Open config.json"; font.pixelSize: Appearance.font.pixelSize.smaller }
                    }
                    onClicked: DefaultApps.launch(["xdg-open", Directories.userConfigPath])
                }
            }
        }
    }

    // ═══ Lyrics ═══
    SettingsCard {
        icon: "lyrics"
        title: "Lyrics"
        subtitle: "Synchronized lyrics for the active media player. Reads local .lrc files, falls back to LRCLIB and NetEase online sources."
        configKeys: ["lyrics"]

        ConfigSwitch {
            id: lyEnable
            label: "Enable"
            configKey: "lyrics.enable"
            checked: Config.options?.lyrics?.enable ?? false
            onCheckedChanged: Config.setNestedValue("lyrics.enable", checked)
        }

        ConfigSwitch {
            label: "Visible by default"
            configKey: "lyrics.visible"
            sublabel: "When off, surfaces start collapsed and the user has to toggle"
            enabled: lyEnable.checked
            checked: Config.options?.lyrics?.visible ?? true
            onCheckedChanged: Config.setNestedValue("lyrics.visible", checked)
        }

        // Backend picker (Auto / Local / LRCLIB / NetEase)
        ConfigRow {
            label: "Backend"
            configKey: "lyrics.backend"
            sublabel: {
                const b = Config.options?.lyrics?.backend ?? "Auto";
                if (b === "Local")   return "Local files only — no network calls";
                if (b === "LRCLIB")  return "Online via lrclib.net (open public corpus)";
                if (b === "NetEase") return "Online via music.163.com (Chinese-music coverage)";
                return "Auto: local file → LRCLIB → NetEase";
            }
            enabled: lyEnable.checked

            ChoiceRow {
                compact: false
                itemSpacing: 4
                model: [
                    { value: "Auto", label: "Auto", icon: "auto_awesome" },
                    { value: "Local", label: "Local", icon: "folder" },
                    { value: "LRCLIB", label: "LRCLIB", icon: "cloud" },
                    { value: "NetEase", label: "NetEase", icon: "language" }
                ]
                current: Config.options?.lyrics?.backend ?? "Auto"
                onChose: value => Config.setNestedValue("lyrics.backend", value)
            }
        }

        ConfigRow {
            label: "Lyrics directory"
            configKey: "lyrics.dir"
            sublabel: "Path for local .lrc files. Supports `~` expansion."
            enabled: lyEnable.checked
            StyledTextInput {
                boxed: true
                text: Config.options?.lyrics?.dir ?? "~/.config/anoshell/lyrics"
                onEditingFinished: Config.setNestedValue("lyrics.dir", text.trim())
                Layout.preferredWidth: 220
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }
    }

    // ═══ Shell ═══
    SettingsCard {
        icon: "terminal"
        title: "Shell"
        advanced: true // hidden unless Settings shows advanced options (search still finds it)
        subtitle: "Which shell ano scripts run under. Auto detects from $SHELL; override here when you want bash scripts to run under a specific interpreter."
        configKeys: ["shell"]

        ConfigRow {
            label: "Preferred shell"
            configKey: "shell.preferred"
            sublabel: `Detected from $SHELL: ${ShellExec.detected}. Active: ${ShellExec.current}.`

            RowLayout {
                spacing: 4
                Repeater {
                    model: ["", "bash", "zsh", "fish", "nushell"]
                    RippleButton {
                        required property string modelData
                        implicitHeight: 26
                        buttonRadius: 6
                        toggled: (Config.options?.shell?.preferred ?? "") === modelData
                        colBackgroundToggled: Appearance?.colors.colSecondaryContainer ?? "#E8DEF8"
                        contentItem: StyledText {
                            text: modelData === "" ? "Auto" : modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                        }
                        onClicked: Config.setNestedValue("shell.preferred", modelData)
                    }
                }
            }
        }
    }
}
