import QtQuick
import qs.modules.common
import qs.modules.common.functions

// Centred "nothing here yet" placeholder: large glyph, headline, hint line.
Column {
    id: root

    property string glyph: "⊡"
    property string title: ""
    property string subtitle: ""
    property string displayFont: ""
    property string bodyFont: ""

    anchors.centerIn: parent
    spacing: 14

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.glyph
        font.pixelSize: 44
        color: Appearance.m3colors.m3outline
        opacity: 0.3
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.title
        font.family: root.displayFont
        font.pixelSize: 15
        opacity: 0.45
    }

    StyledText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.subtitle
        font.family: root.bodyFont
        font.pixelSize: 11
        font.letterSpacing: 0.2
        color: Appearance.m3colors.m3onSurfaceVariant
        opacity: 0.4
    }
}
