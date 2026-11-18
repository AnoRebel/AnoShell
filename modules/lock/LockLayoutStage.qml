import QtQuick
import qs.modules.common
import qs.services
import "lockLayout.js" as LockLayout

/**
 * Arranging a lock screen's elements (lockLayout.js) on a stage the size of a screen: click one to select
 * it, drag it (it snaps to the centre lines and the other elements' edges and centres, or to the grid), drag
 * its round corner handle to resize it. `edited(list)` once per finished change. Used full screen by the
 * layout editor and in miniature by Settings' lock preview (`ui`: how big a screen pixel is drawn, so the
 * outlines keep their width).
 */
Item {
    id: stage
    property var ctx
    property var elements: []
    property string selected: ""
    property bool grid: false
    property real ui: 1
    // Off when the lock screen under the stage draws the elements itself (from stage.shown).
    property bool drawElements: true
    readonly property real gridStep: Math.round(stage.height / 27)
    signal edited(var elements)

    property var draft: null        // the list while dragging
    property var guides: []
    readonly property var shown: stage.draft ?? stage.elements

    function pieceSize(e) { return e.type === "piece" ? (Pieces.entries[e.settings?.id ?? ""]?.size ?? null) : null }
    function rectOf(e) { return LockLayout.rectOf(e, stage.width, stage.height, stage.pieceSize(e)) }
    function indexOf(uid) { return stage.shown.findIndex(e => e.uid === uid) }

    LockElements {
        anchors.fill: parent
        visible: stage.drawElements
        ctx: stage.ctx
        elements: stage.shown
        miniature: true
    }

    // The grid.
    Repeater {
        model: stage.grid ? Math.ceil(stage.width / stage.gridStep) : 0
        Rectangle { required property int index; x: index * stage.gridStep; width: stage.ui; height: stage.height; color: "white"; opacity: 0.12 }
    }
    Repeater {
        model: stage.grid ? Math.ceil(stage.height / stage.gridStep) : 0
        Rectangle { required property int index; y: index * stage.gridStep; height: stage.ui; width: stage.width; color: "white"; opacity: 0.12 }
    }

    // Outlines; the selected one with its resize handle.
    Repeater {
        model: stage.shown
        Rectangle {
            required property var modelData
            readonly property var r: stage.rectOf(modelData)
            readonly property bool sel: stage.selected === modelData.uid
            x: r.x; y: r.y; width: r.w; height: r.h
            color: "transparent"
            radius: 10 * stage.ui
            border.width: (sel ? 3 : 1.5) * stage.ui
            border.color: Appearance.colors.colPrimary
            opacity: sel ? 0.95 : (edit.containsMouse ? 0.5 : 0.3)
            Rectangle {
                visible: parent.sel
                x: parent.width - width / 2; y: parent.height - height / 2
                width: 22 * stage.ui; height: width; radius: width / 2
                color: Appearance.colors.colPrimary
                border.width: 2.5 * stage.ui; border.color: "white"
            }
        }
    }
    // Snap guides while dragging.
    Repeater {
        model: stage.guides
        Rectangle {
            required property var modelData
            readonly property bool vert: modelData.axis === "x"
            x: vert ? modelData.at - width / 2 : 0
            y: vert ? 0 : modelData.at - height / 2
            width: vert ? 1.5 * stage.ui : stage.width
            height: vert ? stage.height : 1.5 * stage.ui
            color: Appearance.colors.colTertiary
        }
    }

    MouseArea {
        id: edit
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: pressed && dragUid ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property string dragUid: ""
        property bool resizing: false
        property point start
        property var startEl: null

        function hit(p) {
            for (let i = stage.shown.length - 1; i >= 0; i--) {
                const r = stage.rectOf(stage.shown[i])
                if (p.x >= r.x && p.y >= r.y && p.x <= r.x + r.w && p.y <= r.y + r.h) return stage.shown[i].uid
            }
            return ""
        }
        function onHandle(p) {
            const e = stage.shown[stage.indexOf(stage.selected)]
            if (!e) return false
            const r = stage.rectOf(e)
            return Math.hypot(p.x - (r.x + r.w), p.y - (r.y + r.h)) < 20 * stage.ui
        }
        onPressed: mouse => {
            const p = Qt.point(mouse.x, mouse.y)
            resizing = onHandle(p)
            const uid = resizing ? stage.selected : hit(p)
            stage.selected = uid
            dragUid = uid
            if (!uid) return
            start = p
            startEl = Object.assign({}, stage.elements[stage.indexOf(uid)])
        }
        onPositionChanged: mouse => {
            if (!pressed || !dragUid || !startEl) return
            const dx = mouse.x - start.x, dy = mouse.y - start.y
            if (!stage.draft && Math.hypot(dx, dy) < 3 * stage.ui) return
            const e = Object.assign({}, startEl)
            if (resizing) {
                const r0 = stage.rectOf(startEl)
                e.scale = Math.max(0.3, Math.min(4, startEl.scale * (1 + Math.max(dx / r0.w, dy / r0.h) * 2)))
                stage.guides = []
            } else {
                const r0 = stage.rectOf(startEl)
                const others = stage.elements.filter(o => o.uid !== dragUid).map(o => stage.rectOf(o))
                const sn = LockLayout.snap({ x: r0.x + dx, y: r0.y + dy, w: r0.w, h: r0.h }, others, stage.width, stage.height,
                                           8 * stage.ui, stage.grid ? stage.gridStep : 0)
                e.x = Math.max(0, Math.min(1, (sn.x + r0.w / 2) / stage.width))
                e.y = Math.max(0, Math.min(1, (sn.y + r0.h / 2) / stage.height))
                stage.guides = sn.guides
            }
            stage.draft = stage.elements.map(o => o.uid === dragUid ? e : o)
        }
        onReleased: {
            const d = stage.draft
            stage.draft = null; stage.guides = []; dragUid = ""; resizing = false
            if (d) stage.edited(d.map(o => Object.assign({}, o, { x: Math.round(o.x * 1000) / 1000, y: Math.round(o.y * 1000) / 1000,
                                                                   scale: Math.round(o.scale * 100) / 100 })))
        }
        onCanceled: { stage.draft = null; stage.guides = []; dragUid = ""; resizing = false }
    }
}
