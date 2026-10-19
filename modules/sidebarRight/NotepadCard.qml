import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Notepad (notepad.enable): tabs of plain text, saved as you type.
Rectangle {
    id: root
    implicitHeight: col.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            MaterialSymbol { text: "edit_note"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
            Flickable {
                Layout.fillWidth: true
                implicitHeight: 28
                contentWidth: tabRow.width
                clip: true
                Row {
                    id: tabRow
                    spacing: 4
                    Repeater {
                        model: Notepad.tabs
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool active: Notepad.current === index
                            width: tabText.implicitWidth + (active && Notepad.tabs.length > 1 ? 34 : 18)
                            height: 28
                            radius: 14
                            color: active ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                            StyledText {
                                id: tabText
                                anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                                text: modelData.title || "Note"
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                            }
                            MouseArea { anchors.fill: parent; onClicked: Notepad.current = index }
                            MaterialSymbol {
                                visible: active && Notepad.tabs.length > 1
                                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                text: "close"; iconSize: 14
                                MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: Notepad.closeTab(index) }
                            }
                        }
                    }
                }
            }
            ToolbarButton { iconName: "add"; iconSize: 18; toolTipText: "New tab"; onClicked: Notepad.addTab() }
        }
        StyledTextArea {
            Layout.fillWidth: true
            Layout.preferredHeight: 160
            placeholderText: "Write something…"
            text: Notepad.tabs[Notepad.current]?.text ?? ""
            readOnly: !Notepad.loaded // nothing typed before the file loads gets replaced
            onTextChanged: if (activeFocus) Notepad.setText(Notepad.current, text)
        }
    }
}
