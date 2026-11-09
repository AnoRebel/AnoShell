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
    // What audio goes in: none | system (what you hear) | mic | both.
    // recording.audio (older bool) means "system" when audioSource is unset.
    readonly property string audioSource: root._audioOnce ? "system"
        : (["none", "system", "mic", "both"].includes(Config.options?.recording?.audioSource) ? Config.options.recording.audioSource
        : ((Config.options?.recording?.audio ?? false) ? "system" : "none"))
    readonly property bool audio: root.audioSource !== "none"
    property bool _audioOnce: false   // one recording with audio (record.sh --sound)
    // Frames per second (0: the recorder's default).
    readonly property int fps: Math.max(0, Math.min(240, Config.options?.recording?.fps ?? 60))

    property bool isRecording: recorder.running
    property string lastFile: ""
    // A recording finished and kept (not discarded, not failed).
    signal saved(string path)
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
    // A mix left loaded by a shell that crashed or reloaded mid-recording
    // (only modules naming our sink are touched).
    Component.onCompleted: {
        refreshInstalled()
        Quickshell.execDetached(["sh", "-c", 'command -v pactl >/dev/null || exit 0; pactl list short modules | awk \'/anoshell_rec_mix/ {print $1}\' | while read -r id; do pactl unload-module "$id"; done'])
    }
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
    // The PulseAudio-style device a one-device recorder records from;
    // "both" uses our temporary mix (see mixer below).
    function _pulseDevice() {
        return root.audioSource === "mic" ? "@DEFAULT_SOURCE@" : root.audioSource === "both" ? "anoshell_rec_mix.monitor" : "@DEFAULT_MONITOR@"
    }
    function _command(geom, file) {
        const out = CompositorService.focusedMonitorName
        switch (root.backend) {
        case "gpu-screen-recorder": {
            const a = ["gpu-screen-recorder", "-f", String(root.fps || 60), "-o", file]
            if (geom) {
                const m = geom.match(/(-?\d+),(-?\d+) (\d+)x(\d+)/)
                a.push("-w", "region", "-region", `${m[3]}x${m[4]}+${m[1]}+${m[2]}`)
            } else a.push("-w", out || "screen")
            // gpu-screen-recorder mixes "a|b" into one track itself.
            if (root.audio) a.push("-a", { system: "default_output", mic: "default_input", both: "default_output|default_input" }[root.audioSource])
            return a
        }
        case "wl-screenrec": {
            const a = ["wl-screenrec", "-f", file]
            if (geom) a.push("-g", geom); else if (out) a.push("-o", out)
            if (root.fps > 0) a.push("--max-fps", String(root.fps))
            if (root.audio) a.push("--audio", "--audio-device", root._pulseDevice())
            return a
        }
        default: {
            const a = ["wf-recorder", "-f", file]
            if (geom) a.push("-g", geom); else if (out) a.push("-o", out)
            if (root.fps > 0) a.push("-r", String(root.fps))
            if (root.audio) a.push(`--audio=${root._pulseDevice()}`)
            return a
        }
        }
    }

    // Busy picking a region or mixing audio counts as starting: a second
    // start then would record under the wrong file name.
    readonly property bool _starting: slurp.running || mixer.running
    function start(mode) {
        if (root.isRecording || root._starting || !root.available) return
        if (mode === "region") { slurp.running = true; return }
        root._begin("")
    }
    function _begin(geom) {
        if (recorder.running) return
        // "both" with a one-device recorder: mix system + mic into a temporary
        // null sink first (only these modules are ours; they go when it ends).
        if (root.audioSource === "both" && root.backend !== "gpu-screen-recorder" && !root._mixModules.length) {
            mixer.geom = geom
            mixer.running = true
            return
        }
        root.lastFile = root._file()
        // mkdir first, then the recorder (a missing folder failed the first one).
        recorder.command = ["sh", "-c", 'mkdir -p "$1" && shift && exec "$@"', "sh", root.dir, ...root._command(geom, root.lastFile)]
        recorder.running = true
        root._audioOnce = false
    }
    function stop() { if (recorder.running) { recorder.signal(2); stopEscalation.step = 0; stopEscalation.restart() } }  // SIGINT: finalise the file
    // Stop and throw the recording away (to the trash, not deleted).
    property bool _discard: false
    function discard() { if (recorder.running) { root._discard = true; recorder.signal(2); stopEscalation.step = 0; stopEscalation.restart() } }
    // A recorder that ignores SIGINT (stuck encoder, lost device) gets TERM
    // after 5 s, then KILL, so "recording" never sticks.
    Timer {
        id: stopEscalation
        property int step: 0
        interval: 5000
        onTriggered: {
            if (!recorder.running) return
            recorder.signal(step === 0 ? 15 : 9)
            if (step++ === 0) restart()
        }
    }
    function toggle(mode) { if (root.isRecording) root.stop(); else root.start(mode ?? "region") }

    Process {
        id: slurp
        // slurp reads predefined boxes from a non-terminal stdin: give it none,
        // or it waits on the pipe and never shows its selection overlay.
        command: ["sh", "-c", "exec slurp < /dev/null"]
        stdout: StdioCollector { onStreamFinished: { const g = text.trim(); if (g.length > 0) root._begin(g) } }
    }
    property var _mixModules: []
    Process {
        id: mixer
        property string geom: ""
        // The defaults are read before the mix sink exists, so the system
        // loopback can never pick the mix itself.
        command: ["sh", "-c", 'set -e; s=$(pactl get-default-sink); src=$(pactl get-default-source); '
            + 'm=$(pactl load-module module-null-sink sink_name=anoshell_rec_mix sink_properties=device.description=AnoShell-recording-mix); '
            + 'a=$(pactl load-module module-loopback source="$s.monitor" sink=anoshell_rec_mix latency_msec=40) || { pactl unload-module "$m"; exit 1; }; '
            + 'b=$(pactl load-module module-loopback source="$src" sink=anoshell_rec_mix latency_msec=40) || { pactl unload-module "$a"; pactl unload-module "$m"; exit 1; }; '
            + 'echo "$m $a $b"']
        stdout: StdioCollector {
            onStreamFinished: {
                const ids = text.trim().split(/\s+/).filter(x => /^\d+$/.test(x))
                if (ids.length !== 3) {
                    Quickshell.execDetached(["notify-send", "-a", "AnoShell", "-i", "video-x-generic", "Recording not started", "Couldn't mix system audio and the microphone (pactl)."])
                    return
                }
                root._mixModules = ids
                root._begin(mixer.geom)
            }
        }
    }
    function _unloadMix() {
        for (const id of root._mixModules) Quickshell.execDetached(["pactl", "unload-module", id])
        root._mixModules = []
    }
    Process {
        id: recorder
        onExited: (code, status) => {
            root._unloadMix()
            const file = root.lastFile
            if (!file) return
            if (root._discard) {
                root._discard = false
                Quickshell.execDetached(["sh", "-c", 'gio trash -- "$1" || notify-send -a AnoShell -i video-x-generic "Couldn\'t move the recording to the trash" "$1"', "sh", file])
                return
            }
            if (code === 0 || code === 130 || code === 2) {
                Quickshell.execDetached(["sh", "-c", root._finishedScript, "sh", file])
                root.saved(file)
            } else Quickshell.execDetached(["notify-send", "-a", "AnoShell", "-i", "video-x-generic", "Recording failed", file])
        }
    }
    // The finished recording: a first-frame thumbnail in the notification,
    // with Open / Show in folder / Delete (to the trash). Fixed script; the
    // file path is an argument.
    readonly property string _finishedScript: 'f="$1"; [ -s "$f" ] || { notify-send -a AnoShell -i video-x-generic "Recording failed" "The file is empty: $f"; exit 0; }; '
            + 't="${XDG_RUNTIME_DIR:-/tmp}/anoshell/rec-thumb.png"; mkdir -p "${t%/*}"; '
            + 'ffmpeg -loglevel error -y -ss 0.3 -i "$f" -frames:v 1 -vf scale=480:-1 "$t" 2>/dev/null || t=video-x-generic; '
            + 'a=$(timeout 900 notify-send -a AnoShell -i "$t" --wait -A open=Open -A folder="Show in folder" -A delete=Delete -- "Recording saved" "$f"); '
            + 'case "$a" in open) xdg-open "$f";; folder) xdg-open "${f%/*}";; delete) gio trash -- "$f" || notify-send -a AnoShell "Couldn\'t move the recording to the trash" "$f";; esac'

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
        // Screen recording on/off (the full-screen keybind); with audio: "audio".
        function toggleScreen(opts: string): void { if (root.isRecording) root.stop(); else { root._audioOnce = opts === "audio"; root.start("screen") } }
        function stop(): void { root.stop() }
        function discard(): void { root.discard() }
        function status(): string { return JSON.stringify({ recording: root.isRecording, backend: root.backend, installed: root.installed, file: root.lastFile }) }
    }
}
