pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Desktop widget layer (spec desktop-widgets): per screen, a Bottom-layer
 * surface over the wallpaper and under every window, sized by the compositor
 * to the area the bars leave free. Widgets sit on a snapping grid
 * (widgets.cell + widgets.gap) on pages; only the shown page is instantiated
 * (the one leaving stays for its slide, then goes).
 *
 * Input: only the widgets and the page controls take it (the mask); a click
 * anywhere else reaches the desktop, and a window over the layer gets its
 * own clicks. Pages: the arrows and dots (with more than one page), a
 * horizontal drag or touchpad swipe over a widget, and `qs ipc call widgets
 * next|prev|page N` for keys.
 *
 * ctx.live is false while the screen is locked or a maximised/fullscreen
 * window covers it: widgets run their timers and animations only while it's
 * true. (A tiled window covering the desktop isn't detected; niri doesn't
 * report where tiled windows are.)
 */
Scope {
    id: root

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            readonly property string screenName: modelData.name

            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "quickshell:widgets"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            readonly property bool live: !GlobalStates.screenLocked && !CompositorService.isCovered(win.screenName)
            readonly property var layout: Widgets.layoutOf(win.screenName)
            readonly property int pageCount: win.layout.pages.length

            // The grid: whole cells, centred in the free area.
            readonly property int cell: Math.max(32, Config.options?.widgets?.cell ?? 96)
            readonly property int gap: Math.max(0, Config.options?.widgets?.gap ?? 12)
            readonly property int margin: 24
            readonly property int cols: Math.max(1, Math.floor((win.width - 2 * win.margin + win.gap) / (win.cell + win.gap)))
            readonly property int rows: Math.max(1, Math.floor((win.height - 2 * win.margin - 28 + win.gap) / (win.cell + win.gap)))
            onColsChanged: Widgets.setGrid(win.screenName, win.cols, win.rows)
            onRowsChanged: Widgets.setGrid(win.screenName, win.cols, win.rows)
            readonly property real originX: Math.round((win.width - (win.cols * (win.cell + win.gap) - win.gap)) / 2)
            readonly property real originY: Math.round((win.height - 28 - (win.rows * (win.cell + win.gap) - win.gap)) / 2)

            Component.onCompleted: { Widgets.hold(true); Widgets.setGrid(win.screenName, win.cols, win.rows); slotA.page = win.configPage; win.shownPage = win.configPage }
            Component.onDestruction: Widgets.hold(false)

            // What widgets get: whether to run, and where they are.
            readonly property QtObject ctx: QtObject {
                readonly property bool live: win.live
                readonly property string screenName: win.screenName
                readonly property int cell: win.cell
            }

            // ── Pages: two slots, the shown one and the one sliding out ──
            property int shownPage: -1
            property bool aFront: true
            property int dir: 1
            function go(p) {
                p = Math.max(0, Math.min(win.pageCount - 1, p))
                if (p === win.shownPage) return
                win.dir = p > win.shownPage ? 1 : -1
                const incoming = win.aFront ? slotB : slotA
                incoming.page = p
                win.aFront = !win.aFront
                slide.restart()
                if (p !== win.layout.page) Widgets.setPage(win.screenName, p)
            }
            Connections {
                target: Widgets
                function onPageRequest(screenName, delta) { if (screenName === win.screenName) win.go(win.shownPage + delta) }
            }
            // The config's page (restart, IPC page N, another edit) drives it too.
            readonly property int configPage: win.layout.page
            onConfigPageChanged: if (win.shownPage >= 0) win.go(win.configPage)

            // Front slot at 0, the other off to the side it leaves by.
            property real progress: 1
            NumberAnimation on progress { id: slide; from: 0; to: 1; duration: Appearance.animation.elementMove.duration; easing.type: Easing.OutCubic; running: false
                onStarted: win.shownPage = (win.aFront ? slotA : slotB).page
                onFinished: (win.aFront ? slotB : slotA).page = -1 }

            Item {
                id: pages
                anchors.fill: parent

                // A horizontal drag over a widget, or a touchpad swipe, turns the page.
                DragHandler {
                    target: null
                    xAxis.enabled: true; yAxis.enabled: false
                    enabled: win.pageCount > 1
                    property real dx: 0
                    onTranslationChanged: if (active) dx = translation.x
                    onActiveChanged: if (!active) { if (Math.abs(dx) > 80) win.go(win.shownPage + (dx < 0 ? 1 : -1)); dx = 0 }
                }
                WheelHandler {
                    acceptedDevices: PointerDevice.TouchPad
                    orientation: Qt.Horizontal
                    enabled: win.pageCount > 1
                    property real acc: 0
                    onWheel: event => {
                        acc += event.angleDelta.x
                        if (Math.abs(acc) > 240) { win.go(win.shownPage + (acc < 0 ? 1 : -1)); acc = 0 }
                    }
                }

                PageSlot { id: slotA; front: win.aFront }
                PageSlot { id: slotB; front: !win.aFront }
            }

            component PageSlot: Item {
                id: slot
                property int page: -1
                property bool front: false
                width: pages.width; height: pages.height
                x: (slot.front ? (1 - win.progress) : -win.progress) * win.dir * pages.width
                opacity: slot.front ? win.progress : 1 - win.progress
                visible: slot.page >= 0
                readonly property var hosts: slot.page >= 0 ? hostRepeater.hosts : []
                Repeater {
                    id: hostRepeater
                    property var hosts: { hostRepeater.count; return Array.from({ length: hostRepeater.count }, (_, i) => hostRepeater.itemAt(i)).filter(h => !!h) }
                    model: slot.page >= 0 ? (win.layout.pages[slot.page] ?? []) : []
                    delegate: WidgetHost {
                        required property var modelData
                        placed: modelData
                        ctx: win.ctx
                        x: win.originX + modelData.x * (win.cell + win.gap)
                        y: win.originY + modelData.y * (win.cell + win.gap)
                        width: modelData.w * (win.cell + win.gap) - win.gap
                        height: modelData.h * (win.cell + win.gap) - win.gap
                    }
                }
            }

            // ── Page controls (more than one page) ──
            Row {
                id: dots
                visible: win.pageCount > 1
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                spacing: 8
                Repeater {
                    model: win.pageCount
                    Rectangle {
                        required property int index
                        width: index === win.shownPage ? 22 : 8; height: 8; radius: 4
                        color: index === win.shownPage ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                        opacity: index === win.shownPage ? 0.95 : 0.45
                        Behavior on width { animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
                        MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: win.go(parent.index) }
                    }
                }
            }
            PageArrow { id: leftArrow; anchors.left: parent.left; glyph: "chevron_left"; enabled: win.shownPage > 0; onClicked: win.go(win.shownPage - 1) }
            PageArrow { id: rightArrow; anchors.right: parent.right; glyph: "chevron_right"; enabled: win.shownPage < win.pageCount - 1; onClicked: win.go(win.shownPage + 1) }
            component PageArrow: RippleButton {
                property string glyph
                visible: win.pageCount > 1
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: 4
                implicitWidth: 32; implicitHeight: 56
                buttonRadius: 16
                opacity: enabled ? 0.7 : 0.25
                contentItem: MaterialSymbol { text: parent.glyph; iconSize: 24; horizontalAlignment: Text.AlignHCenter; color: Appearance.colors.colOnLayer1 }
            }

            // Input only where something is: the widgets of the shown page and the controls.
            mask: Region {
                regions: {
                    const items = slotA.hosts.concat(slotB.hosts)
                    if (win.pageCount > 1) items.push(dots, leftArrow, rightArrow)
                    return items.map(it => regionComp.createObject(this, { "item": it }))
                }
            }
            Component { id: regionComp; Region {} }
        }
    }
}
