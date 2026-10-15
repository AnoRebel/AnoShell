import QtQuick
import qs
import qs.modules.common

/**
 * A grip along the top edge of a standalone panel's card: drag it to move the
 * root.panelCard, double-click to centre it again. Place it as a sibling of the root.panelCard in
 * the panel's full-screen layer (whose input mask is the root.panelCard, so it moves
 * too). The position is kept for the session under `key`.
 */
Item {
    id: root

    required property Item panelCard
    property string key: ""

    x: root.panelCard.x; y: root.panelCard.y; width: root.panelCard.width; height: 20
    z: 1000
    visible: root.panelCard.visible && root.panelCard.opacity > 0.01
    opacity: root.panelCard.opacity

    function _detach() {
        const c = root.panelCard, x = c.x, y = c.y
        c.anchors.centerIn = undefined
        c.anchors.top = undefined; c.anchors.bottom = undefined
        c.anchors.left = undefined; c.anchors.right = undefined
        c.anchors.horizontalCenter = undefined; c.anchors.verticalCenter = undefined
        c.x = x; c.y = y
    }
    function _move(x, y) {
        const p = root.panelCard.parent
        root.panelCard.x = Math.max(0, Math.min(x, p.width - root.panelCard.width))
        root.panelCard.y = Math.max(0, Math.min(y, p.height - root.panelCard.height))
    }
    function _remember() {
        if (!root.key) return
        const m = Object.assign({}, GlobalStates.panelPositions)
        m[root.key] = { x: root.panelCard.x, y: root.panelCard.y }
        GlobalStates.panelPositions = m
    }

    Component.onCompleted: {
        const pos = root.key ? GlobalStates.panelPositions[root.key] : undefined
        if (pos) Qt.callLater(() => { root._detach(); root._move(pos.x, pos.y) })
    }

    Rectangle {
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 7 }
        width: area.pressed || area.containsMouse ? 48 : 36; height: 4; radius: 2
        color: Appearance.colors.colOutline
        opacity: area.pressed ? 0.9 : area.containsMouse ? 0.7 : 0.35
        Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point _press      // pointer, in the card's parent
        property point _start      // card position at press
        onPressed: mouse => {
            root._detach()
            _press = mapToItem(root.panelCard.parent, mouse.x, mouse.y)
            _start = Qt.point(root.panelCard.x, root.panelCard.y)
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            const p = mapToItem(root.panelCard.parent, mouse.x, mouse.y)
            root._move(_start.x + p.x - _press.x, _start.y + p.y - _press.y)
        }
        onReleased: root._remember()
        onDoubleClicked: {
            const p = root.panelCard.parent
            root._move((p.width - root.panelCard.width) / 2, (p.height - root.panelCard.height) / 2)
            root._remember()
        }
    }
}
