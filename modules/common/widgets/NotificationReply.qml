import qs.modules.common
import QtQuick
import QtQuick.Layouts

/**
 * Inline reply field for a notification that offers one (chat apps):
 * Enter or the send button replies, Esc cancels.
 */
Rectangle {
    id: root
    property string placeholder: ""
    signal sent(string text)
    signal cancelled()

    function focusField() { field.forceActiveFocus() }

    Layout.fillWidth: true
    implicitHeight: 32
    radius: Appearance?.rounding.small ?? 8
    color: Appearance?.colors.colLayer2 ?? "#2b2b2b"
    border.width: field.activeFocus ? 1 : 0
    border.color: Appearance?.colors.colPrimary ?? "#65558F"

    RowLayout {
        anchors { fill: parent; leftMargin: 10; rightMargin: 4 }
        spacing: 4
        StyledTextInput {
            id: field
            Layout.fillWidth: true
            clip: true
            verticalAlignment: TextInput.AlignVCenter
            Keys.onReturnPressed: send()
            Keys.onEnterPressed: send()
            Keys.onEscapePressed: root.cancelled()
            function send() { if (text.trim().length > 0) { root.sent(text); text = "" } }
            StyledText {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                text: root.placeholder || "Reply"
                opacity: 0.45
                visible: field.text.length === 0
                font.pixelSize: field.font.pixelSize
                elide: Text.ElideRight
            }
        }
        ToolbarButton {
            iconName: "send"; iconSize: 16
            implicitWidth: 26; implicitHeight: 26
            enabled: field.text.trim().length > 0
            toolTipText: "Send"
            onClicked: field.send()
        }
    }
}
