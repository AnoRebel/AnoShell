pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

/**
 * Caps Lock / Num Lock state, read on demand (no polling).
 *
 * Hyprland: the bundled config binds Caps_Lock and Num_Lock (non-consuming,
 * on release, also while locked) to the `lockKeys` global shortcut; the state
 * comes from the main keyboard in `hyprctl devices`, which is right even
 * with keyd or other virtual keyboards. Elsewhere there is no key event to
 * hang on, and the keyboard LEDs (/sys/class/leds/*::capslock) send no file
 * events, so they are read every 500 ms only while the screen is locked
 * (for the lock screen's Caps Lock warning). IPC `lockKeys refresh` lets
 * other compositors' binds trigger a read too.
 *
 * changed(kind) fires on a real change ("capslock" / "numlock").
 */
Singleton {
    id: root

    property bool capsLock: false
    property bool numLock: false
    property bool known: false
    signal changed(string kind)

    function refresh() { if (!reader.running) reader.running = true }

    function _apply(caps, num) {
        const first = !root.known
        const capsChanged = caps !== root.capsLock, numChanged = num !== root.numLock
        root.capsLock = caps
        root.numLock = num
        root.known = true
        if (first) return
        if (capsChanged) root.changed("capslock")
        if (numChanged) root.changed("numlock")
    }

    Process {
        id: reader
        command: CompositorService.isHyprland
            ? ["hyprctl", "devices", "-j"]
            : ["sh", "-c", "for k in capslock numlock; do v=0; for f in /sys/class/leds/*::$k/brightness; do [ -r \"$f\" ] && [ \"$(cat \"$f\")\" != 0 ] && v=1; done; printf '%s ' $v; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text || ""
                if (CompositorService.isHyprland) {
                    try {
                        const kb = (JSON.parse(t).keyboards ?? []).find(k => k.main)
                        if (kb) root._apply(!!kb.capsLock, !!kb.numLock)
                    } catch (e) {}
                    return
                }
                const v = t.trim().split(/\s+/)
                if (v.length === 2) root._apply(v[0] === "1", v[1] === "1")
            }
        }
    }

    Component.onCompleted: if (Config.ready) root.refresh()
    Connections { target: Config; function onReadyChanged() { if (Config.ready) root.refresh() } }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.refresh() }
    }
    Timer {
        interval: 500; repeat: true
        running: GlobalStates.screenLocked && !CompositorService.isHyprland
        onTriggered: root.refresh()
    }

    GlobalShortcut {
        name: "lockKeys"
        description: "Caps Lock / Num Lock pressed (bind non-consuming, on release)"
        // the bind fires on release; read on either edge
        onPressed: root.refresh()
        onReleased: root.refresh()
    }
    IpcHandler {
        target: "lockKeys"
        function refresh(): void { root.refresh() }
        function status(): string { return JSON.stringify({ capsLock: root.capsLock, numLock: root.numLock }) }
    }
}
