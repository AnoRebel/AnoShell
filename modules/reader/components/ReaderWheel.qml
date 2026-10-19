import QtQuick
import qs.modules.common

// Mouse-wheel scrolling for the reader's lists and grids. ano sets
// QT_QUICK_FLICKABLE_WHEEL_DECELERATION very high (shell.qml), which leaves a
// plain Flickable barely moving per notch; this scrolls the enclosing
// Flickable the way StyledFlickable does (interactions.scrolling.*).
// Declare it as a child of the ListView/GridView/Flickable.
MouseArea {
    id: root
    // The nearest Flickable up the tree (a child of one sits in its contentItem).
    readonly property Item flick: {
        let p = root.parent
        while (p && (p.contentY === undefined || p.flickableDirection === undefined)) p = p.parent
        return p
    }
    readonly property real mouseFactor: Config.options.interactions.scrolling.mouseScrollFactor ?? 50
    readonly property real touchpadFactor: Config.options.interactions.scrolling.touchpadScrollFactor ?? 100
    readonly property real threshold: Config.options.interactions.scrolling.mouseScrollDeltaThreshold ?? 120

    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    onWheel: ev => {
        const f = root.flick
        if (!f) { ev.accepted = false; return }
        const raw = ev.angleDelta.y !== 0 ? ev.angleDelta.y : ev.angleDelta.x
        const step = (raw / root.threshold) * (Math.abs(raw) >= root.threshold ? root.mouseFactor : root.touchpadFactor)
        if (f.contentHeight > f.height + 1) {
            const top = f.originY - f.topMargin
            f.contentY = Math.max(top, Math.min(f.contentY - step, f.originY + f.contentHeight + f.bottomMargin - f.height))
        } else if (f.contentWidth > f.width + 1) {
            const left = f.originX - f.leftMargin
            f.contentX = Math.max(left, Math.min(f.contentX - step, f.originX + f.contentWidth + f.rightMargin - f.width))
        } else {
            ev.accepted = false
        }
    }
}
