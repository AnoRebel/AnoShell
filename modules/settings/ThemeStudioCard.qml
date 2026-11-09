import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

// Theme studio (Settings → Appearance): a static theme from 1–3 seed
// colours, previewed before it's saved, with a few roles overridable.
// services/ThemeStudio.qml does the work through anod (theme.*).
SettingsCard {
    id: studio
    icon: "format_paint"
    title: "Theme studio"
    subtitle: "Make a static theme from your own colours; apps follow it like a wallpaper's"
    configKeys: ["appearance.theme.source", "appearance.theme.name"]
    collapsible: true
    expanded: false

    property var schemeChoices: []
    // The seed being edited: primary | secondary | tertiary.
    property string editing: "primary"
    readonly property string editingValue: ThemeStudio[editing] ?? ""
    readonly property string editingHex: editingValue || ThemeStudio.primary || ThemeStudio.hex(Appearance.m3colors.m3primary)
    readonly property color editingColor: ThemeStudio.validHex(editingHex) ? editingHex : Appearance.m3colors.m3primary

    function _setSeed(hex) { ThemeStudio[studio.editing] = hex }
    function _hsl(h, s, l) { _setSeed(ThemeStudio.hex(Qt.hsla(h, s, l, 1))) }

    Component.onCompleted: if (!ThemeStudio.primary) ThemeStudio.startFromCurrent()

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        RippleButton {
            implicitHeight: 32
            buttonRadius: 8
            colBackground: Appearance.colors.colSecondaryContainer
            contentItem: StyledText {
                text: "Start from current colours"
                font.pixelSize: Appearance.font.pixelSize.smaller
                anchors.leftMargin: 12; anchors.rightMargin: 12
            }
            onClicked: ThemeStudio.startFromCurrent()
        }
        Item { Layout.fillWidth: true }
        ChoiceRow {
            model: [{ value: "dark", label: "Dark", icon: "dark_mode" }, { value: "light", label: "Light", icon: "light_mode" }]
            current: ThemeStudio.mode
            onChose: value => ThemeStudio.mode = value
        }
    }

    ChoiceRow {
        Layout.fillWidth: true
        model: studio.schemeChoices
        current: ThemeStudio.schemeType
        onChose: value => ThemeStudio.schemeType = value
    }

    // ─── Seeds: pick one to edit; secondary and tertiary are optional ───
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [{ key: "primary", label: "Primary" }, { key: "secondary", label: "Secondary" }, { key: "tertiary", label: "Tertiary" }]
            RippleButton {
                id: seedTile
                required property var modelData
                readonly property string value: ThemeStudio[modelData.key]
                Layout.fillWidth: true
                implicitHeight: 52
                buttonRadius: 10
                toggled: studio.editing === modelData.key
                colBackground: Appearance.colors.colLayer2
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                onClicked: studio.editing = modelData.key
                contentItem: RowLayout {
                    spacing: 8
                    anchors.leftMargin: 10; anchors.rightMargin: 6
                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28; radius: 14
                        color: ThemeStudio.validHex(seedTile.value) ? seedTile.value : "transparent"
                        border.width: 1
                        border.color: Appearance.colors.colOutlineVariant
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !ThemeStudio.validHex(seedTile.value)
                            text: "auto_awesome"
                            iconSize: 16
                            color: Appearance.colors.colOnLayer2
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText { text: seedTile.modelData.label; font.pixelSize: Appearance.font.pixelSize.smaller }
                        StyledText {
                            text: ThemeStudio.validHex(seedTile.value) ? seedTile.value : "From primary"
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            opacity: 0.6
                        }
                    }
                    RippleButton {
                        visible: seedTile.modelData.key !== "primary" && seedTile.value !== ""
                        implicitWidth: 28; implicitHeight: 28
                        buttonRadius: 14
                        onClicked: ThemeStudio[seedTile.modelData.key] = ""
                        contentItem: MaterialSymbol { text: "close"; iconSize: 16; horizontalAlignment: Text.AlignHCenter }
                        StyledToolTip { text: "Derive it from the primary" }
                    }
                }
            }
        }
    }

    // ─── Picker for the seed being edited: hex, hue, saturation, lightness ───
    ConfigTextInput {
        id: hexInput
        Layout.fillWidth: true
        placeholderText: studio.editing === "primary" ? "#rrggbb" : "#rrggbb (empty: from the primary)"
        Component.onCompleted: text = studio.editingValue
        validator: s => ThemeStudio.validHex(s) ? "" : "Six hex digits after #, like #7c4dff"
        onTextChanged: if (ThemeStudio.validHex(text) && text.toLowerCase() !== studio.editingValue) studio._setSeed(text.toLowerCase())
    }
    // Typing breaks a text binding, so the field follows the seed by hand
    // (another seed picked, a slider moved, "start from current").
    onEditingValueChanged: if (hexInput.text.toLowerCase() !== editingValue) hexInput.text = editingValue
    Repeater {
        model: [{ label: "Hue", part: "h" }, { label: "Saturation", part: "s" }, { label: "Lightness", part: "l" }]
        ColumnLayout {
            id: hslRow
            required property var modelData
            Layout.fillWidth: true
            spacing: 0
            StyledText { text: hslRow.modelData.label; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.7 }
            StyledSlider {
                Layout.fillWidth: true
                from: 0; to: 1
                usePercentTooltip: hslRow.modelData.part !== "h"
                tooltipContent: hslRow.modelData.part === "h" ? `${Math.round(value * 360)}°` : `${Math.round(value * 100)}%`
                value: { const c = studio.editingColor; return hslRow.modelData.part === "h" ? Math.max(0, c.hslHue) : hslRow.modelData.part === "s" ? c.hslSaturation : c.hslLightness }
                onMoved: {
                    const c = studio.editingColor
                    const h = Math.max(0, c.hslHue), s = c.hslSaturation, l = c.hslLightness
                    if (hslRow.modelData.part === "h") studio._hsl(value, s, l)
                    else if (hslRow.modelData.part === "s") studio._hsl(h, value, l)
                    else studio._hsl(h, s, value)
                }
            }
        }
    }

    // ─── Preview (generated, not applied) ───
    Rectangle {
        id: previewBox
        Layout.fillWidth: true
        implicitHeight: previewCol.implicitHeight + 24
        radius: Appearance.rounding.small
        readonly property var p: ThemeStudio.preview
        color: p.surface ?? Appearance.colors.colLayer2
        border.width: 1
        border.color: p.outline_variant ?? Appearance.colors.colOutlineVariant
        opacity: ThemeStudio.busy ? 0.7 : 1
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(150) } }
        ColumnLayout {
            id: previewCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 10
            RowLayout {
                spacing: 8
                Rectangle {
                    implicitWidth: btnText.implicitWidth + 24; implicitHeight: 32; radius: 16
                    color: previewBox.p.primary ?? "grey"
                    StyledText { id: btnText; anchors.centerIn: parent; text: "Primary"; color: previewBox.p.on_primary ?? "black" }
                }
                Rectangle {
                    implicitWidth: btn2.implicitWidth + 24; implicitHeight: 32; radius: 16
                    color: previewBox.p.secondary_container ?? "grey"
                    StyledText { id: btn2; anchors.centerIn: parent; text: "Secondary"; color: previewBox.p.on_secondary_container ?? "black" }
                }
                Rectangle {
                    implicitWidth: btn3.implicitWidth + 24; implicitHeight: 32; radius: 16
                    color: previewBox.p.tertiary_container ?? "grey"
                    StyledText { id: btn3; anchors.centerIn: parent; text: "Tertiary"; color: previewBox.p.on_tertiary_container ?? "black" }
                }
                Item { Layout.fillWidth: true }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cardText.implicitHeight + 20
                radius: 10
                color: previewBox.p.surface_container_high ?? "grey"
                StyledText {
                    id: cardText
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 10 }
                    text: "Text on a raised surface, with a <font color=\"" + (previewBox.p.primary ?? "grey") + "\">link</font>"
                    textFormat: Text.StyledText
                    color: previewBox.p.on_surface ?? "white"
                }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 6; columnSpacing: 6; rowSpacing: 6
                Repeater {
                    model: ["primary", "primary_container", "secondary", "secondary_container", "tertiary", "tertiary_container",
                        "background", "surface_container", "surface_container_highest", "on_surface", "outline", "error"]
                    Rectangle {
                        id: swatch
                        required property string modelData
                        Layout.fillWidth: true
                        implicitHeight: 24
                        radius: 6
                        color: previewBox.p[modelData] ?? "transparent"
                        border.width: 1
                        border.color: previewBox.p.outline_variant ?? Appearance.colors.colOutlineVariant
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            StyledToolTip { text: `${swatch.modelData.replace(/_/g, " ")}\n${swatch.color}` }
                        }
                    }
                }
            }
        }
    }

    // ─── Per-role overrides ───
    StyledText {
        text: "Overrides (empty: the generated colour)"
        font.pixelSize: Appearance.font.pixelSize.smaller
        opacity: 0.7
    }
    GridLayout {
        Layout.fillWidth: true
        columns: 2; columnSpacing: 8; rowSpacing: 6
        Repeater {
            model: ThemeStudio.overrideRoles
            RowLayout {
                id: overrideRow
                required property string modelData
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    implicitWidth: 20; implicitHeight: 20; radius: 10
                    color: ThemeStudio.preview[overrideRow.modelData] ?? "transparent"
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                }
                StyledText {
                    text: overrideRow.modelData.replace(/_/g, " ")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    Layout.preferredWidth: 110
                    elide: Text.ElideRight
                }
                ConfigTextInput {
                    id: overrideInput
                    Layout.fillWidth: true
                    placeholderText: ThemeStudio.preview[overrideRow.modelData] ?? "#rrggbb"
                    Component.onCompleted: text = ThemeStudio.overrides[overrideRow.modelData] ?? ""
                    Connections {
                        target: ThemeStudio
                        function onOverridesChanged() { overrideInput.text = ThemeStudio.overrides[overrideRow.modelData] ?? "" }
                    }
                    validator: s => ThemeStudio.validHex(s) ? "" : "#rrggbb"
                    onEditingFinished: if (text === "" || ThemeStudio.validHex(text)) ThemeStudio.setOverride(overrideRow.modelData, text)
                }
            }
        }
    }

    // ─── Name, save, apply ───
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        ConfigTextInput {
            id: nameInput
            Layout.fillWidth: true
            placeholderText: "Theme name"
            Component.onCompleted: text = ThemeStudio.name
            onTextChanged: ThemeStudio.name = text
            Connections {
                target: ThemeStudio
                function onNameChanged() { if (nameInput.text !== ThemeStudio.name) nameInput.text = ThemeStudio.name }
            }
        }
        RippleButton {
            implicitHeight: 32
            buttonRadius: 8
            enabled: ThemeStudio.slug.length > 0 && !ThemeStudio.busy
            opacity: enabled ? 1 : 0.4
            colBackground: Appearance.colors.colSecondaryContainer
            contentItem: StyledText { text: "Save"; font.pixelSize: Appearance.font.pixelSize.smaller; anchors.leftMargin: 12; anchors.rightMargin: 12 }
            onClicked: ThemeStudio.save(false)
        }
        RippleButton {
            implicitHeight: 32
            buttonRadius: 8
            enabled: ThemeStudio.slug.length > 0 && !ThemeStudio.busy
            opacity: enabled ? 1 : 0.4
            colBackground: Appearance.colors.colPrimary
            contentItem: StyledText { text: "Save and apply"; color: Appearance.colors.colOnPrimary; font.pixelSize: Appearance.font.pixelSize.smaller; anchors.leftMargin: 12; anchors.rightMargin: 12 }
            onClicked: ThemeStudio.save(true)
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: text.length > 0
        text: !Anod.available ? "anod isn't running: the studio needs it (and matugen) to make schemes" : ThemeStudio.error
        color: Appearance.m3colors.m3error
        font.pixelSize: Appearance.font.pixelSize.smaller
        wrapMode: Text.Wrap
    }
    StyledText {
        Layout.fillWidth: true
        visible: ThemeStudio.slug.length > 0
        text: `Saves as ${ThemeStudio.slug}.json in your themes folder; it's listed with the static themes.`
        font.pixelSize: Appearance.font.pixelSize.smallest
        opacity: 0.6
        wrapMode: Text.Wrap
    }

    // ─── Your studio themes ───
    Repeater {
        model: ThemeStudio.studioThemes
        RowLayout {
            id: mine
            required property string modelData
            readonly property var t: ThemeRegistry.themeContents[modelData] ?? ({})
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: ["primary", "secondary", "tertiary", "surface"]
                Rectangle {
                    required property string modelData
                    implicitWidth: 16; implicitHeight: 16; radius: 8
                    color: mine.t[modelData] ?? "transparent"
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                }
            }
            StyledText { Layout.fillWidth: true; text: mine.t._meta?.name ?? mine.modelData; elide: Text.ElideRight }
            RippleButton {
                implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                onClicked: ThemeStudio.load(mine.modelData)
                contentItem: MaterialSymbol { text: "edit"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                StyledToolTip { text: "Edit" }
            }
            // Two clicks: the first arms it for a few seconds.
            RippleButton {
                id: delBtn
                property bool armed: false
                implicitWidth: 32; implicitHeight: 32; buttonRadius: 16
                toggled: armed
                colBackgroundToggled: Appearance.m3colors.m3errorContainer
                onClicked: {
                    if (!armed) { armed = true; disarm.restart(); return }
                    armed = false
                    ThemeStudio.remove(mine.modelData)
                }
                contentItem: MaterialSymbol { text: delBtn.armed ? "delete_forever" : "delete"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                StyledToolTip { text: delBtn.armed ? "Click again to delete" : "Delete" }
                Timer { id: disarm; interval: 3000; onTriggered: delBtn.armed = false }
            }
        }
    }
}
