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
 * comes from the compositor backend (the main keyboard in Hyprland's
 * devices), which is right even with keyd or other virtual keyboards. Elsewhere there is no key event to
 * hang on, and the keyboard LEDs (/sys/class/leds/*::capslock) send no file
 * events, so while the screen is locked (for the lock screen's Caps Lock
 * warning) their files are found once and re-read every 500 ms through
 * FileViews, without spawning anything. IPC `lockKeys refresh` lets
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

    // A press during a read reads again when it ends (running = true on a
    // running Process would do nothing and the press would be lost).
    property bool _again: false
    function refresh() {
        if (CompositorService.lockKeys(st => root._apply(st.capsLock, st.numLock))) return
        if (reader.running) root._again = true; else reader.running = true
    }

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
        // Finds the LED files (compositors without lock-key state).
        command: ["sh", "-c", "for f in /sys/class/leds/*::capslock/brightness /sys/class/leds/*::numlock/brightness; do [ -r \"$f\" ] && echo \"$f\"; done"]
        onRunningChanged: if (!running && root._again) { root._again = false; running = true }
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text || ""
                // LED files: every keyboard has its own; any lit one counts.
                const files = t.split("\n").filter(l => l)
                root._capsFiles = files.filter(f => f.includes("::capslock/"))
                root._numFiles = files.filter(f => f.includes("::numlock/"))
                root._readLeds()
            }
        }
    }

    // ── LEDs (not Hyprland) ──────────────────────────────────────────────
    property var _capsFiles: []
    property var _numFiles: []
    property var _ledViews: []
    function _readLeds() {
        const lit = list => list.some(f => (root._ledViews.find(v => v.path === f) ?? root._view(f)).text().trim() !== "0")
        root._apply(lit(root._capsFiles), lit(root._numFiles))
    }
    function _view(path) {
        const v = ledView.createObject(root, { path: path })
        root._ledViews = root._ledViews.concat([v])
        return v
    }
    Component {
        id: ledView
        FileView { blockLoading: true; printErrors: false }
    }

    Component.onCompleted: if (Config.ready) root.refresh()
    Connections { target: Config; function onReadyChanged() { if (Config.ready) root.refresh() } }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.refresh() }
    }
    Timer {
        interval: 500; repeat: true
        running: GlobalStates.screenLocked && root._ledViews.length > 0
        onTriggered: { for (const v of root._ledViews) v.reload(); root._readLeds() }
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
