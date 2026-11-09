import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Live thumbnails of a set of windows in a grid that wraps at maxWidth; a
 * click focuses the window (the compositor switches to its workspace).
 * Holds a window lease and captures only while `active`. Used by the pill's
 * workspace chip and the bar's workspace buttons, inside a BarModulePopout.
 *
 *   WindowStrip { active: popout.shown; windows: CompositorService.windows.filter(…) }
 */
Item {
    id: root

    property bool active: false
    property var windows: []
    // Label each tile with its workspace (when listing several workspaces).
    property bool showWorkspace: false
    property int thumbW: 180
    property int thumbH: 110
    property real maxWidth: 800
    // false: a click only emits activated (a picker choosing a window).
    property bool focusOnTap: true
    // A middle click closes the window (the dock's previews).
    property bool closeOnMiddleClick: false
    signal activated(var win)

    readonly property int _gap: 8
    readonly property int _tileH: thumbH + 18
    readonly property int columns: Math.max(1, Math.min(windows.length, Math.floor((maxWidth + _gap) / (thumbW + _gap))))
    readonly property int rows: Math.ceil(windows.length / columns)
    implicitWidth: windows.length ? columns * (thumbW + _gap) - _gap : empty.implicitWidth
    implicitHeight: windows.length ? rows * (_tileH + _gap) - _gap : empty.implicitHeight

    // The backend tracks windows only while someone holds a lease.
    property bool _leased: false
    onActiveChanged: _lease()
    Component.onCompleted: _lease()
    Component.onDestruction: if (_leased) CompositorService.releaseWindows("windowStrip")
    function _lease() {
        if (root.active === root._leased) return
        root._leased = root.active
        if (root.active) CompositorService.acquireWindows("windowStrip"); else CompositorService.releaseWindows("windowStrip")
    }

    StyledText {
        id: empty
        visible: root.windows.length === 0
        text: "No windows"
        font.pixelSize: Appearance.font.pixelSize.smaller
        opacity: 0.55
    }

    Grid {
        columns: root.columns
        spacing: root._gap
        Repeater {
            model: root.windows
            delegate: Item {
                id: tile
                required property var modelData
                width: root.thumbW
                height: root._tileH

                Rectangle {
                    width: parent.width; height: root.thumbH
                    radius: 10
                    color: Appearance.colors.colLayer1
                    border.width: tileHover.hovered ? 2 : 1
                    border.color: tileHover.hovered ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    Behavior on border.color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }

                    Loader {
                        anchors.fill: parent
                        anchors.margins: 2
                        active: root.active && !!tile.modelData.toplevel
                        sourceComponent: ScreencopyView {
                            id: thumbView
                            captureSource: tile.modelData.toplevel ?? null
                            live: true
                            paintCursor: false
                            layer.enabled: true
                            // Sized by id: the mask Rectangle has no parent.
                            layer.effect: OpacityMask {
                                maskSource: Rectangle { width: thumbView.width; height: thumbView.height; radius: 8 }
                            }
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: !tile.modelData.toplevel
                        text: "preview_off"; iconSize: 24; opacity: 0.4
                    }
                }
                StyledText {
                    y: root.thumbH + 2
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    text: {
                        const t = tile.modelData.title || tile.modelData.appId || "(window)"
                        return root.showWorkspace ? `${tile.modelData.workspace} · ${t}` : t
                    }
                }
                HoverHandler { id: tileHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (root.focusOnTap) CompositorService.focusWindow(tile.modelData)
                        root.activated(tile.modelData)
                    }
                }
                TapHandler {
                    enabled: root.closeOnMiddleClick
                    acceptedButtons: Qt.MiddleButton
                    onTapped: CompositorService.closeWindow(tile.modelData)
                }
            }
        }
    }
}
