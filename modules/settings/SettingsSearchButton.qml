import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets

/**
 * The visible way into the settings search (the Ctrl+K palette): a field at
 * the top of the page list in both Settings windows. Clicking it opens the
 * palette, which searches every option by its label, description or key and
 * jumps to its card.
 */
Rectangle {
    id: root
    Layout.fillWidth: true
    implicitHeight: 36
    radius: Appearance?.rounding.full ?? 18
    color: area.containsMouse ? (Appearance?.colors.colLayer2Hover ?? "#3C3947") : (Appearance?.colors.colLayer2 ?? "#2B2930")
    border.width: 1
    border.color: Appearance?.colors.colOutlineVariant ?? "#49454F"
    Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(100) } }

    RowLayout {
        anchors { fill: parent; leftMargin: 12; rightMargin: 6 }
        spacing: 8
        MaterialSymbol { text: "search"; iconSize: 18; color: Appearance?.colors.colSubtext ?? "#CAC4D0" }
        StyledText {
            Layout.fillWidth: true
            text: "Search"
            elide: Text.ElideRight
            color: Appearance?.colors.colSubtext ?? "#CAC4D0"
            font.pixelSize: Appearance?.font.pixelSize.small ?? 14
        }
        Rectangle {
            implicitWidth: keyHint.implicitWidth + 12; implicitHeight: 22
            radius: Appearance?.rounding.small ?? 8
            color: Appearance?.colors.colLayer1 ?? "#1C1B1F"
            StyledText {
                id: keyHint
                anchors.centerIn: parent
                text: "Ctrl K"
                color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                font.pixelSize: Appearance?.font.pixelSize.smallest ?? 10
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: GlobalStates.settingsCommandPaletteOpen = true
    }
}
