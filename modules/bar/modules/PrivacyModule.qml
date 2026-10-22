import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Privacy indicator (bar module "privacy"): visible while the microphone, a
 * camera or the screen is being captured (services/Privacy.qml), one icon per
 * kind, and who is capturing in the tooltip.
 */
Item {
    id: root

    property bool vertical: false
    readonly property var kinds: [
        { kind: "screen", icon: "screen_share", label: "Screen" },
        { kind: "camera", icon: "videocam", label: "Camera" },
        { kind: "microphone", icon: "mic", label: "Microphone" },
    ].filter(k => Privacy.uses.some(u => u.kind === k.kind))
    visible: kinds.length > 0
    implicitWidth: visible ? (root.vertical ? Appearance.sizes.verticalBarWidth : grid.implicitWidth + 12) : 0
    implicitHeight: visible ? (root.vertical ? grid.implicitHeight + 12 : Appearance.sizes.barHeight) : 0

    GridLayout {
        id: grid
        anchors.centerIn: parent
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rowSpacing: 4; columnSpacing: 4
        Repeater {
            model: root.kinds
            MaterialSymbol {
                required property var modelData
                text: modelData.icon
                iconSize: 16
                // Error accent: it reads as a privacy alert, not another widget.
                color: Appearance?.colors.colError ?? "#f38ba8"
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        StyledToolTip {
            text: Privacy.uses.map(u => {
                const k = root.kinds.find(x => x.kind === u.kind)?.label ?? u.kind
                const who = [u.app, u.detail].filter(x => x).join(" · ")
                return who ? `${k}: ${who}` : `${k} in use`
            }).join("\n")
        }
    }
}
