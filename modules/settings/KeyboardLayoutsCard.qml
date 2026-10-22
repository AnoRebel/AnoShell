import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

// Keyboard layouts (Settings → Keybinds): the XKB catalogue (anod
// keyboard.catalogue, from evdev.xml), searchable, and your layouts in order.
// keyboard.layouts is applied by anod (keyboard.apply) live and into the
// managed compositor file; the bar's keyboard module switches between them.
SettingsCard {
    id: card
    icon: "language"
    title: "Keyboard layouts"
    subtitle: card.layouts.length ? "The first is the default; the keyboard module in the bar switches between them"
        : "None set: your compositor config's layouts are used"
    configKeys: ["keyboard"]

    readonly property var layouts: Array.from(Config.options?.keyboard?.layouts ?? [])
    property var catalogue: []
    property string filter: ""
    property string message: ""
    readonly property var matches: {
        const q = card.filter.trim().toLowerCase()
        if (q.length < 2) return []
        const out = []
        for (const l of card.catalogue) {
            const code = l.variant ? `${l.layout}(${l.variant})` : l.layout
            if (l.description.toLowerCase().includes(q) || code.toLowerCase().includes(q)) out.push(l)
            if (out.length >= 12) break
        }
        return out
    }

    function describe(l) {
        const c = card.catalogue.find(x => x.layout === l.layout && x.variant === (l.variant ?? ""))
        return c?.description ?? (l.variant ? `${l.layout} (${l.variant})` : l.layout)
    }
    function save(list) {
        Config.setNestedValue("keyboard.layouts", list.map(l => ({ layout: l.layout, variant: l.variant ?? "" })))
        applySoon.restart()
    }
    function add(l) {
        if (card.layouts.some(x => x.layout === l.layout && (x.variant ?? "") === l.variant)) return
        card.save(card.layouts.concat([l]))
        card.filter = ""
    }
    function move(i, d) {
        const list = card.layouts.slice(), j = i + d
        if (j < 0 || j >= list.length) return
        const t = list[i]; list[i] = list[j]; list[j] = t
        card.save(list)
    }
    function remove(i) { const list = card.layouts.slice(); list.splice(i, 1); card.save(list) }

    // after the config is on disk: anod reads keyboard.layouts from there
    Timer {
        id: applySoon
        interval: 800
        onTriggered: Anod.call("keyboard.apply", {}, (r, e) => card.message = e ? e.message : "")
    }
    function load() {
        if (Anod.available && !card.catalogue.length)
            Anod.call("keyboard.catalogue", {}, (r, e) => { if (r) card.catalogue = r; else if (e) card.message = e.message })
    }
    Component.onCompleted: load()
    Connections { target: Anod; function onAvailableChanged() { card.load() } }

    Repeater {
        model: card.layouts
        RowLayout {
            id: entry
            required property var modelData
            required property int index
            Layout.fillWidth: true
            spacing: 6
            StyledText {
                text: `${entry.index + 1}`
                color: Appearance.colors.colSubtext
                Layout.preferredWidth: 16
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                StyledText { text: card.describe(entry.modelData); elide: Text.ElideRight; Layout.fillWidth: true }
                StyledText {
                    text: entry.modelData.variant ? `${entry.modelData.layout}(${entry.modelData.variant})` : entry.modelData.layout
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
            }
            RippleButton {
                implicitWidth: 30; implicitHeight: 30; buttonRadius: 15
                enabled: entry.index > 0
                onClicked: card.move(entry.index, -1)
                contentItem: MaterialSymbol { text: "arrow_upward"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                StyledToolTip { text: "Move up" }
            }
            RippleButton {
                implicitWidth: 30; implicitHeight: 30; buttonRadius: 15
                enabled: entry.index < card.layouts.length - 1
                onClicked: card.move(entry.index, 1)
                contentItem: MaterialSymbol { text: "arrow_downward"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                StyledToolTip { text: "Move down" }
            }
            RippleButton {
                implicitWidth: 30; implicitHeight: 30; buttonRadius: 15
                onClicked: card.remove(entry.index)
                contentItem: MaterialSymbol { text: "close"; iconSize: 18; horizontalAlignment: Text.AlignHCenter }
                StyledToolTip { text: "Remove" }
            }
        }
    }

    ConfigTextInput {
        Layout.fillWidth: true
        placeholderText: card.catalogue.length ? `Add a layout: type a language or code (${card.catalogue.length} layouts and variants)` : "Add a layout"
        text: card.filter
        onTextChanged: card.filter = text
    }

    Repeater {
        model: card.matches
        RippleButton {
            id: hit
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: 34
            onClicked: card.add({ layout: hit.modelData.layout, variant: hit.modelData.variant })
            contentItem: RowLayout {
                spacing: 8
                MaterialSymbol { text: "add"; iconSize: 18; Layout.leftMargin: 8 }
                StyledText { text: hit.modelData.description; elide: Text.ElideRight; Layout.fillWidth: true }
                StyledText {
                    text: hit.modelData.variant ? `${hit.modelData.layout}(${hit.modelData.variant})` : hit.modelData.layout
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    Layout.rightMargin: 8
                }
            }
        }
    }

    StyledText {
        visible: card.message.length > 0
        Layout.fillWidth: true; wrapMode: Text.Wrap
        text: card.message
        color: Appearance.colors.colError
        font.pixelSize: Appearance.font.pixelSize.smaller
    }
}
