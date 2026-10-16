pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.modules.common

/**
 * Screen recording: starts and stops recordings with the recorder you pick
 * (recording.backend: auto | wf-recorder | wl-screenrec | gpu-screen-recorder),
 * using only what's installed. `installed` lists the ones found; with none,
 * Settings shows what to install (`suggestions`).
 *
 *   RecorderStatus.toggle("region")   // slurp a region, then record it
 *   RecorderStatus.toggle("screen")   // the focused output
 *
 * State comes from our own recorder process (no polling).
 * IPC: qs -c ano ipc call recorder toggle|region|screen|stop
 */
Singleton {
    id: root

    readonly property var known: ["gpu-screen-recorder", "wl-screenrec", "wf-recorder"]
    readonly property var suggestions: [
        { name: "gpu-screen-recorder", why: "fastest, hardware encoding on Intel, AMD and NVIDIA" },
        { name: "wl-screenrec", why: "hardware encoding, wlroots compositors (Hyprland)" },
        { name: "wf-recorder", why: "simple and widely packaged" }
    ]
    property var installed: []
    readonly property string configured: Config.options?.recording?.backend ?? "auto"
    // The configured backend if it's installed, else the first installed one.
    readonly property string backend: installed.includes(configured) ? configured : (installed[0] ?? "")
    readonly property bool available: backend !== ""
    readonly property string dir: (Config.options?.recording?.dir ?? "") || `${Quickshell.env("HOME")}/Videos`
    readonly property bool audio: Config.options?.recording?.audio ?? false

    property bool isRecording: recorder.running
    property string lastFile: ""
    property real recordingStartTime: 0
    property int elapsedSeconds: 0

    onIsRecordingChanged: {
        if (isRecording) { recordingStartTime = Date.now(); elapsedSeconds = 0; elapsedTimer.start() }
        else { recordingStartTime = 0; elapsedSeconds = 0; elapsedTimer.stop() }
    }
    Timer {
        id: elapsedTimer
        interval: 1000
        repeat: true
        onTriggered: if (root.recordingStartTime > 0) root.elapsedSeconds = Math.floor((Date.now() - root.recordingStartTime) / 1000)
    }

    function refreshInstalled() { detect.running = true }
    Component.onCompleted: refreshInstalled()
    Process {
        id: detect
        command: ["sh", "-c", 'for b in "$@"; do command -v "$b" >/dev/null 2>&1 && echo "$b"; done', "sh", ...root.known]
        stdout: StdioCollector { onStreamFinished: root.installed = text.split("\n").filter(s => s.length > 0) }
    }

    function _file() {
        const d = new Date(), p = n => String(n).padStart(2, "0")
        return `${root.dir}/Recording_${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}_${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}.mp4`
    }

    // Builds the recorder command; `geom` is slurp's "x,y WxH" or "" for the
    // focused output.
    function _command(geom, file) {
        const out = CompositorService.focusedMonitorName
        switch (root.backend) {
        case "gpu-screen-recorder": {
            const a = ["gpu-screen-recorder", "-f", "60", "-o", file]
            if (geom) {
                const m = geom.match(/(-?\d+),(-?\d+) (\d+)x(\d+)/)
                a.push("-w", "region", "-region", `${m[3]}x${m[4]}+${m[1]}+${m[2]}`)
            } else a.push("-w", out || "screen")
            if (root.audio) a.push("-a", "default_output")
            return a
        }
        case "wl-screenrec": {
            const a = ["wl-screenrec", "-f", file]
            if (geom) a.push("-g", geom); else if (out) a.push("-o", out)
            if (root.audio) a.push("--audio")
            return a
        }
        default: {
            const a = ["wf-recorder", "-f", file]
            if (geom) a.push("-g", geom); else if (out) a.push("-o", out)
            if (root.audio) a.push("--audio")
            return a
        }
        }
    }

    function start(mode) {
        if (root.isRecording || !root.available) return
        if (mode === "region") { slurp.running = true; return }
        root._begin("")
    }
    function _begin(geom) {
        root.lastFile = root._file()
        mkdir.exec(["mkdir", "-p", root.dir])
        recorder.command = root._command(geom, root.lastFile)
        recorder.running = true
    }
    function stop() { if (recorder.running) recorder.signal(2) }  // SIGINT: finalise the file
    function toggle(mode) { if (root.isRecording) root.stop(); else root.start(mode ?? "region") }

    Process { id: mkdir }
    Process {
        id: slurp
        command: ["slurp"]
        stdout: StdioCollector { onStreamFinished: { const g = text.trim(); if (g.length > 0) root._begin(g) } }
    }
    Process {
        id: recorder
        onExited: (code, status) => {
            if (root.lastFile)
                Quickshell.execDetached(["notify-send", "-a", "Ano Shell", "-i", "video-x-generic",
                    code === 0 || code === 130 || code === 2 ? "Recording saved" : "Recording failed", root.lastFile])
        }
    }

    // Keybinds (bundled hyprland.lua: Super+Shift+R region, Super+Shift+Alt+R screen).
    Loader {
        active: CompositorService.compositor === "hyprland"
        sourceComponent: Item {
            GlobalShortcut { name: "regionRecord"; description: "Record a region (again to stop)"; onPressed: root.toggle("region") }
            GlobalShortcut { name: "screenRecord"; description: "Record the screen (again to stop)"; onPressed: root.toggle("screen") }
        }
    }

    IpcHandler {
        target: "recorder"
        function toggle(): void { root.toggle("region") }
        function region(): void { root.start("region") }
        function screen(): void { root.start("screen") }
        function stop(): void { root.stop() }
        function status(): string { return JSON.stringify({ recording: root.isRecording, backend: root.backend, installed: root.installed, file: root.lastFile }) }
    }
}
