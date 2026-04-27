import QtQuick
import QtQuick.Layouts
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

/**
 * Services settings — elaborate AI model configuration, weather service,
 * resource monitor, brightness device, and clipboard config.
 */
ColumnLayout {
    spacing: 16

    // ═══ AI Chat ═══
    SettingsCard {
        icon: "neurology"
        title: "AI Chat"
        subtitle: "Model configuration, API keys, system prompt, and temperature"

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
                    color: Ai.currentModelHasApiKey ? "#81C784" : Appearance?.m3colors.m3error ?? "#BA1A1A"
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
                        color: Ai.currentModelHasApiKey ? "#81C784" : Appearance?.m3colors.m3error ?? "#BA1A1A"
                    }
                }
                ColumnLayout {
                    spacing: 1
                    StyledText { text: "Tokens"; font.pixelSize: 10; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
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
            sublabel: "One of: " + Ai.modelList.join(", ")
            StyledTextInput {
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
                                text: `${Ai.models[modelData]?.api_format ?? "?"} • ${Ai.models[modelData]?.description ?? ""}`
                                font.pixelSize: Appearance?.font.pixelSize.smallest ?? 11
                                opacity: 0.5; elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }
                        // API key status
                        MaterialSymbol {
                            text: Ai.apiKeys[Ai.models[modelData]?.key_id]?.length > 0 ? "key" : "key_off"
                            iconSize: 16
                            color: Ai.apiKeys[Ai.models[modelData]?.key_id]?.length > 0 ? "#81C784" : Appearance?.colors.colSubtext ?? "#888"
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
            sublabel: "Creativity/randomness: 0 = deterministic, 2 = very creative"
            from: 0; to: 2; stepSize: 0.1
            value: Config.options?.ai?.temperature ?? 0.5
            onValueChanged: Config.setNestedValue("ai.temperature", value)
            valueText: `${value.toFixed(1)}`
        }

        ColumnLayout {
            spacing: 4
            StyledText { text: "System prompt"; font.weight: Font.DemiBold; font.pixelSize: Appearance?.font.pixelSize.small ?? 14 }
            StyledTextArea {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                text: Config.options?.ai?.systemPrompt ?? "You are a helpful assistant integrated into a Linux desktop shell called Ano."
                onEditingFinished: Config.setNestedValue("ai.systemPrompt", text)
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 13
            }
        }

        NoticeBox {
            text: "API keys are managed via the /key command in the AI chat sidebar and stored securely in api_keys.json. Supported providers: OpenAI, Google Gemini, Anthropic Claude."
            iconName: "security"
        }
    }

    // ═══ Resources Monitor ═══
    SettingsCard {
        icon: "monitor_heart"
        title: "Resources Monitor"
        subtitle: "CPU, RAM, network polling frequency and history"

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
                    StyledText { text: modelData.text; font.pixelSize: 11; font.family: Appearance?.font.family.mono; Layout.alignment: Qt.AlignHCenter }
                    StyledText { text: modelData.label; font.pixelSize: 10; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance?.colors.colOutlineVariant ?? "#C4C7C5"; opacity: 0.2 }

        ConfigSlider {
            label: "Update interval"
            sublabel: "How often /proc is polled for CPU/RAM/network data"
            from: 500; to: 10000; stepSize: 500
            value: Config.options?.resources?.updateInterval ?? 3000
            onValueChanged: Config.setNestedValue("resources.updateInterval", Math.round(value))
            valueText: `${(Math.round(value) / 1000).toFixed(1)}s`
        }

        ConfigSlider {
            label: "History length"
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
        subtitle: "Backlight device override"

        ConfigRow {
            label: "Device name"
            sublabel: "Leave empty for auto-detect. Use 'brightnessctl -l' to list devices."
            StyledTextInput {
                text: Config.options?.light?.device ?? ""
                onEditingFinished: Config.setNestedValue("light.device", text)
                Layout.preferredWidth: 200
                font.family: Appearance?.font.family.mono ?? "monospace"
            }
        }
    }
}
