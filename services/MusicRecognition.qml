pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * "What's playing?" (musicRecognition.enable, off by default). One bounded
 * run: record musicRecognition.seconds of the default output (or the
 * microphone) with pw-record into a private runtime file, ask songrec
 * (`audio-file-to-recognized-song`, Shazam's unofficial service), delete the
 * file. The answer comes as a notification with Copy and Search actions.
 * Idea from Ryoku's SongRec service (which re-encoded a growing recording on
 * every pass and wrote to a shared /tmp path).
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.musicRecognition?.enable ?? false
    readonly property int seconds: Math.max(4, Math.min(20, Config.options?.musicRecognition?.seconds ?? 8))
    readonly property string source: Config.options?.musicRecognition?.source ?? "output" // output | mic
    property bool listening: false
    property string title: ""
    property string artist: ""
    property string url: ""

    function recognize() {
        if (!root.enabled || runner.running) return
        root.listening = true
        runner.running = true
    }

    Process {
        id: runner
        // Fixed script; $1 = seconds, $2 = "output" | "mic".
        command: ["sh", "-c", 'd="${XDG_RUNTIME_DIR:-/tmp}/anoshell"; mkdir -p "$d" && chmod 700 "$d" || exit 3; '
            + 'f="$d/songrec.wav"; rm -f "$f"; '
            + 'if [ "$2" = output ]; then timeout -s INT "$1" pw-record -P "{ stream.capture.sink = true }" "$f"; '
            + 'else timeout -s INT "$1" pw-record "$f"; fi; '
            + '[ -s "$f" ] || exit 4; songrec audio-file-to-recognized-song "$f"; r=$?; rm -f "$f"; exit $r',
            "sh", String(root.seconds), root.source]
        stdout: StdioCollector {
            onStreamFinished: {
                root.listening = false
                let data = null
                try { data = JSON.parse(this.text || "") } catch (e) {}
                const t = data?.track
                if (!t) {
                    root.title = ""; root.artist = ""; root.url = ""
                    notifier.exec(["notify-send", "-a", "AnoShell", "-i", "audio-x-generic", "Not recognised",
                        data ? "Shazam found no match: try again closer to the chorus." : "songrec gave no answer (is it installed, and is the network up?)"])
                    return
                }
                root.title = t.title ?? ""
                root.artist = t.subtitle ?? ""
                root.url = t.url ?? ""
                notifier.shown = { title: root.title, artist: root.artist, url: root.url }
                notifier.exec(["timeout", "900", "notify-send", "-a", "AnoShell", "-i", "audio-x-generic", "--wait",
                    "-A", "copy=Copy", "-A", "search=Search", "--", root.title, root.artist])
            }
        }
    }
    // notify-send --wait prints the chosen action.
    Process {
        id: notifier
        property var shown: ({})    // the song this notification is about
        stdout: StdioCollector {
            onStreamFinished: {
                const a = (this.text || "").trim(), s = notifier.shown
                if (a === "copy") Quickshell.execDetached(["wl-copy", "--", `${s.artist} - ${s.title}`])
                else if (a === "search") {
                    const u = /^https:\/\//.test(s.url ?? "") ? s.url
                        : "https://www.youtube.com/results?search_query=" + encodeURIComponent(`${s.artist} ${s.title}`)
                    DefaultApps.launch(["xdg-open", u])
                }
            }
        }
    }

    IpcHandler {
        target: "musicRecognition"
        function recognize(): void { root.recognize() }
        function status(): string { return JSON.stringify({ enabled: root.enabled, listening: root.listening, title: root.title, artist: root.artist }) }
    }
}
