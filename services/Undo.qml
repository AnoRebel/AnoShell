pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import "undoLogic.js" as UndoLogic

/**
 * Undo instead of confirm: a removal happens at once and a toast offers
 * Undo for a few seconds.
 *
 *   Undo.push({ label: "Removed “milk”", restore: () => …, commit: () => … })
 *
 * restore() puts the item back exactly and returns false when it can't
 * (something changed since); commit() (optional) runs when the entry goes
 * for good: a deferred delete that only happens then. The latest few are
 * kept, newest undone first. One toast on the focused screen; it never
 * takes the keyboard. IPC: qs -c ano ipc call undo last
 */
Singleton {
    id: root

    readonly property int ttl: 6000
    readonly property int keep: 3
    property var stack: []
    readonly property var current: stack.length ? stack[stack.length - 1] : null
    // A short note in place of the toast (undo failed, nothing to undo).
    property string note: ""

    function push(entry) {
        const r = UndoLogic.push(root.stack, entry, Date.now(), root.keep, root.ttl)
        root._settle(r)
        root.note = ""
    }
    // Undo the newest; false when there was nothing (or it couldn't be put back).
    function undoLast() {
        const r = UndoLogic.take(root.stack, Date.now(), root.ttl)
        root._settle(r)
        if (!r.entry) { root.say("Nothing to undo"); return false }
        let ok = false
        try { ok = r.entry.restore() !== false } catch (e) { console.warn(`[Undo] ${e}`) }
        if (!ok) root.say("Can't undo: it changed since")
        return ok
    }
    function _settle(r) {
        root.stack = r.stack
        for (const e of r.dropped) root._commit(e)
        if (root.stack.length) { tick.interval = Math.max(50, root.stack[0].at + root.ttl - Date.now()); tick.restart() }
        else tick.stop()
    }
    function _commit(e) { try { e.commit?.() } catch (err) { console.warn(`[Undo] ${err}`) } }
    // A note for a moment (an async restore that failed says why).
    function say(t) { root.note = t; noteTimer.restart() }

    Timer { id: tick; onTriggered: root._settle(UndoLogic.expire(root.stack, Date.now(), root.ttl)) }
    Timer { id: noteTimer; interval: 2500; onTriggered: root.note = "" }
    // Deferred deletes still pending when the shell goes (quit, reload) happen now.
    Component.onDestruction: { for (const e of root.stack) root._commit(e) }

    IpcHandler {
        target: "undo"
        function last(): string { return root.undoLast() ? "undone" : (root.note || "nothing to undo") }
        function list(): string { return JSON.stringify(root.stack.map(e => e.label)) }
    }

    LazyLoader {
        active: (root.current !== null || root.note !== "") && !GlobalStates.screenLocked
        PanelWindow {
            id: win
            screen: GlobalStates.focusedScreen
            anchors.bottom: true
            margins.bottom: 104 // above the OSD's spot
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:undo"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            color: "transparent"
            implicitWidth: body.width
            implicitHeight: body.height

            Rectangle {
                id: body
                width: Math.min(row.implicitWidth + 32, 520)
                height: 44
                radius: height / 2
                color: Appearance.colors.colLayer0
                border.width: Appearance.borders.width
                border.color: Appearance.borders.color
                Row {
                    id: row
                    anchors.centerIn: parent
                    spacing: 14
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 400)
                        elide: Text.ElideRight
                        text: root.note || (root.current?.label ?? "")
                        color: Appearance.colors.colOnLayer0
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                    Text {
                        id: undoText
                        visible: root.note === "" && root.current !== null
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Undo"
                        color: Appearance.colors.colPrimary
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        font.underline: undoArea.containsMouse
                        MouseArea {
                            id: undoArea
                            anchors.fill: parent
                            anchors.margins: -8
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.undoLast()
                        }
                    }
                }
            }
        }
    }
}
