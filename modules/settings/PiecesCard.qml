import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

// Desktop pieces (Settings → Modules): the layer's switch and grid, pages
// per screen, and the picker: every piece the registry has (bundled and
// yours in ~/.config/anoshell/pieces), broken ones with their error.
SettingsCard {
    id: card
    icon: "widgets"
    title: "Desktop pieces"
    subtitle: "Cards on the desktop, under your windows, on pages · off by default"
    configKeys: ["pieces"]

    readonly property bool on: Config.options?.pieces?.enable ?? false
    property string screenName: Quickshell.screens[0]?.name ?? ""
    readonly property var layout: Pieces.layoutOf(card.screenName)
    readonly property var shownPage: card.layout.pages[card.layout.page] ?? []
    // The running layer's grid; without it, an estimate from the screen size.
    readonly property var grid: {
        const g = Pieces.grids[card.screenName]
        if (g) return g
        // The screen less what panels reserve on each edge (the layer's window).
        const sc = Quickshell.screens.find(s => s.name === card.screenName), n = card.screenName
        const r = e => PanelRegistry.inset(n, e) + PanelRegistry.foreignInset(n, e)
        return Pieces.gridSize((sc?.width ?? 1280) - r("left") - r("right"), (sc?.height ?? 800) - r("top") - r("bottom"))
    }
    property string message: ""

    // Compile-checks the pieces while the picker is open.
    Component.onCompleted: Pieces.hold(true)
    Component.onDestruction: Pieces.hold(false)

    ConfigSwitch {
        label: "Show desktop pieces"
        configKey: "pieces.enable"
        sublabel: "Clicks on a window never reach them; they pause while a maximised window covers the screen or it's locked"
        checked: card.on
        onCheckedChanged: if (checked !== card.on) Config.setNestedValue("pieces.enable", checked)
    }
    ConfigSlider {
        label: "Grid cell"
        configKey: "pieces.cell"
        sublabel: "Pieces snap to a grid of these squares"
        from: 48; to: 192; stepSize: 8
        value: Config.options?.pieces?.cell ?? 96
        onValueChanged: Config.setNestedValue("pieces.cell", Math.round(value))
        valueText: `${Math.round(value)} px`
    }
    ConfigSlider {
        label: "Gap"
        configKey: "pieces.gap"
        from: 0; to: 40; stepSize: 2
        value: Config.options?.pieces?.gap ?? 12
        onValueChanged: Config.setNestedValue("pieces.gap", Math.round(value))
        valueText: `${Math.round(value)} px`
    }

    ConfigSlider {
        label: "Animation frame rate"
        configKey: "pieces.fps"
        sublabel: "For animated pieces (the Bioma organisms). Each frame redraws the desktop layer: higher is smoother and costs more"
        from: 5; to: 60; stepSize: 5
        value: Config.options?.pieces?.fps ?? 10
        onValueChanged: Config.setNestedValue("pieces.fps", Math.round(value))
        valueText: `${Math.round(value)} fps`
    }
    ConfigRow {
        label: "Arrange"
        sublabel: "Move, resize and remove pieces on the desktop, add pages, change a piece's settings · or right-click a piece · qs ipc call pieces edit"
        enabled: card.on
        RippleButton {
            implicitHeight: 32
            buttonText: "Edit on the desktop"
            onClicked: { GlobalStates.settingsOpen = false; Pieces.editing = true }
        }
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
        sublabel: `Page ${card.layout.page + 1} of ${card.layout.pages.length} · ${card.grid.cols} × ${card.grid.rows} cells · next/previous: qs ipc call pieces next|prev`
        RowLayout {
            spacing: 6
            RippleButton { implicitHeight: 30; buttonText: "Previous"; enabled: card.layout.page > 0; onClicked: Pieces.setPage(card.screenName, card.layout.page - 1) }
            RippleButton { implicitHeight: 30; buttonText: "Next"; enabled: card.layout.page < card.layout.pages.length - 1; onClicked: Pieces.setPage(card.screenName, card.layout.page + 1) }
            RippleButton { implicitHeight: 30; buttonText: "Add page"; onClicked: Pieces.addPage(card.screenName) }
            RippleButton { implicitHeight: 30; buttonText: "Remove page"; onClicked: Pieces.removePage(card.screenName, card.layout.page) }
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
            MaterialSymbol { text: Pieces.usable(placedRow.modelData.id) ? "widgets" : "broken_image"; iconSize: 18; color: Appearance.colors.colOnLayer1 }
            StyledText {
                Layout.fillWidth: true; elide: Text.ElideRight
                text: `${Pieces.entries[placedRow.modelData.id]?.name ?? placedRow.modelData.id} · ${placedRow.modelData.w}×${placedRow.modelData.h} at ${placedRow.modelData.x + 1},${placedRow.modelData.y + 1}`
            }
            RippleButton { implicitHeight: 28; buttonText: "Remove"; onClicked: Pieces.remove(card.screenName, placedRow.modelData.uid) }
        }
    }

    // The picker
    StyledText {
        Layout.topMargin: 6
        text: "Add to this page"
        font.weight: Font.DemiBold
    }
    Repeater {
        model: Pieces.list
        RowLayout {
            id: pick
            required property var modelData
            readonly property var problems: Pieces.errorsOf(modelData.id)
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
                onClicked: card.message = Pieces.add(card.screenName, pick.modelData.id, card.grid.cols, card.grid.rows)
                    ? "" : `No room for ${pick.modelData.name} on this page: add a page or remove a piece`
            }
        }
    }
    RowLayout {
        spacing: 8
        RippleButton {
            implicitHeight: 30
            buttonText: "Open your pieces folder"
            onClicked: DefaultApps.launch(["xdg-open", Pieces.userDir])
        }
        StyledText {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: "A folder there with a piece.json and a QML file is a piece (see docs/pieces.md)"
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
