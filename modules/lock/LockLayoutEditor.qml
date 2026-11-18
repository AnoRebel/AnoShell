import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "lockLayout.js" as LockLayout

/**
 * The lock layout editor (IPC `lock editLayout [id]`, Settings → General → Lock screen → Edit layout): the
 * lock screen's elements full screen on the focused screen, over its wallpaper. Drag to move (snapping to
 * centre lines, other elements and the optional grid), the round handle to resize; the bar turns the
 * selected one by 90°, sets its opacity or removes it (not the password field), adds elements and desktop
 * pieces, undoes and redoes (Ctrl+Z, Ctrl+Shift+Z), resets to the lock screen's own arrangement. Done saves
 * lock.layouts.<id>; Escape or Cancel leaves it as it was. Nothing typed is checked.
 */
Scope {
    id: root
    readonly property string lockId: LockScreens.editingId

    PanelWindow {
        id: win
        visible: root.lockId !== ""
        screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.namespace: "quickshell:lockEditor"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Loader {
            anchors.fill: parent
            active: win.visible
            focus: true
            sourceComponent: editorC
        }
    }

    Component {
        id: editorC
        FocusScope {
            id: ed
            focus: true
            property var working: LockScreens.layoutOf(root.lockId)
            property var hist: ({ past: [], future: [] })
            property bool grid: false
            readonly property var sel: ed.working.find(e => e.uid === stage.selected) ?? null
            readonly property string name: root.lockId === "default" ? "AnoShell" : (LockScreens.registry.entries[root.lockId]?.name ?? root.lockId)

            function change(list) {
                ed.hist = LockLayout.record(ed.hist, ed.working, 50)
                ed.working = list
            }
            function patchSel(fields) {
                if (!ed.sel) return
                ed.change(ed.working.map(e => e.uid === ed.sel.uid ? Object.assign({}, e, fields) : e))
            }
            function undo() { const u = LockLayout.undo(ed.hist, ed.working); if (u) { ed.working = u.layout; ed.hist = u.h } }
            function redo() { const u = LockLayout.redo(ed.hist, ed.working); if (u) { ed.working = u.layout; ed.hist = u.h } }
            function remove() { if (ed.sel && ed.sel.type !== "field") { ed.change(ed.working.filter(e => e.uid !== ed.sel.uid)); stage.selected = "" } }
            function rotate() { if (ed.sel) ed.patchSel({ rot: (ed.sel.rot + 90) % 360 }) }
            function add(type, settings) {
                let uid = type === "piece" ? `piece-${settings.id}` : type, n = 2
                while (ed.working.some(e => e.uid === uid)) uid = `${type === "piece" ? `piece-${settings.id}` : type}-${n++}`
                ed.change(ed.working.concat([{ uid, type, x: 0.5, y: 0.5, scale: 1, rot: 0, opacity: 1, settings: settings ?? {} }]))
                stage.selected = uid
                addMenu.visible = false
            }
            function nudge(dx, dy) {
                if (!ed.sel) return
                ed.patchSel({ x: Math.max(0, Math.min(1, ed.sel.x + dx / stage.width)), y: Math.max(0, Math.min(1, ed.sel.y + dy / stage.height)) })
            }
            function done() { LockScreens.saveLayout(root.lockId, ed.working); LockScreens.endEdit() }

            Keys.onPressed: event => {
                const ctrl = event.modifiers & Qt.ControlModifier, shift = event.modifiers & Qt.ShiftModifier
                const step = shift ? 10 : 1
                if (ctrl && event.key === Qt.Key_Z) shift ? ed.redo() : ed.undo()
                else if (ctrl && event.key === Qt.Key_Y) ed.redo()
                else if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) ed.remove()
                else if (event.key === Qt.Key_R) ed.rotate()
                else if (event.key === Qt.Key_G) ed.grid = !ed.grid
                else if (event.key === Qt.Key_Escape) { if (addMenu.visible) addMenu.visible = false; else LockScreens.endEdit() }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) ed.done()
                else if (event.key === Qt.Key_Left) ed.nudge(-step, 0)
                else if (event.key === Qt.Key_Right) ed.nudge(step, 0)
                else if (event.key === Qt.Key_Up) ed.nudge(0, -step)
                else if (event.key === Qt.Key_Down) ed.nudge(0, step)
                else return
                event.accepted = true
            }

            // Under the stage: the built-in lock's backdrop (the stage draws its elements), or the package
            // itself drawing the arrangement being edited.
            Image {
                anchors.fill: parent
                visible: root.lockId === "default"
                source: root.lockId === "default" ? previewCtx.wallpaper : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
            }
            Repeater {
                model: root.lockId !== "default" ? [root.lockId] : []
                LockSurfaceHost {
                    required property string modelData
                    width: ed.width; height: ed.height
                    packageId: modelData; ctx: previewCtx; focus: false
                }
            }

            LockContext { id: previewCtx; preview: true; screen: win.screen; layoutOverride: stage.shown }
            LockLayoutStage {
                id: stage
                anchors.fill: parent
                ctx: previewCtx
                elements: ed.working
                grid: ed.grid
                drawElements: root.lockId === "default"
                onEdited: list => ed.change(list)
            }

            component ToolButton: Rectangle {
                id: tb
                property string icon
                property string tip
                property bool active: false
                signal clicked()
                implicitWidth: 40; implicitHeight: 40; radius: 20
                opacity: enabled ? 1 : 0.4
                color: tb.active ? Appearance.colors.colPrimary : (tbArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent")
                MaterialSymbol {
                    anchors.centerIn: parent; text: tb.icon; iconSize: 22
                    color: tb.active ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }
                MouseArea { id: tbArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tb.clicked() }
                StyledToolTip { text: tb.tip; extraVisibleCondition: tbArea.containsMouse }
            }

            // The bar.
            Rectangle {
                id: bar
                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 20 }
                width: barRow.implicitWidth + 20; height: 56
                radius: 28
                color: Appearance.colors.colLayer2
                border.width: 1; border.color: Appearance.colors.colOutlineVariant
                RowLayout {
                    id: barRow
                    anchors.centerIn: parent
                    spacing: 4
                    StyledText {
                        Layout.leftMargin: 8; Layout.rightMargin: 4
                        text: `Arranging ${ed.name}`
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }
                    ToolButton { icon: "add"; tip: "Add an element or a piece"; active: addMenu.visible; onClicked: addMenu.visible = !addMenu.visible }
                    ToolButton { icon: "rotate_90_degrees_cw"; tip: "Turn by 90° (R)"; enabled: !!ed.sel; onClicked: ed.rotate() }
                    StyledSlider {
                        Layout.preferredWidth: 120
                        enabled: !!ed.sel
                        from: 0.2; to: 1
                        value: ed.sel?.opacity ?? 1
                        onPressedChanged: if (!pressed && ed.sel && Math.abs(value - ed.sel.opacity) > 0.005) ed.patchSel({ opacity: Math.round(value * 100) / 100 })
                        StyledToolTip { text: "Opacity"; extraVisibleCondition: parent.hovered }
                    }
                    ToolButton {
                        icon: "delete"; tip: ed.sel?.type === "field" ? "The password field can't be removed" : "Remove (Delete)"
                        enabled: !!ed.sel && ed.sel.type !== "field"
                        visible: ed.sel?.type !== "field"
                        onClicked: ed.remove()
                    }
                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 28; color: Appearance.colors.colOutlineVariant }
                    ToolButton { icon: "grid_4x4"; tip: "Grid (G)"; active: ed.grid; onClicked: ed.grid = !ed.grid }
                    ToolButton { icon: "undo"; tip: "Undo (Ctrl+Z)"; enabled: ed.hist.past.length > 0; onClicked: ed.undo() }
                    ToolButton { icon: "redo"; tip: "Redo (Ctrl+Shift+Z)"; enabled: ed.hist.future.length > 0; onClicked: ed.redo() }
                    ToolButton { icon: "restart_alt"; tip: "Back to the lock screen's own arrangement"; onClicked: { ed.change(LockScreens.defaultLayoutOf(root.lockId)); stage.selected = "" } }
                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 28; color: Appearance.colors.colOutlineVariant }
                    RippleButton { buttonText: "Cancel"; onClicked: LockScreens.endEdit() }
                    RippleButton { buttonText: "Done"; toggled: true; onClicked: ed.done() }
                }
            }

            // Add: the elements not on the screen yet, then the installed pieces.
            Rectangle {
                id: addMenu
                visible: false
                anchors { top: bar.bottom; topMargin: 8; horizontalCenter: bar.horizontalCenter }
                width: 300; height: Math.min(addCol.implicitHeight + 16, parent.height * 0.6)
                radius: 18
                color: Appearance.colors.colLayer2
                border.width: 1; border.color: Appearance.colors.colOutlineVariant
                Flickable {
                    anchors.fill: parent; anchors.margins: 8
                    contentHeight: addCol.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: addCol
                        width: parent.width
                        spacing: 2
                        Repeater {
                            model: ["clock", "avatar", "name", "keyboard", "battery", "notifications"].filter(t => !ed.working.some(e => e.type === t))
                            delegate: menuItem
                        }
                        StyledText {
                            visible: Pieces.list.length > 0
                            Layout.topMargin: 6; Layout.leftMargin: 8
                            text: "Desktop pieces"; color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                        Repeater {
                            model: Pieces.list.filter(p => Pieces.usable(p.id)).map(p => ({ piece: p.id, label: p.name }))
                            delegate: menuItem
                        }
                    }
                }
            }
            Component {
                id: menuItem
                Rectangle {
                    required property var modelData
                    readonly property bool isPiece: typeof modelData === "object"
                    Layout.fillWidth: true
                    implicitHeight: 38; radius: 12
                    color: miArea.containsMouse ? Appearance.colors.colLayer2Hover : "transparent"
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 10
                        spacing: 10
                        MaterialSymbol { text: parent.parent.isPiece ? LockLayout.ICONS.piece : LockLayout.ICONS[parent.parent.modelData]; iconSize: 20; color: Appearance.colors.colOnLayer2 }
                        StyledText { Layout.fillWidth: true; text: parent.parent.isPiece ? parent.parent.modelData.label : LockLayout.LABELS[parent.parent.modelData]; color: Appearance.colors.colOnLayer2 }
                    }
                    MouseArea {
                        id: miArea
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: parent.isPiece ? ed.add("piece", { id: parent.modelData.piece }) : ed.add(parent.modelData)
                    }
                }
            }

            StyledText {
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 18 }
                text: "Drag to move · round handle to resize · arrows nudge (Shift: 10 px) · Enter: done · Escape: cancel"
                color: "white"; opacity: 0.7
            }
        }
    }

}
