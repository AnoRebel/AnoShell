import QtQuick
import qs.modules.common
import qs.modules.sidebarRight
import qs.services

// Bundled piece: the sidebar's to-do card (services/Todo, todo.txt), so a
// task checked here is checked there and in the file. Holds the service on
// while placed, even with the sidebar's to-do turned off.
Item {
    property var ctx
    Component.onCompleted: Todo.hold(true)
    Component.onDestruction: Todo.hold(false)
    Flickable {
        anchors.fill: parent
        contentHeight: card.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        TodoCard { id: card; width: parent.width; color: "transparent" }
    }
}
