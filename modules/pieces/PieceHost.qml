import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * One placed piece: its card (unless the manifest says frame: false) and
 * its QML, loaded from the registry. A piece that's missing, broken or
 * fails to load shows why in its place; the others are unaffected.
 *
 * The piece's root item gets `ctx` (live, screenName, cell) and `settings`
 * (the placed piece's settings over the manifest's defaults).
 *
 * In edit mode the card can be dragged (it lands on the free spot nearest
 * where it's let go), resized from its corner (pushing its neighbours aside;
 * it stops at the last size that fits), removed, or have its settings
 * opened. While it moves, a shape shows where it will land and the
 * neighbours it would push move there. Right-click enters edit mode.
 */
Item {
    id: host
    property var placed // { uid, id, x, y, w, h, settings }
    property var ctx
    // { originX, originY, step, gap, cols, rows, screenName } from the layer
    property var grid
    property bool editing: false
    property bool selected: false   // the one the arrow keys move (edit mode)
    signal openSettings(var host)
    signal picked()
    // Where it takes input (the layer's mask collects these).
    readonly property Region region: Region { item: host }

    readonly property var entry: Pieces.entries[host.placed?.id ?? ""] ?? null
    readonly property var problems: Pieces.errorsOf(host.placed?.id ?? "")
    readonly property var settings: {
        const s = {}
        for (const d of host.entry?.settings ?? []) if (d.key) s[d.key] = d.default
        return Object.assign(s, host.placed?.settings ?? {})
    }

    // While dragging or resizing: the offset from the placed cell geometry.
    property real dx: 0
    property real dy: 0
    property real dw: 0
    property real dh: 0
    // Where it sits: placed, or where another piece's drag would push it.
    readonly property var cell: {
        const p = Pieces.preview
        if (host.editing && p && p.screen === host.grid.screenName && p.uid !== host.placed.uid)
            return p.page.find(o => o.uid === host.placed.uid) ?? host.placed
        return host.placed
    }
    x: host.grid.originX + host.cell.x * host.grid.step + host.dx
    y: host.grid.originY + host.cell.y * host.grid.step + host.dy
    width: Math.max(host.grid.step - host.grid.gap, host.cell.w * host.grid.step - host.grid.gap + host.dw)
    height: Math.max(host.grid.step - host.grid.gap, host.cell.h * host.grid.step - host.grid.gap + host.dh)
    z: host.dragging ? 10 : 0
    readonly property bool dragging: moveArea.pressed || resizeArea.pressed
    // Pushed aside, snapping in, a key move: animated (not under the pointer).
    Behavior on x { enabled: host.editing && !host.dragging; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    Behavior on y { enabled: host.editing && !host.dragging; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    Behavior on width { enabled: host.editing && !host.dragging; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }
    Behavior on height { enabled: host.editing && !host.dragging; animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this) }

    // The cell geometry the current drag/resize would land on.
    readonly property var target: ({
        x: Math.round((host.x - host.grid.originX) / host.grid.step),
        y: Math.round((host.y - host.grid.originY) / host.grid.step),
        w: Math.max(1, Math.round((host.width + host.grid.gap) / host.grid.step)),
        h: Math.max(1, Math.round((host.height + host.grid.gap) / host.grid.step))
    })
    readonly property string mode: moveArea.pressed ? "drop" : resizeArea.pressed ? "resize" : ""
    // The page as the drag would leave it (null: nowhere fits) and this piece's spot in it.
    readonly property var plan: !host.editing || !host.mode ? null
        : Pieces.plan(host.grid.screenName, host.placed.uid, host.mode,
                      host.mode === "drop" ? host.target.x : host.target.w,
                      host.mode === "drop" ? host.target.y : host.target.h, host.grid.cols, host.grid.rows)
    readonly property var landing: host.plan?.find(o => o.uid === host.placed.uid) ?? null
    onPlanChanged: {
        if (host.plan) Pieces.preview = { screen: host.grid.screenName, uid: host.placed.uid, page: host.plan }
        else if (Pieces.preview?.uid === host.placed.uid) Pieces.preview = null
    }
    function commit(mode) {
        const t = host.target
        Pieces.preview = null
        Pieces.place(host.grid.screenName, host.placed.uid, mode, mode === "drop" ? t.x : t.w, mode === "drop" ? t.y : t.h, host.grid.cols, host.grid.rows)
        host.dx = 0; host.dy = 0; host.dw = 0; host.dh = 0
    }

    // Where it will land, under the card being dragged.
    Rectangle {
        z: -1
        visible: !!host.landing
        x: host.grid.originX + (host.landing?.x ?? 0) * host.grid.step - host.x
        y: host.grid.originY + (host.landing?.y ?? 0) * host.grid.step - host.y
        width: (host.landing?.w ?? 1) * host.grid.step - host.grid.gap
        height: (host.landing?.h ?? 1) * host.grid.step - host.grid.gap
        radius: Appearance.rounding.large
        color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.22)
        border.width: 2
        border.color: Appearance.colors.colPrimary
    }

    // The card, in the active look's material (fill or glass, stroke, texture).
    SurfaceMaterial {
        anchors.fill: parent
        visible: !host.entry || host.entry.frame || loader.status !== Loader.Ready
        surface: "piece"
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1
        textColor: Appearance.colors.colOnLayer1
    }

    Loader {
        id: loader
        anchors.fill: parent
        anchors.margins: host.entry?.frame === false ? 0 : 12
        asynchronous: true
        active: host.problems.length === 0
        source: host.problems.length === 0 ? host.entry.url : ""
        onLoaded: {
            if (item.hasOwnProperty("ctx")) item.ctx = Qt.binding(() => host.ctx)
            if (item.hasOwnProperty("settings")) item.settings = Qt.binding(() => host.settings)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        visible: host.problems.length > 0 || loader.status === Loader.Error
        spacing: 4
        MaterialSymbol { text: "broken_image"; iconSize: 22; color: Appearance.colors.colError }
        StyledText {
            Layout.fillWidth: true; Layout.fillHeight: true
            wrapMode: Text.Wrap; elide: Text.ElideRight
            text: !host.entry ? `"${host.placed?.id}" isn't installed`
                : host.problems.length ? `${host.entry.name}: ${host.problems.join("; ")}`
                : `${host.entry.name} didn't load`
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    // Right-click: edit the pieces.
    TapHandler {
        enabled: !host.editing
        acceptedButtons: Qt.RightButton
        onTapped: Pieces.editing = true
    }

    // ── Edit mode ───────────────────────────────────────────────────────
    Item {
        id: editLayer
        anchors.fill: parent
        visible: host.editing
        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.12)
            border.width: host.selected ? 4 : 2
            border.color: Appearance.colors.colPrimary
        }
        // Drag anywhere on the card to move it.
        MouseArea {
            id: moveArea
            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point start
            onPressed: mouse => { start = mapToItem(null, mouse.x, mouse.y); host.picked() }
            onPositionChanged: mouse => {
                const p = mapToItem(null, mouse.x, mouse.y)
                host.dx += p.x - start.x; host.dy += p.y - start.y
                start = p
            }
            onReleased: host.commit("drop")
        }
        Row {
            anchors { top: parent.top; right: parent.right; margins: 6 }
            spacing: 4
            EditButton { glyph: "tune"; tip: "Settings"; visible: (host.entry?.settings ?? []).length > 0; onClicked: host.openSettings(host) }
            EditButton { glyph: "close"; tip: "Remove"; onClicked: Pieces.remove(host.grid.screenName, host.placed.uid) }
        }
        // Resize from the corner.
        Rectangle {
            anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
            width: 22; height: 22; radius: 6
            color: Appearance.colors.colPrimary
            MaterialSymbol { anchors.centerIn: parent; text: "open_in_full"; iconSize: 14; rotation: 90; color: Appearance.colors.colOnPrimary }
            MouseArea {
                id: resizeArea
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.SizeFDiagCursor
                property point start
                onPressed: mouse => { start = mapToItem(null, mouse.x, mouse.y); host.picked() }
                onPositionChanged: mouse => {
                    const p = mapToItem(null, mouse.x, mouse.y)
                    host.dw += p.x - start.x; host.dh += p.y - start.y
                    start = p
                }
                onReleased: host.commit("resize")
            }
        }
        // Where it will land.
        StyledText {
            anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
            visible: host.dragging
            text: host.landing ? `${host.landing.w}×${host.landing.h} at ${host.landing.x + 1},${host.landing.y + 1}` : "No room"
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colPrimary
        }
    }
    component EditButton: RippleButton {
        property string glyph
        property string tip
        implicitWidth: 28; implicitHeight: 28; buttonRadius: 14
        colBackground: Appearance.colors.colLayer2
        contentItem: MaterialSymbol { text: parent.glyph; iconSize: 16; horizontalAlignment: Text.AlignHCenter; color: Appearance.colors.colOnLayer2 }
        StyledToolTip { text: parent.tip }
    }
}
