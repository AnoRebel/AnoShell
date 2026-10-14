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

    function _sync() { root.active ? root.service?.acquire(root.name) : root.service?.release(root.name) }
    onActiveChanged: _sync()
    Component.onCompleted: _sync()
    Component.onDestruction: root.service?.release(root.name)
}
