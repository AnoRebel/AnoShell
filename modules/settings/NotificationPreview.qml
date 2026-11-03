import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Settings' notification and OSD preview (settings-wiring "Interactive
 * previews in Settings"): two notifications and the volume OSD in miniature,
 * drawn with the shell's own notification item and OSD widgets. Edited in
 * place, written once on release:
 *   - drag the notification stack: it snaps to the nearest of the six
 *     positions (notifications.position);
 *   - drag its inner edge: the popups' width (notifications.popupWidth);
 *   - drag the OSD up or down: top or bottom (osd.position).
 */
PreviewScreen {
    id: root
    maxHeight: 300

    readonly property string position: Config.options?.notifications?.position ?? "topRight"
    readonly property real margin: Config.options?.notifications?.edgeMargin ?? 8
    readonly property real popupWidth: Math.max(280, Math.min(640, Config.options?.notifications?.popupWidth ?? 380))
    readonly property string osdPosition: Config.options?.osd?.position ?? "bottom"
    readonly property bool isTop: position.startsWith("top")
    readonly property bool isLeft: position.endsWith("Left")
    readonly property bool isRight: position.endsWith("Right")

    // Demo notifications, as the notification service hands them over.
    readonly property var demo: [
        { notificationId: -1, appName: "Calendar", appIcon: "x-office-calendar", summary: "Design review", body: "In 10 minutes · Room 2", actions: [] },
        { notificationId: -2, appName: "Downloads", appIcon: "folder-download", summary: "Download finished", body: "anoshell-demo.tar.gz", actions: [] }
    ]

    // The stack where it is, or where the drag has it.
    readonly property real stackW: edit.mode === "width" ? edit.draftW : root.popupWidth
    Column {
        id: stack
        spacing: 8
        width: root.stackW
        x: edit.mode === "move" ? edit.draftX
            : root.isLeft ? root.margin : root.isRight ? root.worldW - width - root.margin : (root.worldW - width) / 2
        y: edit.mode === "move" ? edit.draftY
            : root.isTop ? root.margin + 48 : root.worldH - height - root.margin - 48
        Repeater {
            model: root.demo
            NotificationItem {
                required property var modelData
                width: stack.width
                notification: modelData
                compact: true
            }
        }
    }
    // The width handle, on the stack's inner side.
    Rectangle {
        id: widthHandle
        readonly property bool onLeft: root.isRight
        width: 10; height: Math.min(stack.height, 80); radius: 5
        x: onLeft ? stack.x - width - 6 : stack.x + stack.width + 6
        y: stack.y + (stack.height - height) / 2
        color: Appearance?.colors.colPrimary ?? "#D0BCFF"
        opacity: edit.containsMouse || edit.mode === "width" ? 0.95 : 0.5
    }

    // The volume OSD, as OSD.qml draws it.
    SurfaceMaterial {
        id: osd
        surface: "osd"
        width: 280; height: 56; radius: 28
        x: (root.worldW - width) / 2
        y: edit.mode === "osd" ? edit.draftOsdY : root.osdPosition === "top" ? 40 : root.worldH - height - 40
        color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
        border.width: 1
        border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
        RowLayout {
            anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
            spacing: 12
            MaterialSymbol { text: "volume_up"; iconSize: 24; fill: 1; color: Appearance?.colors.colPrimary ?? "#65558F" }
            StyledProgressBar { Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; valueBarHeight: 6; value: 0.62 }
        }
    }

    // The six places the stack can snap to, shown while it's dragged.
    Repeater {
        model: edit.mode === "move" ? ["topLeft", "top", "topRight", "bottomLeft", "bottom", "bottomRight"] : []
        Rectangle {
            required property string modelData
            readonly property bool atTop: modelData.startsWith("top")
            readonly property real cx: modelData.endsWith("Left") ? root.margin + root.stackW / 2
                : modelData.endsWith("Right") ? root.worldW - root.margin - root.stackW / 2 : root.worldW / 2
            width: root.stackW; height: 90; radius: 16
            x: cx - width / 2; y: atTop ? root.margin + 48 : root.worldH - height - root.margin - 48
            color: "transparent"
            border.width: 3
            border.color: Appearance?.colors.colPrimary ?? "#D0BCFF"
            opacity: edit.snap === modelData ? 0.9 : 0.25
        }
    }

    function _snapAt(cx, cy) {
        const col = cx < root.worldW / 3 ? "Left" : cx > root.worldW * 2 / 3 ? "Right" : ""
        return (cy < root.worldH / 2 ? "top" : "bottom") + col
    }
    function _in(item, p, pad) { return p.x >= item.x - pad && p.y >= item.y - pad && p.x <= item.x + item.width + pad && p.y <= item.y + item.height + pad }

    MouseArea {
        id: edit
        anchors.fill: parent
        z: 100
        hoverEnabled: true
        preventStealing: true
        cursorShape: mode === "width" ? Qt.SizeHorCursor : mode !== "" ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property string mode: ""      // move | width | osd
        property point start
        property real startX; property real startY; property real startW
        property real draftX; property real draftY; property real draftW; property real draftOsdY
        property string snap: ""
        property bool moved: false

        onPressed: mouse => {
            const p = Qt.point(mouse.x, mouse.y)
            start = p; moved = false; snap = ""
            // The start first: once `mode` is set, the items follow the drafts.
            if (root._in(widthHandle, p, 12)) { startW = root.popupWidth; draftW = startW; mode = "width" }
            else if (root._in(stack, p, 0)) { startX = stack.x; startY = stack.y; draftX = startX; draftY = startY; mode = "move" }
            else if (root._in(osd, p, 0)) { startY = osd.y; draftOsdY = startY; mode = "osd" }
            else mode = ""
        }
        onPositionChanged: mouse => {
            if (!pressed || mode === "") return
            const dx = mouse.x - start.x, dy = mouse.y - start.y
            if (Math.hypot(dx, dy) > 6) moved = true
            if (mode === "move") {
                draftX = startX + dx; draftY = startY + dy
                snap = root._snapAt(draftX + root.stackW / 2, draftY + stack.height / 2)
            } else if (mode === "width") {
                draftW = Math.max(280, Math.min(640, startW + (widthHandle.onLeft ? -dx : dx) * (root.isLeft || root.isRight ? 1 : 2)))
            } else if (mode === "osd") {
                draftOsdY = Math.max(0, Math.min(root.worldH - osd.height, startY + dy))
            }
        }
        onReleased: {
            const m = mode, s = snap
            mode = ""
            if (!moved) return
            if (m === "move" && s && s !== root.position) Config.setNestedValue("notifications.position", s)
            else if (m === "width" && Math.round(draftW) !== Math.round(root.popupWidth)) Config.setNestedValue("notifications.popupWidth", Math.round(draftW))
            else if (m === "osd") {
                const pos = draftOsdY + osd.height / 2 < root.worldH / 2 ? "top" : "bottom"
                if (pos !== root.osdPosition) Config.setNestedValue("osd.position", pos)
            }
        }
        onCanceled: mode = ""
    }
}
