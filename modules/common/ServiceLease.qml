import QtQuick

/**
 * Holds a named lease on a service (acquire/release) while `active` is true,
 * so the service only does work (polling, streams) while something visible
 * needs it.  Usage:
 *   ServiceLease { service: ResourceUsage; name: "hud"; active: GlobalStates.hudVisible }
 */
QtObject {
    id: root
    required property var service
    required property string name
    property bool active: true

    // Leases are counted per name, so a holder releases only what it holds:
    // one created inactive (or destroyed after going inactive) used to cancel
    // another holder's lease under the same name.
    property var _heldOn: null
    function _sync() {
        const want = root.active ? root.service : null
        if (want === root._heldOn) return
        root._heldOn?.release(root.name)
        root._heldOn = want
        want?.acquire(root.name)
    }
    onActiveChanged: _sync()
    onServiceChanged: _sync()
    Component.onCompleted: _sync()
    Component.onDestruction: { root._heldOn?.release(root.name); root._heldOn = null }
}
