pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services

/**
 * Focus mode: one switch for "leave me alone" — the bar goes away and Do
 * Not Disturb comes on (critical notifications still show). Turning it off
 * puts back what was there before, not a fixed state.
 *
 * IPC: `focus toggle|on|off|status`; Actions has a "Focus mode" step.
 */
Singleton {
    id: root
    property bool active: false
    property var _before: null // { barOpen, silent }

    function set(on) {
        if (on === root.active) return
        if (on) {
            root._before = { barOpen: GlobalStates.barOpen, silent: Notifications.silent }
            GlobalStates.barOpen = false
            Notifications.silent = true
        } else {
            const b = root._before ?? { barOpen: true, silent: false }
            GlobalStates.barOpen = b.barOpen
            Notifications.silent = b.silent
            root._before = null
        }
        root.active = on
    }
    function toggle() { root.set(!root.active) }

    IpcHandler {
        target: "focus"
        function toggle(): void { root.toggle() }
        function on(): void { root.set(true) }
        function off(): void { root.set(false) }
        function status(): string { return root.active ? "on" : "off" }
    }
}
