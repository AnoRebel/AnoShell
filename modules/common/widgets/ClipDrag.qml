import QtQuick
import qs.services

// Drags a clipboard entry or pin (Cliphist) out of the shell, onto any window
// that takes drops. Fill a row with it: the drag starts once the pointer has
// moved 8 px with the button down and the entry's content is ready (decoded
// on demand); a click without moving stays with the row.
Item {
    id: root
    property var entry
    anchors.fill: parent

    property var _mime: ({})
    property bool _ready: false
    function _reset() { root._ready = false; root._mime = ({}) }

    DragHandler {
        id: dh
        target: null
        dragThreshold: 8
        acceptedButtons: Qt.LeftButton
        onActiveChanged: {
            if (dh.active) Cliphist.dragPayload(root.entry, m => { if (dh.active && m) { root._mime = m; root._ready = true } })
            else if (!root.Drag.active) root._reset()
        }
    }
    Drag.dragType: Drag.Automatic
    Drag.supportedActions: Qt.CopyAction
    Drag.mimeData: root._mime
    Drag.active: root._ready && dh.active
    Drag.onDragStarted: Cliphist.dragging = true
    Drag.onDragFinished: { Cliphist.dragging = false; root._reset() }
}
