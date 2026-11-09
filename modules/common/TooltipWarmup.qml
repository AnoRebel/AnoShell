pragma Singleton
import QtQuick
import Quickshell

/**
 * Tooltip warm-up: the first tooltip waits for a hover of `delay` ms; while
 * one is open, and for `cooldown` ms after the last closes, the next shows at
 * once (running the pointer along a row of icons).
 */
Singleton {
    id: root
    readonly property int delay: 500
    readonly property int cooldown: 1000
    property bool warm: false
    property int _open: 0

    function opened() { root._open++; root.warm = true; cool.stop() }
    function closed() { root._open = Math.max(0, root._open - 1); if (root._open === 0) cool.restart() }

    Timer { id: cool; interval: root.cooldown; onTriggered: root.warm = false }
}
