import QtQuick
import qs
import qs.modules.common
import qs.modules.lock
import qs.services

/**
 * Settings' lock screen preview (settings-wiring "Interactive previews in
 * Settings"): the chosen lock screen in miniature, nothing typed is checked
 * (its field takes no input). The built-in one is edited in place: drag a
 * block (clock, avatar and name, status row, password field) anywhere, or
 * its corner handle to resize it — written once on release as lock.layout.
 * A lock screen package is shown as it is.
 */
PreviewScreen {
    id: root
    maxHeight: 300
    readonly property bool builtin: LockScreens.selected === "default" || !LockScreens.current
    readonly property var surface: builtin ? (builtinLoader.item ?? null) : null

    // A preview context: nothing is checked, submit() does nothing.
    LockContext { id: previewCtx; preview: true }

    Loader {
        id: builtinLoader
        anchors.fill: parent
        active: root.builtin
        sourceComponent: DefaultLockSurface { ctx: previewCtx; miniature: true }
    }
    Loader {
        anchors.fill: parent
        active: !root.builtin
        sourceComponent: LockSurfaceHost { packageId: LockScreens.selected; ctx: previewCtx; focus: false }
    }

    // ── Editing the built-in one ────────────────────────────────────────
    property var rects: ({})
    property string selected: ""
    function refresh() { root.rects = root.surface?.blockRects() ?? ({}) }
    Timer { id: refreshSoon; interval: 60; onTriggered: root.refresh() }
    Connections {
        target: Config.options?.lock ?? null
        function onLayoutChanged() { refreshSoon.restart() }
    }
    onSurfaceChanged: refreshSoon.restart()
    onWidthChanged: refreshSoon.restart()
    Timer { running: root.builtin && Object.keys(root.rects).length === 0; interval: 250; repeat: true; onTriggered: root.refresh() }

    // Outlines of the movable blocks; the selected one has a resize handle.
    Repeater {
        model: root.builtin ? Object.keys(root.rects) : []
        Rectangle {
            required property string modelData
            readonly property var r: edit.dragKey === modelData ? edit.draft : root.rects[modelData]
            visible: !!r
            x: r?.x ?? 0; y: r?.y ?? 0; width: r?.w ?? 0; height: r?.h ?? 0
            z: 50
            color: "transparent"
            radius: 12
            border.width: root.selected === modelData || edit.dragKey === modelData ? 4 : 2
            border.color: Appearance?.colors.colPrimary ?? "#D0BCFF"
            opacity: root.selected === modelData || edit.dragKey === modelData ? 0.95 : (edit.containsMouse ? 0.45 : 0.25)
            Rectangle {
                visible: root.selected === parent.modelData
                anchors { right: parent.right; bottom: parent.bottom; margins: -14 }
                width: 28; height: 28; radius: 14
                color: Appearance?.colors.colPrimary ?? "#D0BCFF"
                border.width: 3; border.color: "white"
            }
        }
    }

    MouseArea {
        id: edit
        anchors.fill: parent
        z: 100
        hoverEnabled: true
        preventStealing: true
        enabled: root.builtin
        cursorShape: dragKey ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property string dragKey: ""
        property bool resizing: false
        property var draft: null
        property point start
        property var startRect: null

        function blockAt(p) {
            const keys = Object.keys(root.rects)
            for (let i = keys.length - 1; i >= 0; i--) {
                const r = root.rects[keys[i]]
                if (p.x >= r.x && p.y >= r.y && p.x <= r.x + r.w && p.y <= r.y + r.h) return keys[i]
            }
            return ""
        }
        function onHandle(p) {
            const r = root.rects[root.selected]
            return !!r && Math.hypot(p.x - (r.x + r.w), p.y - (r.y + r.h)) < 36
        }
        onPressed: mouse => {
            const p = Qt.point(mouse.x, mouse.y)
            resizing = onHandle(p)
            const key = resizing ? root.selected : blockAt(p)
            root.selected = key
            if (!key) return
            dragKey = key
            start = p
            startRect = Object.assign({}, root.rects[key])
            draft = Object.assign({}, startRect)
        }
        onPositionChanged: mouse => {
            if (!pressed || !dragKey) return
            const dx = mouse.x - start.x, dy = mouse.y - start.y
            const s = startRect
            if (resizing) {
                // Scale about the block's centre, by how far the corner moved out.
                const f = Math.max(0.4 / s.scale, Math.min(3 / s.scale, 1 + Math.max(dx / s.w, dy / s.h)))
                const w = s.w * f, h = s.h * f
                draft = { x: s.x + (s.w - w) / 2, y: s.y + (s.h - h) / 2, w: w, h: h, scale: s.scale * f }
            } else {
                draft = { x: Math.max(-s.w / 2, Math.min(root.worldW - s.w / 2, s.x + dx)),
                          y: Math.max(-s.h / 2, Math.min(root.worldH - s.h / 2, s.y + dy)), w: s.w, h: s.h, scale: s.scale }
            }
        }
        onReleased: {
            const key = dragKey, d = draft, s = startRect
            dragKey = ""; draft = null; resizing = false
            if (!key || !d || (Math.abs(d.x - s.x) < 2 && Math.abs(d.y - s.y) < 2 && Math.abs(d.scale - s.scale) < 0.01)) return
            const layout = Object.assign({}, Config.options?.lock?.layout ?? {})
            // Kept whole on the screen (a block half off it can't be read).
            const cx = Math.max(d.w / 2, Math.min(root.worldW - d.w / 2, d.x + d.w / 2))
            const cy = Math.max(d.h / 2, Math.min(root.worldH - d.h / 2, d.y + d.h / 2))
            layout[key] = { x: Math.round(cx / root.worldW * 1000) / 1000,
                            y: Math.round(cy / root.worldH * 1000) / 1000,
                            scale: Math.round(d.scale * 100) / 100 }
            Config.setNestedValue("lock.layout", layout)
        }
        onCanceled: { dragKey = ""; draft = null; resizing = false }
    }
}
