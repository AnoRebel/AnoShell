import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The system section's Bubble style: a small live bubble view and a button that opens the full-screen Bubble Monitor,
 * revealed from the button.
 */
Item {
    id: root
    property bool live: true
    implicitHeight: 210

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: Qt.darker(Appearance.colors.colLayer2, 1.25)
        clip: true
        BubbleWorld {
            anchors.fill: parent
            full: false
            live: root.live && root.visible
        }
    }
    StyledText {
        anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
        visible: !SysMon.available
        text: "Processes need anod (ano start)"
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colSubtext
    }
    ToolbarButton {
        id: fullButton
        anchors { top: parent.top; right: parent.right; margins: 4 }
        iconName: "open_in_full"; iconSize: 16
        toolTipText: "Bubble Monitor"
        onClicked: {
            // Where the reveal grows from: x counted from the right edge (this is the right sidebar).
            const p = fullButton.mapToItem(null, fullButton.width / 2, fullButton.height / 2)
            const w = fullButton.QsWindow.window?.width ?? 0
            GlobalStates.bubbleMonitorOrigin = Qt.point(p.x - w, p.y)
            GlobalStates.bubbleMonitorOpen = true
        }
    }
}
