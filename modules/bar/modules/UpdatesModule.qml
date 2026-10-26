import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Pending package updates (bar module ID "updates", needs updates.enable).
 * Shown only while there are updates or the last check failed; click opens
 * the update in the terminal, right click checks again.
 */
Item {
    id: root

    visible: Updates.enabled && (Updates.count > 0 || Updates.error.length > 0)
    implicitWidth: visible ? row.implicitWidth + 12 : 0
    implicitHeight: Appearance.sizes.barHeight

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4
        MaterialSymbol {
            text: Updates.error ? "sync_problem" : "system_update_alt"
            iconSize: 16
            color: Updates.error ? Appearance.colors.colError : (Appearance?.colors.colPrimary ?? "#a6e3a1")
        }
        StyledText {
            visible: Updates.count > 0
            text: Updates.count
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: Appearance.font.family.numbers
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.RightButton ? Updates.check() : Updates.update()
        StyledToolTip {
            text: Updates.error ? `Couldn't check for updates: ${Updates.error} · right click to retry`
                : `${Updates.count} update${Updates.count === 1 ? "" : "s"}`
                    + (Updates.aurCount ? ` (${Updates.aurCount} from the AUR)` : "")
                    + "\n" + Updates.packages.slice(0, 12).join("\n")
                    + (Updates.packages.length > 12 ? `\n… and ${Updates.packages.length - 12} more` : "")
                    + "\nClick to update in the terminal · right click to check again"
        }
    }
}
