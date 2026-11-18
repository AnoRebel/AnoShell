pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Terminal looks and prompt styles (terminal.*): when they change, runs
 * scripts/terminal/apply-terminal.sh (it reads your config file, so a second
 * after the change), then asks anod to rewrite the terminal window rules in its
 * managed compositor file. The palette's prompt colours follow from applycolor.sh.
 */
Singleton {
    id: root
    function load() {}

    readonly property var t: Config.options?.terminal ?? null
    // Everything the script reads, so any change re-runs it.
    readonly property string key: !root.t ? "" : JSON.stringify([root.t.enable, root.t.apps?.kitty, root.t.apps?.foot,
        root.t.apps?.ghostty, root.t.apps?.alacritty, root.t.background, root.t.opacity, root.t.blur, root.t.padding,
        root.t.cursor, root.t.prompt, root.t.shells])
    property string _applied: ""
    property string lastLog: ""
    // Ready at start: what's on disk is already applied.
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) root._applied = root.key }
    }
    Component.onCompleted: if (Config.ready) root._applied = root.key
    onKeyChanged: if (Config.ready && root._applied !== "") soon.restart()
    Timer {
        id: soon
        interval: 1000
        onTriggered: {
            if (root.key === root._applied) return
            root._applied = root.key
            proc.running = false
            proc.running = true
        }
    }
    function applyNow(): void { root._applied = root.key; proc.running = false; proc.running = true }
    Process {
        id: proc
        command: [Quickshell.shellPath("scripts/terminal/apply-terminal.sh")]
        stdout: StdioCollector { onStreamFinished: root.lastLog = text.trim() }
        onExited: code => {
            if (code !== 0) console.warn(`[TerminalLooks] apply-terminal.sh exited ${code}: ${root.lastLog}`)
            Anod.call("terminal.refresh", {}, () => {})
        }
    }
}
