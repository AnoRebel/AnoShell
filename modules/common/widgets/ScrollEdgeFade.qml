import QtQuick
import qs.modules.common

/**
 * Fades the top/bottom edge of a Flickable/ListView where content is cut off.
 * Two gradient Rectangles over the view (no mask, no shader); each shows only
 * while there is content beyond its edge and is not drawn otherwise.
 *
 * It reparents itself onto the view (not its contentItem), so it can be
 * declared anywhere: `ScrollEdgeFade { target: myList }`. StyledFlickable has
 * one built in (`edgeFade`).
 */
Item {
    id: root
    property Flickable target
    property real fadeHeight: 24
    // The colour the fade blends into: by default the nearest painted
    // Rectangle behind the view (re-read when that colour changes).
    property color fadeColor: {
        for (let p = target?.parent; p; p = p.parent) {
            const c = p.color
            if (c !== undefined && c.a !== undefined && c.a > 0.05) return c
        }
        return Appearance?.colors.colLayer0 ?? "#1C1B1F"
    }

    parent: target
    anchors.fill: parent
    z: 1 // above the view's contentItem
    enabled: false // never takes input

    Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Math.min(root.fadeHeight, root.height / 4)
        opacity: root.target && !root.target.atYBeginning ? 1 : 0
        visible: opacity > 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.fadeColor }
            GradientStop { position: 1.0; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
        }
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(150) } }
    }

    Rectangle {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
        height: Math.min(root.fadeHeight, root.height / 4)
        opacity: root.target && !root.target.atYEnd ? 1 : 0
        visible: opacity > 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(root.fadeColor.r, root.fadeColor.g, root.fadeColor.b, 0) }
            GradientStop { position: 1.0; color: root.fadeColor }
        }
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(150) } }
    }
}
