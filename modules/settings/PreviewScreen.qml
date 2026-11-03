import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services

/**
 * A miniature of the focused screen for Settings' previews (settings-wiring
 * "Interactive previews in Settings"): the current wallpaper at the screen's
 * logical size, scaled to this item's width. Children go into `world`, in the
 * screen's own coordinates, so shell components can be placed there as they
 * are on the real screen.
 *
 *   PreviewScreen { Layout.fillWidth: true
 *       Rectangle { x: 20; y: 20; width: 300; height: 40 } }   // screen px
 */
Item {
    id: root
    readonly property var targetScreen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0] ?? null
    readonly property real worldW: Math.max(320, targetScreen?.width ?? 1280)
    readonly property real worldH: Math.max(200, targetScreen?.height ?? 800)
    readonly property real s: width / worldW
    // At most this tall on the page; wider pages get a centred miniature.
    property real maxHeight: 360
    implicitHeight: Math.min(maxHeight, width * worldH / worldW)
    default property alias content: world.data
    property alias worldItem: world

    // Screen coordinates of a point in this item, and back.
    function toWorld(px, py) { return Qt.point((px - frame.x) / frame.scaleF, (py - frame.y) / frame.scaleF) }
    function fromWorld(wx, wy) { return Qt.point(frame.x + wx * frame.scaleF, frame.y + wy * frame.scaleF) }

    Rectangle {
        id: frame
        readonly property real scaleF: Math.min(root.width / root.worldW, root.height / root.worldH)
        width: root.worldW * scaleF
        height: root.worldH * scaleF
        anchors.centerIn: parent
        radius: Appearance?.rounding.normal ?? 12
        color: Appearance?.m3colors.m3background ?? "#141218"
        clip: true

        Item {
            id: world
            width: root.worldW
            height: root.worldH
            scale: frame.scaleF
            transformOrigin: Item.TopLeft

            Image {
                anchors.fill: parent
                z: -100
                source: {
                    const p = Config.options?.background?.wallpaperPath ?? ""
                    return p ? Wallpapers.fileUrl(p) : ""
                }
                sourceSize.width: 960 // a thumbnail is plenty at this scale
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
            }
        }
    }
    // The miniature's outline, over its contents.
    Rectangle {
        anchors.fill: frame
        radius: frame.radius
        color: "transparent"
        border.width: 1
        border.color: Appearance?.colors.colOutlineVariant ?? "#49454F"
    }
}
