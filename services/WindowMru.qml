pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * Most-recently-used window order, shared by every switcher style. Follows
 * focus changes (a signal, no polling): the focused window moves to the front;
 * closed windows drop out; windows never focused keep their list order after
 * the ones that were.
 *
 *   WindowMru.ordered   // [Toplevel], most recent first
 */
Singleton {
    id: root

    property var _order: []   // Toplevels, most recent first
    readonly property var ordered: {
        const all = ToplevelManager.toplevels.values
        const seen = root._order.filter(t => all.includes(t))
        return seen.concat(all.filter(t => !seen.includes(t)))
    }

    function _touch(t) {
        if (!t) return
        root._order = [t].concat(root._order.filter(x => x !== t && ToplevelManager.toplevels.values.includes(x)))
    }

    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() { root._touch(ToplevelManager.activeToplevel) }
    }
    Component.onCompleted: _touch(ToplevelManager.activeToplevel)
}
