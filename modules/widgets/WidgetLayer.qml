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
 * (widgets.cell + widgets.gap) on pages; only the shown page is instantiated.
 * At rest each widget is a small Bottom-layer window of its own at its cell,
 * so a moving widget redraws only its card (a full-screen surface redrawn for
 * it cost about twice the CPU); a page turn fades the new page's windows in.
 * This full-screen surface draws only the page controls, and in edit mode
 * the cards themselves (above windows, sliding between pages).
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

            // Edit mode: above windows, with the keyboard (Escape leaves).
            readonly property bool editing: Widgets.editing
            WlrLayershell.layer: win.editing ? WlrLayer.Top : WlrLayer.Bottom
            WlrLayershell.namespace: "quickshell:widgets"
            WlrLayershell.keyboardFocus: win.editing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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
            readonly property var _size: Widgets.gridSize(win.width, win.height)
            readonly property int cols: win._size.cols
            readonly property int rows: win._size.rows
            onColsChanged: Widgets.setGrid(win.screenName, win.cols, win.rows)
            onRowsChanged: Widgets.setGrid(win.screenName, win.cols, win.rows)
            readonly property real originX: Math.round((win.width - (win.cols * (win.cell + win.gap) - win.gap)) / 2)
            readonly property real originY: Math.round((win.height - Widgets.pagerHeight - (win.rows * (win.cell + win.gap) - win.gap)) / 2)

            Component.onCompleted: { Widgets.hold(true); Widgets.setGrid(win.screenName, win.cols, win.rows); slotA.page = win.configPage; win.shownPage = win.configPage }
            Component.onDestruction: Widgets.hold(false)

            readonly property var grid: ({ originX: win.originX, originY: win.originY, step: win.cell + win.gap, gap: win.gap,
                                           cols: win.cols, rows: win.rows, screenName: win.screenName })

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
            NumberAnimation on progress { id: slide; from: 0; to: 1; duration: Appearance.animation.elementMove.duration; easing.type: Appearance.animation.elementMove.type; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve; running: false
                onStarted: win.shownPage = (win.aFront ? slotA : slotB).page
                onFinished: (win.aFront ? slotB : slotA).page = -1 }

            Item {
                id: pages
                anchors.fill: parent

                // A horizontal drag over a widget, or a touchpad swipe, turns the page.
                DragHandler {
                    target: null
                    xAxis.enabled: true; yAxis.enabled: false
                    enabled: win.pageCount > 1 && !win.editing
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

                // Edit mode: the cells.
                Loader {
                    anchors.fill: parent
                    active: win.editing
                    sourceComponent: Item {
                        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.25) }
                        Repeater {
                            model: win.cols * win.rows
                            Rectangle {
                                required property int index
                                x: win.originX + (index % win.cols) * win.grid.step
                                y: win.originY + Math.floor(index / win.cols) * win.grid.step
                                width: win.cell; height: win.cell
                                radius: Appearance.rounding.small
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.14)
                            }
                        }
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
                visible: slot.page >= 0 && win.editing
                // The page's widgets, kept in step with the Repeater (delegates
                // can be created after `count` changes). Only in edit mode: at
                // rest each widget has a window of its own (below).
                property var hosts: []
                readonly property var placedList: slot.page >= 0 && win.editing ? (win.layout.pages[slot.page] ?? []) : []
                Repeater {
                    id: hostRepeater
                    // Keyed by uid: a layout write (move, setting, page turn)
                    // updates the widgets in place instead of re-creating them.
                    model: ScriptModel { values: slot.placedList.map(o => o.uid) }
                    onItemAdded: (i, item) => slot.hosts = slot.hosts.concat([item])
                    onItemRemoved: (i, item) => slot.hosts = slot.hosts.filter(h => h !== item)
                    delegate: WidgetHost {
                        required property string modelData
                        placed: slot.placedList.find(o => o.uid === modelData) ?? ({ uid: modelData, id: "", x: 0, y: 0, w: 1, h: 1 })
                        ctx: win.ctx
                        grid: win.grid
                        editing: win.editing
                        onOpenSettings: h => settingsPanel.host = h
                    }
                }
            }

            // ── At rest: a window per widget ──
            // Each widget is its own small Bottom-layer surface at its cell, so
            // a moving one redraws only its card: redrawing the full-screen layer
            // for it cost about twice as much (measured).
            readonly property var shownList: win.layout.pages[win.shownPage] ?? []
            Instantiator {
                active: !win.editing && win.shownPage >= 0
                model: ScriptModel { values: win.shownList.map(o => o.uid) }
                delegate: PanelWindow {
                    id: card
                    required property string modelData
                    readonly property var placed: win.shownList.find(o => o.uid === card.modelData) ?? null
                    screen: win.modelData
                    visible: !!card.placed
                    WlrLayershell.layer: WlrLayer.Bottom
                    WlrLayershell.namespace: "quickshell:widget"
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    exclusionMode: ExclusionMode.Normal
                    exclusiveZone: 0
                    anchors { top: true; left: true }
                    margins {
                        left: win.originX + (card.placed?.x ?? 0) * win.grid.step
                        top: win.originY + (card.placed?.y ?? 0) * win.grid.step
                    }
                    implicitWidth: Math.max(1, (card.placed?.w ?? 1) * win.grid.step - win.gap)
                    implicitHeight: Math.max(1, (card.placed?.h ?? 1) * win.grid.step - win.gap)
                    color: "transparent"

                    WidgetHost {
                        id: cardHost
                        // its own window: placed at the window's origin
                        placed: card.placed ?? ({ uid: card.modelData, id: "", x: 0, y: 0, w: 1, h: 1 })
                        grid: Object.assign({}, win.grid, { originX: -(card.placed?.x ?? 0) * win.grid.step,
                                                            originY: -(card.placed?.y ?? 0) * win.grid.step })
                        ctx: win.ctx
                        editing: false
                        opacity: 0
                        Component.onCompleted: fadeIn.start()
                        NumberAnimation on opacity { id: fadeIn; to: 1; running: false
                            duration: Appearance.animation.elementMove.duration
                            easing.type: Appearance.animation.elementMove.type; easing.bezierCurve: Appearance.animation.elementMove.bezierCurve }
                    }
                    // A drag across it or a touchpad swipe turns the page.
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

            // ── Edit mode: toolbar, the widget list, a widget's settings ──
            onEditingChanged: if (!win.editing) { settingsPanel.host = null; addList.open = false }
            // Escape: the open panel first, then edit mode. A window-level
            // shortcut, so it works wherever focus is inside the layer.
            Shortcut {
                sequence: "Escape"
                enabled: win.editing
                context: Qt.WindowShortcut
                onActivated: {
                    if (settingsPanel.host) settingsPanel.host = null
                    else if (addList.open) addList.open = false
                    else Widgets.editing = false
                }
            }
            SurfaceMaterial {
                id: toolbar
                visible: win.editing
                surface: "widget"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 8
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1
                textColor: Appearance.colors.colOnLayer1
                width: tools.implicitWidth + 16; height: tools.implicitHeight + 12
                Row {
                    id: tools
                    anchors.centerIn: parent
                    spacing: 4
                    ToolButton { glyph: "add"; label: "Add widget"; onClicked: addList.open = !addList.open }
                    ToolButton { glyph: "note_add"; label: "Add page"; onClicked: Widgets.addPage(win.screenName) }
                    ToolButton { glyph: "delete"; label: "Remove page"; onClicked: Widgets.removePage(win.screenName, win.shownPage) }
                    ToolButton { glyph: "check"; label: "Done"; onClicked: Widgets.editing = false }
                }
            }
            component ToolButton: RippleButton {
                id: tbtn
                property string glyph
                property string label
                implicitHeight: 34
                implicitWidth: tb.implicitWidth + 24
                buttonRadius: 17
                contentItem: Item {
                    Row {
                        id: tb
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: tbtn.glyph; iconSize: 18; color: Appearance.colors.colOnLayer1 }
                        StyledText { anchors.verticalCenter: parent.verticalCenter; text: tbtn.label }
                    }
                }
            }
            SurfaceMaterial {
                id: addList
                property bool open: false
                property string message: ""
                visible: win.editing && open
                surface: "widget"
                anchors.top: toolbar.bottom
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                radius: Appearance.rounding.large
                color: Appearance.colors.colLayer1
                textColor: Appearance.colors.colOnLayer1
                width: 360
                height: Math.min(win.height - 140, addCol.implicitHeight + 16)
                Flickable {
                    anchors.fill: parent
                    anchors.margins: 8
                    contentHeight: addCol.implicitHeight
                    clip: true
                    Column {
                        id: addCol
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: Widgets.list
                            RippleButton {
                                id: pick
                                required property var modelData
                                readonly property var problems: Widgets.errorsOf(modelData.id)
                                width: addCol.width
                                implicitHeight: pickCol.implicitHeight + 12
                                enabled: pick.problems.length === 0
                                onClicked: {
                                    addList.message = Widgets.add(win.screenName, modelData.id, win.cols, win.rows) ? "" : `No room for ${modelData.name} on this page`
                                    if (!addList.message) addList.open = false
                                }
                                contentItem: Column {
                                    id: pickCol
                                    leftPadding: 8; rightPadding: 8
                                    StyledText { text: `${pick.modelData.name} · ${pick.modelData.size.w}×${pick.modelData.size.h}`; font.weight: Font.Medium }
                                    StyledText {
                                        width: addCol.width - 16; wrapMode: Text.Wrap
                                        text: pick.problems.length ? pick.problems.join("; ") : pick.modelData.description
                                        color: pick.problems.length ? Appearance.colors.colError : Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                            }
                        }
                        StyledText {
                            visible: addList.message.length > 0
                            text: addList.message; color: Appearance.colors.colError
                            leftPadding: 8; font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }
            WidgetSettings {
                id: settingsPanel
                host: null
                visible: win.editing && !!host
                // beside the widget, kept on screen
                x: !host ? 0 : Math.max(8, Math.min(win.width - width - 8, host.x + host.width + 12 > win.width - width ? host.x - width - 12 : host.x + host.width + 12))
                y: !host ? 0 : Math.max(8, Math.min(win.height - height - 8, host.y))
                onClosed: settingsPanel.host = null
            }

            // Input only where something is: the widgets of the shown page and
            // the controls; all of it while editing.
            mask: win.editing ? everything : someRegion
            Region { id: everything; item: pages }
            Region { id: dotsRegion; item: dots }
            Region { id: leftRegion; item: leftArrow }
            Region { id: rightRegion; item: rightArrow }
            Region {
                id: someRegion
                // each host owns its Region (made once, gone with the host)
                regions: slotA.hosts.concat(slotB.hosts).map(h => h.region)
                    .concat(win.pageCount > 1 ? [dotsRegion, leftRegion, rightRegion] : [])
            }
        }
    }
}
