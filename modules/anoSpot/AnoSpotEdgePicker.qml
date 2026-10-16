import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Edge picker for moving the pill: a transparent full-screen layer on one
 * screen whose four edges are drop zones; the one nearest the pointer lights up
 * with a ghost of the pill. Rest on an edge's band for a moment (dwell), or
 * click its zone, to move there. Right-click cancels.
 *
 * Dwell, not release: when this layer maps under a held button the compositor
 * moves pointer focus to it, so it gets the motion but the release reaches
 * neither it nor the pill.
 *
 * Why an overlay: a Wayland client only gets pointer motion over its own
 * surface, so the small pill window can't follow a drag across the screen.
 * This full-screen layer can, in screen coordinates, on every compositor.
 */
PanelWindow {
    id: root

    property string current: "top"
    property bool open: false
    // A drag release just opened us: take the first pointer report as the drop.
    property bool dropPending: false
    signal chose(string edge)
    signal cancelled()

    visible: open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:anospot:edgePicker"
    WlrLayershell.layer: WlrLayer.Overlay
    anchors { top: true; bottom: true; left: true; right: true }

    property string hovered: ""
    Timer {
        id: dwell
        property string edge: ""
        interval: 350
        onTriggered: if (root.open && root.hovered === edge) root.chose(edge)
    }
    function _edgeAt(x, y) {
        const d = { top: y, bottom: height - y, left: x, right: width - x }
        return Object.keys(d).reduce((a, b) => d[a] <= d[b] ? a : b)
    }
    onOpenChanged: if (!open) { hovered = ""; dropPending = false }
    // The compositor reports the pointer to the new surface only after the
    // grab ends, sometimes late under load: allow it a moment.
    Timer { running: root.dropPending; interval: 2000; onTriggered: root.dropPending = false }
    // Nothing chosen for a while: close.
    Timer { running: root.open; interval: 8000; onTriggered: root.cancelled() }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.DragMoveCursor
        function _point(x, y) {
            root.hovered = root._edgeAt(x, y)
            // Resting inside another edge's band arms the drop (button state
            // isn't reported to this layer during the drag, so dwell works the
            // same whether you drag or just move there).
            const d = { top: y, bottom: root.height - y, left: x, right: root.width - x }[root.hovered]
            const armed = root.hovered !== root.current && d < 90
            if (!armed) dwell.stop()
            else if (dwell.edge !== root.hovered || !dwell.running) { dwell.edge = root.hovered; dwell.restart() }
            if (root.dropPending) { root.dropPending = false; if (root.hovered !== root.current) root.chose(root.hovered) }
        }
        onPositionChanged: mouse => _point(mouse.x, mouse.y)
        onEntered: _point(mouseX, mouseY)
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) root.cancelled()
            else root.chose(root._edgeAt(mouse.x, mouse.y))
        }
    }

    // Zones: a soft band along each edge; the hovered one brightens and shows
    // a ghost pill where it would land.
    Repeater {
        model: ["top", "bottom", "left", "right"]
        Item {
            id: zone
            required property string modelData
            readonly property bool vertical: modelData === "left" || modelData === "right"
            readonly property bool active: root.hovered === modelData
            readonly property real band: 90
            x: modelData === "right" ? root.width - band : 0
            y: modelData === "bottom" ? root.height - band : 0
            width: vertical ? band : root.width
            height: vertical ? root.height : band
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: zone.vertical ? Gradient.Horizontal : Gradient.Vertical
                    GradientStop { position: 0; color: ColorUtils.transparentize(Appearance.colors.colPrimary, (zone.modelData === "top" || zone.modelData === "left") ? (zone.active ? 0.35 : 0.12) : 0) }
                    GradientStop { position: 1; color: ColorUtils.transparentize(Appearance.colors.colPrimary, (zone.modelData === "bottom" || zone.modelData === "right") ? (zone.active ? 0.35 : 0.12) : 0) }
                }
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            // Ghost of the pill at its landing spot.
            Rectangle {
                width: zone.vertical ? 36 : 220
                height: zone.vertical ? 140 : 36
                radius: Math.min(width, height) / 2
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: zone.vertical ? (zone.modelData === "left" ? -(zone.band / 2 - 24) : (zone.band / 2 - 24)) : 0
                anchors.verticalCenterOffset: zone.vertical ? 0 : (zone.modelData === "top" ? -(zone.band / 2 - 24) : (zone.band / 2 - 24))
                color: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.85)
                border.width: 2
                border.color: Appearance.colors.colPrimary
                opacity: zone.active ? 1 : (zone.modelData === root.current ? 0.35 : 0)
                scale: zone.active ? 1 : 0.9
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        text: "Move to an edge (or click it) to put the pill there · right-click to cancel"
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer0
        style: Text.Outline
        styleColor: ColorUtils.transparentize(Appearance.colors.colLayer0, 0.8)
        opacity: 0.85
    }
}
