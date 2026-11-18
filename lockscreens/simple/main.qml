import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.lock

// Simple (docs/lockscreens.md): the clock, your picture and name and a password field that is always ready
// (Enter submits, Esc clears), arranged as lock.layouts.simple says, over the blurred wallpaper. The blur
// eases while you type; after the right password everything slides up and away while the wallpaper sharpens
// into the desktop's.
Item {
    id: root
    property var ctx
    readonly property bool typing: (root.ctx?.typedLength ?? 0) > 0
    readonly property bool leaving: root.ctx?.leaving ?? false

    Component.onCompleted: root.ctx?.wantOutro(450)

    Rectangle { anchors.fill: parent; color: Appearance.m3colors.m3background }
    Image {
        id: wall
        anchors.fill: parent
        source: root.ctx?.wallpaper ?? ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wall
        blurEnabled: true
        blurMax: 64
        blur: root.leaving ? 0 : root.typing ? 0.55 : 1
        brightness: root.leaving ? 0 : -0.18
        Behavior on blur { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        Behavior on brightness { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }

    LockElements {
        id: content
        width: parent.width; height: parent.height
        focus: true
        ctx: root.ctx
        elements: root.ctx?.layout ?? []
        y: root.leaving ? -parent.height * 0.6 : 0
        opacity: root.leaving ? 0 : 1
        Behavior on y { NumberAnimation { duration: 420; easing.type: Easing.InCubic } }
        Behavior on opacity { NumberAnimation { duration: 420; easing.type: Easing.InCubic } }
    }
}
