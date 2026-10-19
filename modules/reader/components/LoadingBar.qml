import QtQuick
import qs.modules.common
import qs.modules.common.functions

// A thin indeterminate strip: a short bar sliding across a faint track. For
// "more is on its way" while content is already on screen (next page,
// refreshing a list). Fades in and out with `active`.
Item {
    id: root

    property bool active: false
    property color color: Appearance.m3colors.m3primary

    height: 2
    clip: true
    opacity: root.active ? 1 : 0
    visible: root.opacity > 0
    Behavior on opacity { NumberAnimation { duration: 220 } }

    Rectangle {
        anchors.fill: parent
        color: ColorUtils.transparentize(root.color, 0.14)
    }

    Rectangle {
        id: bar
        width: Math.max(40, root.width * 0.3)
        height: root.height
        radius: height / 2
        color: root.color

        XAnimator on x {
            from: -bar.width
            to: root.width
            duration: 1100
            loops: Animation.Infinite
            running: root.visible
            easing.type: Easing.InOutQuad
        }
    }
}
