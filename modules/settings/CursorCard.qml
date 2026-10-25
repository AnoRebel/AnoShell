import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

// Cursor theme and size (Settings → Displays): anod applies and persists it.
SettingsCard {
    id: cursorCard
    icon: "arrow_selector_tool"
    title: "Cursor"
    subtitle: "Pointer theme and size · live, and for apps started later"
    configKeys: ["cursor"]

    property var themes: []
    property int pendingSize: 24
    Timer {
        id: cursorSizeDebounce
        interval: 500
        onTriggered: if (cursorCard.pendingSize !== (Config.options?.cursor?.size ?? 24))
            cursorCard.apply(Config.options?.cursor?.theme ?? "", cursorCard.pendingSize)
    }
    // The palette cursors are listed before they're first built (choosing one builds it).
    property string loadError: ""
    function load() {
        if (!Anod.available) return
        cursorCard.loadError = ""
        Anod.call("cursor.themes", {}, (r, e) => {
            if (!r) { cursorCard.loadError = e?.message ?? "no answer"; return }
            const missing = PaletteThemes.cursorIds.filter(id => !r.some(t => t.name === id))
                .map(id => ({ name: id, title: id === "anoshell-cursor" ? "AnoShell" : "AnoShell Cell", preview: "" }))
            cursorCard.themes = missing.concat(r)
        })
    }
    function apply(theme, size) {
        const was = Config.options?.cursor?.theme ?? ""
        Config.setNestedValue("cursor.theme", theme)
        Config.setNestedValue("cursor.size", size)
        if (!PaletteThemes.cursorIds.includes(theme)) { if (theme !== "") Anod.call("cursor.apply", { theme: theme, size: size }) }
        else if (theme === was) PaletteThemes.applyCursor() // a new size; a new theme applies once built
    }
    Component.onCompleted: load()
    Connections { target: PaletteThemes; function onCursorBuilt() { cursorCard.load() } }

    NoticeBox {
        Layout.fillWidth: true
        visible: !Anod.available
        text: "The cursor is applied by anod, which isn't running."
    }
    NoticeBox {
        Layout.fillWidth: true
        visible: Anod.available && cursorCard.loadError.length > 0
        level: "error"
        text: `Couldn't list the cursor themes: ${cursorCard.loadError}`
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: cursorCard.themes
            delegate: RippleButton {
                required property var modelData
                implicitWidth: 96
                implicitHeight: 84
                toggled: (Config.options?.cursor?.theme ?? "") === modelData.name
                onClicked: cursorCard.apply(modelData.name, Config.options?.cursor?.size ?? 24)
                contentItem: ColumnLayout {
                    spacing: 4
                    Image {
                        Layout.alignment: Qt.AlignHCenter
                        source: modelData.preview ? "file://" + modelData.preview : ""
                        cache: false // a palette cursor's preview is redrawn in place
                        sourceSize: Qt.size(40, 40)
                        Layout.preferredWidth: 40; Layout.preferredHeight: 40
                        fillMode: Image.PreserveAspectFit
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: modelData.title
                    }
                }
            }
        }
    }
    ConfigSlider {
        label: "Size"
        configKey: "cursor.size"
        sublabel: "Applies to the theme above"
        from: 16; to: 96; stepSize: 4
        value: Config.options?.cursor?.size ?? 24
        // Applied once the slider settles, not on every step.
        onValueChanged: { cursorCard.pendingSize = Math.round(value); cursorSizeDebounce.restart() }
        valueText: `${Math.round(value)} px`
    }
    RippleButton {
        visible: (Config.options?.cursor?.theme ?? "") !== ""
        buttonText: "Leave the cursor to my compositor config"
        onClicked: Config.setNestedValue("cursor.theme", "")
    }
}
