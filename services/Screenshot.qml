pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Screenshots: region, window or screen, now or after a delay, written to a
 * temp file (the preview card copies, saves or edits it from there).
 *
 *   Hyprland (and other wlroots-likes): slurp + grim; the window comes from
 *     hyprctl activewindow.
 *   niri: its own actions (screenshot / screenshot-window / screenshot-screen
 *     --path); the region is niri's interactive screenshot UI.
 *
 *   qs -c ano ipc call screenshot region|window|screen
 *   qs -c ano ipc call screenshot delayed screen 5
 */
Singleton {
    id: root

    // Private to you (0700 in the runtime dir), not world-readable /tmp.
    readonly property string dir: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/anoshell/screenshots`
    readonly property string _mk: 'mkdir -p -m 700 -- "$DIR" && chmod 700 -- "$DIR" && umask 077 && ' 
    property bool busy: false
    property string lastFile: ""
    property string _mode: ""
    property string _out: ""
    property int countdown: 0          // seconds left of a delayed capture (0 = none)
    // A beat before the shot: the countdown pill and any open card leave the
    // screen first (they were in the picture).
    property bool preparing: false

    signal captured(string path, string mode)
    signal failed(string mode, string reason)

    function capture(mode: string, delaySec: int): void {
        if (root.busy || root.preparing || root.countdown > 0 || !["region", "window", "screen"].includes(mode)) return
        root._mode = mode
        if (delaySec > 0) { root.countdown = Math.min(60, delaySec); delayTick.start() }
        else root._prepare()
    }
    function cancel(): void {
        delayTick.stop(); root.countdown = 0
        if (waitFile.running) { waitFile.stop(); root._finish(1) }
    }

    Timer {
        id: delayTick
        interval: 1000; repeat: true
        onTriggered: { if (--root.countdown <= 0) { stop(); root._prepare() } }
    }
    function _prepare() { root.preparing = true; prepareTimer.restart() }
    Timer { id: prepareTimer; interval: 200; onTriggered: { root.preparing = false; root._run() } }

    function _run() {
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH.mm.ss.zzz")
        root._out = `${root.dir}/Screenshot_${stamp}.png`
        root.busy = true
        if (CompositorService.isNiri) {
            const act = root._mode === "region" ? "screenshot" : root._mode === "window" ? "screenshot-window" : "screenshot-screen"
            shot.exec({ command: ["bash", "-c", root._mk + 'niri msg action "$ACT" --path "$OUT"'],
                environment: ({ DIR: root.dir, ACT: act, OUT: root._out }) })
        } else if (root._mode === "window") {
            if (CompositorService.compositor !== "hyprland") { root._finish(1); return } // the focused window comes from hyprctl
            winQuery.running = true // geometry first, then grim
        } else if (root._mode === "region") {
            shot.exec({ command: ["bash", "-c", root._mk + 'g=$(slurp) && grim -g "$g" "$OUT"'],
                environment: ({ DIR: root.dir, OUT: root._out }) })
        } else {
            const output = CompositorService.focusedMonitorName
            shot.exec({ command: ["bash", "-c", root._mk + 'if [ -n "$MON" ]; then grim -o "$MON" "$OUT"; else grim "$OUT"; fi'],
                environment: ({ DIR: root.dir, OUT: root._out, MON: output }) })
        }
    }

    // Hyprland's focused window, in layout coordinates (what grim -g takes).
    Process {
        id: winQuery
        command: ["hyprctl", "activewindow", "-j"]
        onExited: code => { if (code !== 0) root._finish(code) } // never left busy
        stdout: StdioCollector {
            onStreamFinished: {
                let g = ""
                try {
                    const w = JSON.parse(text)
                    if (w?.at && w?.size) g = `${Math.round(w.at[0])},${Math.round(w.at[1])} ${Math.round(w.size[0])}x${Math.round(w.size[1])}`
                } catch (e) {}
                if (!g) { root._finish(1); return }
                shot.exec({ command: ["bash", "-c", root._mk + 'grim -g "$G" "$OUT"'],
                    environment: ({ DIR: root.dir, OUT: root._out, G: g }) })
            }
        }
    }

    Process {
        id: shot
        onExited: code => {
            // niri writes the file when its UI is confirmed (the region) or a
            // moment later: wait for it rather than assume.
            if (CompositorService.isNiri && code === 0) { waitFile.tries = 0; waitFile.start() }
            else root._finish(code)
        }
    }
    Timer {
        id: waitFile
        property int tries: 0
        interval: 250; repeat: true
        // The region (niri's own UI) waits for you up to 2 min, the others 5 s;
        // cancel() stops waiting.
        onTriggered: { if (++tries > (root._mode === "region" ? 480 : 20)) { stop(); root._finish(1) } else if (!exists.running) exists.running = true }
    }
    Process {
        id: exists
        command: ["test", "-s", root._out]
        onExited: code => { if (code === 0) { waitFile.stop(); root._finish(0) } }
    }

    function _finish(code) {
        root.busy = false
        if (code === 0) { root.lastFile = root._out; root.captured(root._out, root._mode) }
        else root.failed(root._mode, root._mode === "region" ? "cancelled" : "capture failed")
    }

    // Temp shots older than a day go (saved ones were moved out already).
    Component.onCompleted: Quickshell.execDetached(["find", root.dir, "-maxdepth", "1", "-name", "Screenshot_*.png", "-mmin", "+1440", "-delete"])

    IpcHandler {
        target: "screenshot"
        function region(): void { root.capture("region", 0) }
        function window(): void { root.capture("window", 0) }
        function screen(): void { root.capture("screen", 0) }
        function delayed(mode: string, seconds: int): void { root.capture(mode, seconds) }
        function cancel(): void { root.cancel() }
        function last(): string { return root.lastFile }
    }
}
