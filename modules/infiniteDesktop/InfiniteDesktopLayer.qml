pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Infinite desktop input and map (services/InfiniteDesktop.qml), on the
 * focused screen while its workspace is an infinite desktop:
 *  - drag: a Background-layer surface over the wallpaper and under every
 *    window and piece; dragging the empty desktop pans the canvas;
 *  - pan keys: while they are held (or pan mode is on), an Overlay surface
 *    follows the pointer and pans with it; a click or Escape ends it;
 *  - map: while panning, a small view of the canvas and where the screen is
 *    on it (no input).
 */
Scope {
    id: root
    readonly property var screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? null
    readonly property bool on: InfiniteDesktop.active && !!root.screen && !GlobalStates.screenLocked

    PanelWindow {
        id: drag
        visible: root.on
        screen: root.screen
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "quickshell:infiniteDesktop"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        MouseArea {
            anchors.fill: parent
            property real lx: 0
            property real ly: 0
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: mouse => { lx = mouse.x; ly = mouse.y; InfiniteDesktop.beginPan() }
            onPositionChanged: mouse => {
                if (!pressed) return
                InfiniteDesktop.panBy(mouse.x - lx, mouse.y - ly)
                lx = mouse.x; ly = mouse.y
            }
            onReleased: InfiniteDesktop.endPan()
            onCanceled: InfiniteDesktop.endPan()
        }
    }

    PanelWindow {
        id: keys
        visible: root.on && InfiniteDesktop.panMode
        screen: root.screen
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:infiniteDesktopPan"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        onVisibleChanged: if (visible) { area.started = false; InfiniteDesktop.beginPan() } else InfiniteDesktop.endPan()
        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: InfiniteDesktop.panMode = false
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.SizeAllCursor
            property bool started: false
            property real lx: 0
            property real ly: 0
            onPositionChanged: mouse => {
                if (started) InfiniteDesktop.panBy(mouse.x - lx, mouse.y - ly)
                started = true; lx = mouse.x; ly = mouse.y
            }
            onClicked: InfiniteDesktop.panMode = false
        }
    }

    PanelWindow {
        id: mapWin
        readonly property var map: InfiniteDesktop.map
        visible: root.on && InfiniteDesktop.panning && !!map
        screen: root.screen
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:infiniteDesktopMap"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Normal
        anchors { bottom: true; right: true }
        margins { bottom: 16; right: 16 }
        implicitWidth: 220
        implicitHeight: 140
        color: "transparent"
        mask: Region {}
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.normal
            color: ColorUtils.transparentize(Appearance.colors.colLayer0Base ?? Appearance.colors.colLayer0, 0.88)
            border.width: 1
            border.color: Appearance.colors.colOutlineVariant
            Item {
                id: canvas
                anchors.fill: parent
                anchors.margins: 10
                readonly property var b: mapWin.map?.bounds ?? { x: 0, y: 0, width: 1, height: 1 }
                readonly property real k: Math.min(width / Math.max(1, b.width), height / Math.max(1, b.height))
                readonly property real ox: (width - b.width * k) / 2
                readonly property real oy: (height - b.height * k) / 2
                Repeater {
                    model: mapWin.map?.windows ?? []
                    Rectangle {
                        required property var modelData
                        x: canvas.ox + (modelData.x - canvas.b.x) * canvas.k
                        y: canvas.oy + (modelData.y - canvas.b.y) * canvas.k
                        width: Math.max(2, modelData.width * canvas.k)
                        height: Math.max(2, modelData.height * canvas.k)
                        radius: 2
                        color: modelData.focused ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    }
                }
                Rectangle {
                    readonly property var v: mapWin.map?.view ?? { x: 0, y: 0, width: 0, height: 0 }
                    x: canvas.ox + (v.x - canvas.b.x) * canvas.k
                    y: canvas.oy + (v.y - canvas.b.y) * canvas.k
                    width: v.width * canvas.k
                    height: v.height * canvas.k
                    color: "transparent"
                    border.width: 2
                    border.color: Appearance.colors.colOnLayer0
                    radius: 3
                }
            }
        }
    }
}
