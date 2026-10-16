import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// A round icon button in the deck's try-on colours; `checked` fills it with
// the accent (a toggle that's on).
Rectangle {
    id: rb
    required property Item deck
    property string icon
    property bool checked: false
    property string toolTip: ""
    readonly property alias hovered: ma.containsMouse
    signal clicked

    width: 40 * deck.u
    height: 40 * deck.u
    radius: height / 2
    color: rb.checked ? (rb.hovered ? Qt.lighter(deck.tint.accent, 1.08) : deck.tint.accent)
        : Qt.rgba(deck.tint.surface.r, deck.tint.surface.g, deck.tint.surface.b, rb.hovered ? 0.95 : 0.8)
    border.width: rb.checked ? 0 : 1
    border.color: Qt.rgba(deck.tint.ink.r, deck.tint.ink.g, deck.tint.ink.b, 0.12)

    MaterialSymbol {
        anchors.centerIn: parent
        text: rb.icon
        iconSize: 19 * rb.deck.u
        color: rb.checked ? rb.deck.tint.accentInk : rb.deck.tint.ink
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: rb.clicked()
    }
    StyledToolTip { text: rb.toolTip; extraVisibleCondition: rb.toolTip !== "" }
}
