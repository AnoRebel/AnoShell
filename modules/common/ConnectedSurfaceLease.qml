import QtQuick
import qs.services

/**
 * Publishes one surface's screen-space body to PanelRegistry while `active`, so
 * the connected frame fuses it into the shell silhouette. Bind x/y/w/h to the
 * surface's CURRENT (animated) geometry: the frame follows it frame by frame,
 * so the surface's own motion is the single source of truth. `progress` (0..1,
 * how far the surface has grown out of its edge) drives the frame's meniscus.
 *
 *   ConnectedSurfaceLease {
 *       key: "sidebarLeft:" + screen.name; kind: "sidebar"; edge: "left"
 *       screenName: screen.name; active: open
 *       x: 0; y: 0; w: body.width + body.x; h: screen.height
 *   }
 *
 * Writes coalesce to one per event-loop turn. Inert when connected mode is off.
 */
QtObject {
    id: root
    required property string key
    property string kind: "panel"
    property string screenName: ""
    property string edge: "top"
    property bool active: false
    property real x: 0
    property real y: 0
    property real w: 0
    property real h: 0
    property real progress: 1
    property real reserve: 0        // exclusive zone this surface holds on its edge
    property bool detached: false   // an island off its edge: joins by a liquid neck
    property var neckK: undefined   // neck smoothing radius (default connectedRadius)
    property int priority: 0
    property var surfaceRadius: undefined
    property bool omitStartConnector: false
    property bool omitEndConnector: false
    // Publish in the same turn instead of coalescing to the next one, so the
    // frame draws a moving surface's body in the same frame as its content
    // instead of one behind (content running ahead of its background reads
    // as stutter). On for every surface; false coalesces to the next turn.
    property bool immediate: true

    property string _owner: ""
    property string _ownedKey: ""
    property int _rev: 0

    function _publish() {
        if (!PanelRegistry.enabled || !root.active || !root.screenName) {
            root._release()
            return
        }
        if (!root._owner) { root._owner = PanelRegistry.claim(root.key); root._ownedKey = root.key }
        const geom = {
            "kind": root.kind, "screenName": root.screenName, "edge": root.edge,
            "x": root.x, "y": root.y, "w": root.w, "h": root.h,
            "progress": Math.max(0, Math.min(1, root.progress)), "reserve": root.reserve,
            "detached": root.detached, "neckK": root.neckK,
            "priority": root.priority, "surfaceRadius": root.surfaceRadius,
            "omitStartConnector": root.omitStartConnector, "omitEndConnector": root.omitEndConnector
        }
        if (!PanelRegistry.publish(root.key, root._owner, ++root._rev, geom, root.immediate)
                && PanelRegistry._owner[root.key] === undefined) {
            // Ownership was pruned under us (a monitor came and went): claim
            // again. A key taken by another live lease stays theirs.
            root._owner = PanelRegistry.claim(root.key)
            root._ownedKey = root.key
            PanelRegistry.publish(root.key, root._owner, ++root._rev, geom)
        }
    }
    function _release() {
        if (root._owner) PanelRegistry.release(root._ownedKey, root._owner)
        root._owner = ""
    }
    // Coalesce writes to one per event-loop turn. A Timer owned by the lease
    // (not Qt.callLater) so a pending write dies with a destroyed lease.
    readonly property Timer _pending: Timer { interval: 0; onTriggered: root._publish() }
    // Immediate: at the end of this turn (x, y, w and h changing together
    // publish once), still before the frame is drawn.
    function _schedule() { if (root.immediate) PanelRegistry.queueLease(root); else root._pending.restart() }

    onActiveChanged: _schedule()
    onXChanged: _schedule()
    onYChanged: _schedule()
    onWChanged: _schedule()
    onHChanged: _schedule()
    onProgressChanged: _schedule()
    onReserveChanged: _schedule()
    onDetachedChanged: _schedule()
    onNeckKChanged: _schedule()
    onScreenNameChanged: { _release(); _schedule() }
    onKeyChanged: { _release(); _schedule() }
    onEdgeChanged: _schedule()
    onOmitStartConnectorChanged: _schedule()
    onOmitEndConnectorChanged: _schedule()
    onSurfaceRadiusChanged: _schedule()
    readonly property Connections _cfg: Connections {
        target: PanelRegistry
        function onEnabledChanged() { root._owner = ""; root._schedule() }
    }
    Component.onCompleted: _schedule()
    Component.onDestruction: { PanelRegistry.dropLease(root); _release() }
}
