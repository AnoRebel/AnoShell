import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * A short message at the bottom of Settings (e.g. what Ctrl+Z undid).
 * show(text) shows it for a few seconds.
 */
Rectangle {
    id: root
    function show(message) { label.text = message; root.opacity = 1; hideTimer.restart() }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 24
    z: 100
    implicitWidth: label.implicitWidth + 32
    implicitHeight: 36
    radius: height / 2
    color: Appearance?.colors.colLayer3 ?? "#3a3a3a"
    border.width: 1
    border.color: Appearance?.colors.colOutlineVariant ?? "#55555588"
    opacity: 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(160) } }

    StyledText {
        id: label
        anchors.centerIn: parent
        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
    }
    Timer { id: hideTimer; interval: 2600; onTriggered: root.opacity = 0 }
}
