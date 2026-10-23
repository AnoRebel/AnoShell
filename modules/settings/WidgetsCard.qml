import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

// Desktop widgets (Settings → Modules): the layer's switch and grid, pages
// per screen, and the picker: every widget the registry has (bundled and
// yours in ~/.config/anoshell/widgets), broken ones with their error.
SettingsCard {
    id: card
    icon: "widgets"
    title: "Desktop widgets"
    subtitle: "Cards on the desktop, under your windows, on pages · off by default"
    configKeys: ["widgets"]

    readonly property bool on: Config.options?.widgets?.enable ?? false
    property string screenName: Quickshell.screens[0]?.name ?? ""
    readonly property var layout: Widgets.layoutOf(card.screenName)
    readonly property var shownPage: card.layout.pages[card.layout.page] ?? []
    // The running layer's grid; without it, an estimate from the screen size.
    readonly property var grid: {
        const g = Widgets.grids[card.screenName]
        if (g) return g
        const sc = Quickshell.screens.find(s => s.name === card.screenName)
        const cell = Config.options?.widgets?.cell ?? 96, gap = Config.options?.widgets?.gap ?? 12
        return { cols: Math.max(1, Math.floor(((sc?.width ?? 1280) - 48 + gap) / (cell + gap))),
                 rows: Math.max(1, Math.floor(((sc?.height ?? 800) - 140 + gap) / (cell + gap))) }
    }
    property string message: ""

    // Compile-checks the widgets while the picker is open.
    Component.onCompleted: Widgets.hold(true)
    Component.onDestruction: Widgets.hold(false)

    ConfigSwitch {
        label: "Show desktop widgets"
        configKey: "widgets.enable"
        sublabel: "Clicks on a window never reach them; they pause while a maximised window covers the screen or it's locked"
        checked: card.on
        onCheckedChanged: if (checked !== card.on) Config.setNestedValue("widgets.enable", checked)
    }
    ConfigSlider {
        label: "Grid cell"
        configKey: "widgets.cell"
        sublabel: "Widgets snap to a grid of these squares"
        from: 48; to: 192; stepSize: 8
        value: Config.options?.widgets?.cell ?? 96
        onValueChanged: Config.setNestedValue("widgets.cell", Math.round(value))
        valueText: `${Math.round(value)} px`
    }
    ConfigSlider {
        label: "Gap"
        configKey: "widgets.gap"
        from: 0; to: 40; stepSize: 2
        value: Config.options?.widgets?.gap ?? 12
        onValueChanged: Config.setNestedValue("widgets.gap", Math.round(value))
        valueText: `${Math.round(value)} px`
    }

    ConfigRow {
        label: "Screen"
        visible: Quickshell.screens.length > 1
        ChoiceRow {
            model: Quickshell.screens.map(s => ({ value: s.name, label: s.name, icon: "monitor" }))
            current: card.screenName
            onChose: value => card.screenName = value
        }
    }
    ConfigRow {
        label: "Pages"
        sublabel: `Page ${card.layout.page + 1} of ${card.layout.pages.length} · ${card.grid.cols} × ${card.grid.rows} cells · next/previous: qs ipc call widgets next|prev`
        RowLayout {
            spacing: 6
            RippleButton { implicitHeight: 30; buttonText: "Previous"; enabled: card.layout.page > 0; onClicked: Widgets.setPage(card.screenName, card.layout.page - 1) }
            RippleButton { implicitHeight: 30; buttonText: "Next"; enabled: card.layout.page < card.layout.pages.length - 1; onClicked: Widgets.setPage(card.screenName, card.layout.page + 1) }
            RippleButton { implicitHeight: 30; buttonText: "Add page"; onClicked: Widgets.addPage(card.screenName) }
            RippleButton { implicitHeight: 30; buttonText: "Remove page"; onClicked: Widgets.removePage(card.screenName, card.layout.page) }
        }
    }

    // On the shown page
    Repeater {
        model: card.shownPage
        RowLayout {
            id: placedRow
            required property var modelData
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol { text: Widgets.usable(placedRow.modelData.id) ? "widgets" : "broken_image"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
            StyledText {
                Layout.fillWidth: true; elide: Text.ElideRight
                text: `${Widgets.entries[placedRow.modelData.id]?.name ?? placedRow.modelData.id} · ${placedRow.modelData.w}×${placedRow.modelData.h} at ${placedRow.modelData.x + 1},${placedRow.modelData.y + 1}`
            }
            RippleButton { implicitHeight: 28; buttonText: "Remove"; onClicked: Widgets.remove(card.screenName, placedRow.modelData.uid) }
        }
    }

    // The picker
    StyledText {
        Layout.topMargin: 6
        text: "Add to this page"
        font.weight: Font.DemiBold
    }
    Repeater {
        model: Widgets.list
        RowLayout {
            id: pick
            required property var modelData
            readonly property var problems: Widgets.errorsOf(modelData.id)
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: pick.problems.length ? "broken_image" : "widgets"
                iconSize: 20
                color: pick.problems.length ? Appearance.colors.colError : Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 0
                StyledText {
                    Layout.fillWidth: true; elide: Text.ElideRight
                    text: `${pick.modelData.name} · ${pick.modelData.size.w}×${pick.modelData.size.h}` + (pick.modelData.source === "user" ? " · yours" : "")
                }
                StyledText {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: pick.problems.length ? pick.problems.join("; ") : pick.modelData.description
                    color: pick.problems.length ? Appearance.colors.colError : Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
            RippleButton {
                implicitHeight: 30
                buttonText: "Add"
                enabled: pick.problems.length === 0
                onClicked: card.message = Widgets.add(card.screenName, pick.modelData.id, card.grid.cols, card.grid.rows)
                    ? "" : `No room for ${pick.modelData.name} on this page: add a page or remove a widget`
            }
        }
    }
    RowLayout {
        spacing: 8
        RippleButton {
            implicitHeight: 30
            buttonText: "Open your widgets folder"
            onClicked: DefaultApps.launch(["xdg-open", Widgets.userDir])
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "A folder there with a widget.json and a QML file is a widget (see docs/widgets.md)"
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
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
