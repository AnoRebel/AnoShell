import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

/**
 * A settings row for choosing a font family. Presents an editable dropdown
 * populated from the installed families (FontService / fc-list) so users can
 * pick or type a family, and flags when the current value isn't installed.
 *
 * Usage:
 *   FontPickerRow {
 *       label: "Main font"
 *       value: Config.options?.appearance?.fonts?.main ?? ""
 *       onChosen: v => Config.setNestedValue("appearance.fonts.main", v)
 *   }
 */
ConfigRow {
    id: root

    property string value: ""
    signal chosen(string family)

    readonly property bool installed: value.length === 0 || FontService.isInstalled(value)

    ColumnLayout {
        Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
        spacing: 2

        ComboBox {
            id: combo
            Layout.preferredWidth: 220
            editable: true
            model: FontService.families
            // Show the configured value even before/after the model loads.
            editText: root.value

            // Keep the field in sync when the config value changes externally.
            Connections {
                target: root
                function onValueChanged() {
                    if (combo.editText !== root.value) combo.editText = root.value;
                }
            }

            // Commit on selection from the list…
            onActivated: idx => {
                const fam = String(model[idx]);
                if (fam !== root.value) root.chosen(fam);
            }
            // …or on typing + Enter / focus-out.
            onAccepted: {
                if (editText.length > 0 && editText !== root.value) root.chosen(editText);
            }

            // Render each family in its own typeface for a live preview.
            delegate: ItemDelegate {
                width: combo.width
                contentItem: StyledText {
                    text: modelData
                    font.family: modelData
                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                    elide: Text.ElideRight
                }
                highlighted: combo.highlightedIndex === index
            }

            contentItem: TextField {
                text: combo.editText
                onTextEdited: combo.editText = text
                font.family: root.installed ? root.value : (Appearance?.font.family.main ?? "sans-serif")
                font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                verticalAlignment: Text.AlignVCenter
                onEditingFinished: combo.accepted()
            }

            background: Rectangle {
                radius: Appearance?.rounding.small ?? 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                border.width: 1
                border.color: root.installed
                    ? (Appearance?.colors.colOutlineVariant ?? "#44444488")
                    : (Appearance?.colors.colError ?? "#F2B8B5")
            }
        }

        // "Not installed" hint with an install suggestion.
        StyledText {
            visible: !root.installed && root.value.length > 0
            text: `⚠ "${root.value}" isn't installed — pick another or install it`
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 11
            color: Appearance?.colors.colError ?? "#F2B8B5"
            Layout.preferredWidth: 220
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignRight
        }
    }
}
