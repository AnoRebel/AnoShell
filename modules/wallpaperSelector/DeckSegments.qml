pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// A row of choices in a glass pill: options [{ key, label, icon, badge? }].
DeckGlass {
    id: segs
    property var options: []
    property string value
    signal picked(string key)

    width: segRow.implicitWidth + 8 * deck.u
    height: 40 * deck.u

    Row {
        id: segRow
        anchors.centerIn: parent
        spacing: 2 * segs.deck.u

        Repeater {
            model: segs.options
            Rectangle {
                id: seg
                required property var modelData
                readonly property bool current: segs.value === modelData.key
                width: segLabel.implicitWidth + 28 * segs.deck.u
                height: 32 * segs.deck.u
                radius: height / 2
                color: current ? segs.deck.tint.accent
                    : segMa.containsMouse ? Qt.rgba(segs.deck.tint.ink.r, segs.deck.tint.ink.g, segs.deck.tint.ink.b, 0.08) : "transparent"

                Row {
                    id: segLabel
                    anchors.centerIn: parent
                    spacing: 6 * segs.deck.u
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !!seg.modelData.icon
                        text: seg.modelData.icon ?? ""
                        fill: seg.current ? 1 : 0
                        iconSize: 17 * segs.deck.u
                        color: seg.current ? segs.deck.tint.accentInk : segs.deck.tint.muted
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: seg.modelData.label + (seg.modelData.badge !== undefined ? "  " + seg.modelData.badge : "")
                        font.pixelSize: (Appearance?.font.pixelSize.smallie ?? 13) * segs.deck.u
                        font.weight: Font.DemiBold
                        color: seg.current ? segs.deck.tint.accentInk : segs.deck.tint.ink
                    }
                }
                MouseArea {
                    id: segMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: segs.picked(seg.modelData.key)
                }
            }
        }
    }
}
