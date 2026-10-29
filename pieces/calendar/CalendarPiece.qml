import QtQuick
import qs.modules.calendar

// Bundled piece: the calendar panel's month grid and events (CalendarEvents).
Item {
    property var ctx
    Flickable {
        anchors.fill: parent
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        CalendarContent { id: content; width: parent.width }
    }
}
