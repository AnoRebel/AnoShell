import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A status zone as a collapsible capsule: shows only its leading icon until
 * hovered, then opens on a spring to its full width (its text), and closes
 * again a moment after the pointer leaves. The pill's length follows, so the
 * whole capsule breathes with it.
 *
 *   AnoSpotAccordion { visible: …; AnoSpotMpris { } }
 */
Item {
    id: root

    default property alias content: holder.data
    property bool enabled: true
    // Most it may open to (the room left in the pill); the content elides to it.
    property real maxWidth: Infinity
    readonly property real openWidth: Math.max(collapsedWidth, Math.min(fullWidth, maxWidth))
    // Width while collapsed: the leading icon (the zone's first child).
    readonly property real collapsedWidth: Math.ceil(item?.children?.[0]?.implicitWidth ?? 18)
    readonly property Item item: holder.children[0] ?? null
    readonly property real fullWidth: item?.implicitWidth ?? 0
    readonly property bool expanded: !enabled || hover.hovered || linger.running

    // Set visible on the accordion, not its child: a child's visibility
    // reads as false while its parent is hidden, so copying it would stick.
    implicitHeight: item?.implicitHeight ?? 0
    implicitWidth: Math.round(_w)
    property real _w: expanded ? openWidth : Math.min(collapsedWidth, fullWidth)
    Behavior on _w { id: wMotion; MotionSpring { token: wMotion.targetValue > root._w ? "liquid" : "settle" } }
    Layout.preferredWidth: implicitWidth
    clip: true

    HoverHandler { id: hover; onHoveredChanged: if (!hovered) linger.restart() }
    Timer { id: linger; interval: 500 }

    Item {
        id: holder
        width: root.openWidth
        height: root.height
        // The item keeps its own layout width; we only clip the rest.
        onChildrenChanged: if (children[0]) { children[0].width = Qt.binding(() => root.openWidth); children[0].height = Qt.binding(() => root.height) }
    }
}
