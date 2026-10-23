import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * One placed widget: its card (unless the manifest says frame: false) and
 * its QML, loaded from the registry. A widget that's missing, broken or
 * fails to load shows why in its place; the others are unaffected.
 *
 * The widget's root item gets `ctx` (live, screenName, cell) and `settings`
 * (the placed widget's settings over the manifest's defaults).
 *
 * In edit mode the card can be dragged (snaps to cells on release), resized
 * from its corner, removed, or have its settings opened; a spot that's
 * outside the grid or taken springs back. Right-click enters edit mode.
 */
Item {
    id: host
    property var placed // { uid, id, x, y, w, h, settings }
    property var ctx
    // { originX, originY, step, gap, cols, rows, screenName } from the layer
    property var grid
    property bool editing: false
    signal openSettings(var host)

    readonly property var entry: Widgets.entries[host.placed?.id ?? ""] ?? null
    readonly property var problems: Widgets.errorsOf(host.placed?.id ?? "")
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
    x: host.grid.originX + host.placed.x * host.grid.step + host.dx
    y: host.grid.originY + host.placed.y * host.grid.step + host.dy
    width: Math.max(host.grid.step - host.grid.gap, host.placed.w * host.grid.step - host.grid.gap + host.dw)
    height: Math.max(host.grid.step - host.grid.gap, host.placed.h * host.grid.step - host.grid.gap + host.dh)
    z: host.dx || host.dy || host.dw || host.dh ? 10 : 0

    // The cell geometry the current drag/resize would land on.
    readonly property var target: ({
        x: Math.round((host.x - host.grid.originX) / host.grid.step),
        y: Math.round((host.y - host.grid.originY) / host.grid.step),
        w: Math.max(1, Math.round((host.width + host.grid.gap) / host.grid.step)),
        h: Math.max(1, Math.round((host.height + host.grid.gap) / host.grid.step))
    })
    function commit() {
        const t = host.target
        Widgets.place(host.grid.screenName, host.placed.uid, t.x, t.y, t.w, t.h, host.grid.cols, host.grid.rows)
        host.dx = 0; host.dy = 0; host.dw = 0; host.dh = 0
    }

    // The card, in the active look's material (fill or glass, stroke, texture).
    SurfaceMaterial {
        anchors.fill: parent
        visible: !host.entry || host.entry.frame || loader.status !== Loader.Ready
        surface: "widget"
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

    // Right-click: edit the widgets.
    TapHandler {
        enabled: !host.editing
        acceptedButtons: Qt.RightButton
        onTapped: Widgets.editing = true
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
            border.width: 2
            border.color: Appearance.colors.colPrimary
        }
        // Drag anywhere on the card to move it.
        MouseArea {
            id: moveArea
            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            property point start
            onPressed: mouse => start = mapToItem(null, mouse.x, mouse.y)
            onPositionChanged: mouse => {
                const p = mapToItem(null, mouse.x, mouse.y)
                host.dx += p.x - start.x; host.dy += p.y - start.y
                start = p
            }
            onReleased: host.commit()
        }
        Row {
            anchors { top: parent.top; right: parent.right; margins: 6 }
            spacing: 4
            EditButton { glyph: "tune"; tip: "Settings"; visible: (host.entry?.settings ?? []).length > 0; onClicked: host.openSettings(host) }
            EditButton { glyph: "close"; tip: "Remove"; onClicked: Widgets.remove(host.grid.screenName, host.placed.uid) }
        }
        // Resize from the corner.
        Rectangle {
            anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
            width: 22; height: 22; radius: 6
            color: Appearance.colors.colPrimary
            MaterialSymbol { anchors.centerIn: parent; text: "open_in_full"; iconSize: 14; rotation: 90; color: Appearance.colors.colOnPrimary }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.SizeFDiagCursor
                property point start
                onPressed: mouse => start = mapToItem(null, mouse.x, mouse.y)
                onPositionChanged: mouse => {
                    const p = mapToItem(null, mouse.x, mouse.y)
                    host.dw += p.x - start.x; host.dh += p.y - start.y
                    start = p
                }
                onReleased: host.commit()
            }
        }
        // Where it will land.
        StyledText {
            anchors { left: parent.left; bottom: parent.bottom; margins: 8 }
            visible: moveArea.pressed || host.dw !== 0 || host.dh !== 0
            text: `${host.target.w}×${host.target.h} at ${host.target.x + 1},${host.target.y + 1}`
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
