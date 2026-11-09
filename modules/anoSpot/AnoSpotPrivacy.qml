import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Live activity: the camera or the microphone in use (services/Privacy).
 * A coloured dot each (camera green, microphone orange, as phones do); the
 * apps' names open beside them in the accordion.
 */
RowLayout {
    id: root
    spacing: 6
    property bool compact: false // dots only (the side-edge capsule)

    readonly property var uses: Privacy.uses.filter(u => u.kind === "camera" || u.kind === "microphone")
    readonly property bool active: uses.length > 0
    readonly property string apps: [...new Set(root.uses.map(u => u.app).filter(a => a))].join(", ")

    // The dots: the accordion's collapsed part (its first child).
    Row {
        spacing: 3
        Layout.alignment: Qt.AlignVCenter
        Repeater {
            model: [
                { kind: "camera", color: Appearance.colors.colSuccess },
                { kind: "microphone", color: Appearance.colors.colWarning }
            ].filter(k => root.uses.some(u => u.kind === k.kind))
            Rectangle {
                required property var modelData
                width: 8; height: 8; radius: 4
                color: modelData.color
            }
        }
    }
    StyledText {
        visible: !root.compact
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: root.apps || (Privacy.cameraActive ? "Camera in use" : "Microphone in use")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colOnLayer0
    }
}
