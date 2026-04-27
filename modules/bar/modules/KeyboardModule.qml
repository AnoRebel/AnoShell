import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"
import QtQuick

/**
 * Keyboard layout indicator. Shows current XKB layout code.
 * Only visible when multiple layouts are configured.
 */
Item {
    id: root
    visible: KeyboardLayoutService.layoutCodes.length > 1
    implicitWidth: visible ? label.implicitWidth + 12 : 0
    implicitHeight: Appearance.sizes.barHeight

    StyledText {
        id: label
        anchors.centerIn: parent
        text: KeyboardLayoutService.currentLayoutCode.toUpperCase()
        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        StyledToolTip { text: KeyboardLayoutService.currentLayoutName }
    }
}
