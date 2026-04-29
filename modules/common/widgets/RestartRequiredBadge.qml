import qs.modules.common
import QtQuick

/**
 * Restart-required marker. Place next to a Settings field's label to
 * signal that changes only apply after a shell reload.
 *
 * Usage:
 *   RowLayout {
 *       StyledText { text: "Default compositor" }
 *       RestartRequiredBadge {}
 *   }
 *
 * Tooltip text is fixed across the codebase ("Takes effect after Reload
 * Shell.") to keep the language uniform — pages SHOULD NOT customise it.
 */
Item {
    id: root
    implicitWidth: 16
    implicitHeight: 16

    MaterialSymbol {
        anchors.centerIn: parent
        text: "restart_alt"
        iconSize: 12
        color: Appearance?.colors.colSubtext ?? "#CAC4D0"
        opacity: 0.8
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
    }

    StyledToolTip {
        text: "Takes effect after Reload Shell."
        visible: ma.containsMouse
    }
}
