pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.services

/**
 * Screenshots: region, window or screen, now or after a delay, written to a
 * temp file (the preview card copies, saves or edits it from there).
 *
 *   Hyprland (and other wlroots-likes): slurp + grim; the window's geometry
 *     comes from the compositor backend (Hyprland, sway, mango; not on the
 *     generic and labwc backends).
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
        root._cancelled = false
        if (delaySec > 0) { root.countdown = Math.min(60, delaySec); delayTick.start() }
        else root._prepare()
    }
    function cancel(): void {
        delayTick.stop(); root.countdown = 0
        if (waitFile.running) { waitFile.stop(); root._finish(1) }
        else if (freezeGrab.running) root._cancelled = true // finishes when the grab ends
        else if (regionPick.running) regionPick.signal(15) // the region selection (onExited finishes it)
        else if (freezeSettle.running) { freezeSettle.stop(); root._finish(1) }
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
            // Geometry first (the backend's focused window), then grim. A
            // request the backend drops (socket gone, bad reply) never calls
            // back: the guard finishes it so the service isn't left busy.
            geometryGuard.restart()
            const asked = CompositorService.focusedWindowGeometry(w => {
                if (!geometryGuard.running) return // already given up
                geometryGuard.stop()
                if (!w || !(w.width > 0) || !(w.height > 0)) { root._finish(1); return }
                const g = `${Math.round(w.x)},${Math.round(w.y)} ${Math.round(w.width)}x${Math.round(w.height)}`
                shot.exec({ command: ["bash", "-c", root._mk + 'grim -g "$G" "$OUT"'],
                    environment: ({ DIR: root.dir, OUT: root._out, G: g }) })
            })
            if (!asked) { geometryGuard.stop(); root._finish(1) } // this backend can't say which window is focused
        } else if (root._mode === "region") {
            // slurp alone first (cancel signals it directly), then grim.
            // screenshot.freezeRegion: each screen is captured first and shown
            // still while you pick, so the shot is that moment (grim then
            // captures the still picture).
            if (root.freezeRegion) { freezeGrab.exec({ command: ["bash", "-c", root._mk + 'for o in "$@"; do grim -o "$o" "$DIR/.freeze-$o.png" || exit 1; done', "bash", ...Quickshell.screens.map(x => x.name)],
                environment: ({ DIR: root.dir }) }); return }
            regionPick.running = true
        } else {
            const output = CompositorService.focusedMonitorName
            shot.exec({ command: ["bash", "-c", root._mk + 'if [ -n "$MON" ]; then grim -o "$MON" "$OUT"; else grim "$OUT"; fi'],
                environment: ({ DIR: root.dir, OUT: root._out, MON: output }) })
        }
    }

    Timer { id: geometryGuard; interval: 3000; onTriggered: root._finish(1) }

    readonly property bool freezeRegion: Config.options?.screenshot?.freezeRegion ?? false
    property bool frozen: false
    Process {
        id: freezeGrab
        onExited: code => {
            if (code !== 0 || root._cancelled) { root._finish(1); return }
            root.frozen = true
            freezeSettle.restart()
        }
    }
    // The still picture is up (layer animations included) before slurp starts.
    Timer { id: freezeSettle; interval: 350; onTriggered: regionPick.running = true }
    property bool _cancelled: false
    // After every freeze capture (also one whose grab failed half way).
    function _unfreeze() {
        if (!root.freezeRegion || root._mode !== "region") return
        root.frozen = false
        Quickshell.execDetached(["sh", "-c", 'rm -f -- "$1"/.freeze-*.png', "sh", root.dir])
    }
    Variants {
        model: root.frozen ? Quickshell.screens : []
        PanelWindow {
            required property var modelData
            screen: modelData
            color: "black"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:freeze"
            mask: Region { item: null } // slurp takes the pointer
            Image {
                anchors.fill: parent
                source: `file://${root.dir}/.freeze-${modelData.name}.png`
                cache: false
                smooth: false
            }
        }
    }

    Process {
        id: regionPick
        // slurp reads predefined boxes from a non-terminal stdin: give it none,
        // or it waits on the pipe and never shows its selection overlay.
        // It prints the region on success and nothing when cancelled.
        command: ["sh", "-c", "exec slurp < /dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const g = text.trim()
                if (!/^-?\d+,-?\d+ \d+x\d+$/.test(g)) { root._finish(1); return }
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
        root._unfreeze()
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
