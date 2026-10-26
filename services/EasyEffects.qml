pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common

/**
 * EasyEffects bypass and output presets through its own command line
 * (`-b 3`, `--bypass-toggle`, `-p`, `-a output`, `-l <preset>`).
 *
 * Read when the right sidebar opens (audio.easyEffects.enable), never polled.
 * The CLI is only called while EasyEffects' server socket exists, so the
 * shell never starts EasyEffects; it never kills it or edits its files.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.audio?.easyEffects?.enable ?? false
    property bool available: false      // EasyEffects is running
    property bool bypassed: false
    property var presets: []            // output preset names
    property string currentPreset: ""

    function refresh() { if (root.enabled && !reader.running) reader.running = true }
    function toggleBypass() {
        if (!root.available) return
        root.bypassed = !root.bypassed      // shown at once; the read confirms
        actor.exec(["easyeffects", "--bypass-toggle"])
        confirm.restart()
    }
    function loadPreset(name) {
        if (!root.available || !root.presets.includes(name)) return
        root.currentPreset = name
        actor.exec(["easyeffects", "-l", name])
        confirm.restart()
    }

    Process {
        id: reader
        // Fixed script: nothing from outside is spliced in.
        command: ["sh", "-c", "[ -S \"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/EasyEffectsServer\" ] || { echo off; exit 0; }; "
            + "easyeffects -b 3; echo '---'; easyeffects -p; echo '---'; easyeffects -a output"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (this.text || "").split(/^---$/m)
                root.available = parts.length >= 3
                if (!root.available) return
                // -b 3: 1 = bypass on, 2 = off
                root.bypassed = parts[0].trim() === "1"
                // -p: "Output presets:", "N\tname" lines, then "Input presets:"
                const out = parts[1].split(/Input presets:/)[0]
                root.presets = out.split("\n").map(l => l.match(/^\s*\d+\t(.+)$/)).filter(m => !!m).map(m => m[1].trim())
                root.currentPreset = parts[2].trim()
            }
        }
    }
    Process { id: actor }
    Timer { id: confirm; interval: 600; onTriggered: root.refresh() }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() { if (GlobalStates.sidebarRightOpen) root.refresh() }
    }
    onEnabledChanged: refresh()

    IpcHandler {
        target: "easyEffects"
        function toggleBypass(): void { root.toggleBypass() }
        function loadPreset(name: string): void { root.loadPreset(name) }
        function refresh(): void { root.refresh() }
        function status(): string {
            return JSON.stringify({ enabled: root.enabled, running: root.available, bypassed: root.bypassed,
                preset: root.currentPreset, presets: root.presets.length })
        }
    }
}
