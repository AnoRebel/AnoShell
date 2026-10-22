import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

// Desktop icon theme (Settings → Displays): GTK and qt5ct/qt6ct. The AnoShell
// ones are drawn in the wallpaper's colours (services/PaletteThemes.qml).
SettingsCard {
    id: iconsCard
    icon: "folder_special"
    title: "Icons"
    subtitle: "Icon theme for apps · the AnoShell ones follow the wallpaper"
    configKeys: ["icons"]

    readonly property string current: Config.options?.icons?.theme ?? ""
    readonly property string base: Config.options?.icons?.base ?? "Papirus-Dark"
    property string filter: ""
    // The palette themes (listed before they're first built), the current one
    // and the base; the rest of what's installed only when the filter finds them.
    readonly property var themes: {
        const listed = PaletteThemes.iconThemes
        const ours = PaletteThemes.iconIds.map(id => listed.find(t => t.id === id)
            ?? { id: id, name: ({ "anoshell-icons": "AnoShell", "anoshell-icons-primary": "AnoShell Primary", "anoshell-icons-tint": "AnoShell Tint" })[id] })
        const q = iconsCard.filter.trim().toLowerCase()
        const rest = listed.filter(t => !PaletteThemes.iconIds.includes(t.id)
            && (q ? (t.name.toLowerCase().includes(q) || t.id.toLowerCase().includes(q))
                  : (t.id === iconsCard.current || t.id === iconsCard.base)))
        return ours.concat(rest.slice(0, 30))
    }
    Component.onCompleted: PaletteThemes.refresh()

    ConfigTextInput {
        Layout.fillWidth: true
        placeholderText: `Find an icon theme (${PaletteThemes.iconThemes.length} installed)`
        text: iconsCard.filter
        onTextChanged: iconsCard.filter = text
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: iconsCard.themes
            delegate: RippleButton {
                id: chip
                required property var modelData
                readonly property bool palette: PaletteThemes.iconIds.includes(modelData.id)
                implicitHeight: 34
                implicitWidth: chipRow.implicitWidth + 24
                buttonRadius: height / 2
                colBackgroundToggled: Appearance.colors.colSecondaryContainer
                toggled: iconsCard.current === modelData.id
                onClicked: PaletteThemes.setIconTheme(modelData.id)
                contentItem: RowLayout {
                    id: chipRow
                    spacing: 6
                    MaterialSymbol {
                        visible: chip.palette
                        text: "palette"
                        iconSize: 16
                        color: Appearance.colors.colPrimary
                    }
                    StyledText {
                        text: chip.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: chip.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: `AnoShell and AnoShell Primary draw their own folders and file types; AnoShell Tint keeps ${iconsCard.base}'s folders in the palette's colour. Apps and the rest come from ${iconsCard.base} (the last other theme you picked).`
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
    RippleButton {
        visible: iconsCard.current !== ""
        buttonText: "Leave icons to my desktop settings"
        onClicked: Config.setNestedValue("icons.theme", "")
    }
}
