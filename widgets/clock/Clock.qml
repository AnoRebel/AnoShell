import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// Bundled widget: the time and date. The host (modules/widgets) sets ctx
// (live, screenName) and settings; timers run only while ctx.live.
Item {
    id: root
    property var ctx
    property var settings: ({})
    readonly property bool seconds: root.settings?.seconds ?? false

    property date now: new Date()
    Timer {
        // to the next second or minute boundary, then on it
        running: root.ctx?.live ?? false
        repeat: true
        triggeredOnStart: true
        interval: root.seconds ? 1000 - root.now.getMilliseconds() : 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds())
        onTriggered: root.now = new Date()
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 0
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(root.now, root.seconds ? "hh:mm:ss" : (Config.options?.time?.format ?? "hh:mm"))
            font.pixelSize: Math.min(root.height * 0.5, root.width / (root.seconds ? 5.2 : 3.4))
            font.weight: Font.Light
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(root.now, "dddd d MMMM")
            font.pixelSize: Math.max(12, root.height * 0.12)
            color: Appearance.colors.colSubtext
        }
    }
}
