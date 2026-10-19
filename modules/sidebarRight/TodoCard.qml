import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// To-do (todo.enable), synced both ways with todo.txt.
Rectangle {
    id: root
    implicitHeight: col.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 6
        RowLayout {
            Layout.fillWidth: true
            MaterialSymbol { text: "checklist"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
            StyledText { Layout.fillWidth: true; text: "To-do"; font.weight: Font.DemiBold }
            StyledText {
                text: `${Todo.items.filter(i => !i.done).length} left`
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
            ToolbarButton {
                visible: Todo.items.some(i => i.done)
                iconName: "cleaning_services"; iconSize: 18; toolTipText: "Remove done"
                onClicked: Todo.clearDone()
            }
        }
        Repeater {
            model: Todo.items
            delegate: RowLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 6
                MaterialSymbol {
                    text: modelData.done ? "check_box" : "check_box_outline_blank"
                    iconSize: 20
                    color: modelData.done ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    MouseArea { anchors.fill: parent; onClicked: Todo.toggle(index) }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: modelData.text
                    wrapMode: Text.Wrap
                    font.strikeout: modelData.done
                    opacity: modelData.done ? 0.5 : 1
                }
                ToolbarButton { iconName: "close"; iconSize: 16; onClicked: Todo.remove(index) }
            }
        }
        StyledTextInput {
            id: input
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            verticalAlignment: TextInput.AlignVCenter
            onAccepted: { Todo.add(text); text = "" }
            StyledText {
                anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                visible: input.text === ""
                text: "Add a task and press Enter"
                color: Appearance.colors.colSubtext
            }
        }
    }
}
