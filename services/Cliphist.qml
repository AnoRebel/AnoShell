pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Clipboard history service using cliphist. Supports fuzzy search,
 * paste, superpaste, and image detection.
 */
Singleton {
    id: root
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property list<string> entries: []

    /**
     * Pause the auto-refresh that's triggered when the wl-clipboard
     * contents change. Set this true around an operation that briefly
     * hijacks the clipboard (e.g. a screenshot script that copies a PNG
     * into the clipboard, then restores the previous payload). When
     * cleared, callers should also invoke refresh() to bring the entry
     * list back in sync with whatever cliphist saw during the suppression
     * window.
     *
     * Compositor-agnostic — the underlying wl-clipboard protocol is the
     * same on Hyprland and Niri.
     */
    property bool suppressRefresh: false

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    // ── Media previews ────────────────────────────────────────────────
    // What an entry is: an image (binary data), copied files (file:// URIs,
    // e.g. from a file manager), a colour value, or text.
    readonly property var imageExts: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "avif", "tif", "tiff", "ico"]
    readonly property var videoExts: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "ogv"]
    readonly property var audioExts: ["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac", "wma"]
    function fileKind(path) {
        const ext = (path.match(/\.([A-Za-z0-9]+)$/) ?? [])[1]?.toLowerCase() ?? ""
        return root.imageExts.includes(ext) ? "image" : root.videoExts.includes(ext) ? "video"
            : root.audioExts.includes(ext) ? "audio" : ext === "pdf" ? "pdf" : "file"
    }
    function entryInfo(entry) {
        const id = root._id(entry)
        const listed = String(entry ?? "").split("\t").slice(1).join("\t")
        // `cliphist list` cuts entries at ~100 characters: file lists are read in full.
        const full = root.fullTexts[id]
        const text = full !== undefined && full !== "!" ? full : listed
        // A cut-off file list: the row asks for the whole text (requestText) first.
        if (full === undefined && listed.startsWith("file://") && listed.endsWith("…"))
            return { id: id, kind: "text", text: listed, needsText: true }
        const bin = text.match(/^\[\[ binary data (.+?) (\w+) (\d+)x(\d+) \]\]$/)
        if (bin) return { id: id, kind: "image", ext: bin[2].toLowerCase(), size: bin[1], width: +bin[3], height: +bin[4], text: text }
        const uris = text.match(/file:\/\/[^\s…]+(?=\s|$)/g)
        if (uris && text.replace(/file:\/\/[^\s]+/g, "").trim().replace(/^…$/, "") === "") {
            const files = uris.map(u => { let path; try { path = decodeURIComponent(u.slice(7)) } catch (e) { path = u.slice(7) } return { path: path, name: path.split("/").pop(), kind: root.fileKind(path) } })
            return { id: id, kind: "files", files: files, text: text }
        }
        const t = text.trim()
        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t))
            return { id: id, kind: "color", color: t, text: text }
        return { id: id, kind: "text", text: text }
    }

    // Previews are made once, two at a time, as rows come into view:
    // images decoded from cliphist, a frame from videos (ffmpeg). key → file.
    property var previews: ({})
    property var fullTexts: ({})          // id → the whole text of a file-list entry
    property var _jobs: []
    property var _queued: ({})
    function preview(key) { return root.previews[key] ?? "" }
    function requestImage(id, ext) {
        if (!id) return
        const key = "img:" + id
        if (root.previews[key] || root._queued[key]) return
        const out = `${Directories.cliphistDecode}/${id}.${ext || "png"}`
        root._queue(key, { command: ["bash", "-c", 'mkdir -p "${OUT%/*}" && printf "%s" "$ID" | "$BIN" decode > "$OUT.part" && mv -f "$OUT.part" "$OUT"'],
            environment: ({ ID: id, OUT: out, BIN: root.cliphistBinary }) }, out)
    }
    function requestVideoFrame(path) {
        const key = "vid:" + path
        if (root.previews[key] || root._queued[key]) return
        const out = `${Directories.cliphistDecode}/v-${Qt.md5(path)}.jpg`
        root._queue(key, { command: ["bash", "-c", 'mkdir -p "${OUT%/*}" && ffmpeg -nostdin -loglevel error -y -ss 1 -i "$IN" -frames:v 1 -vf "scale=360:-2" "$OUT.part.jpg" && mv -f "$OUT.part.jpg" "$OUT"'],
            environment: ({ IN: path, OUT: out }) }, out)
    }
    function requestText(id) {
        const key = "txt:" + id
        if (!id || root.fullTexts[id] !== undefined || root._queued[key]) return
        root._queue(key, { command: ["bash", "-c", 'printf "%s" "$ID" | "$BIN" decode | head -c 65536'], environment: ({ ID: id, BIN: root.cliphistBinary }) }, "", true)
    }
    function _queue(key, job, out, text) {
        const q = Object.assign({}, root._queued); q[key] = true; root._queued = q
        root._jobs = root._jobs.concat([{ key: key, job: job, out: out, text: !!text }])
        root._pump()
    }
    // The preview directory is cleared once per shell start, before any job.
    property bool _ready: false
    Process {
        running: true
        command: ["bash", "-c", 'rm -rf -- "$DIR" && mkdir -p -- "$DIR"']
        environment: ({ DIR: Directories.cliphistDecode })
        onExited: { root._ready = true; root._pump() }
    }
    function _pump() {
        if (!root._ready) return
        for (const w of [worker1, worker2]) {
            if (w.key !== "" || root._jobs.length === 0) continue
            const j = root._jobs[0]
            root._jobs = root._jobs.slice(1)
            w.key = j.key; w.out = j.out; w.text = j.text
            w.exitCode = -1; w.streamDone = false; w.result = ""
            w.exec(j.job)
        }
    }
    // A job is done once its process has exited AND its output is read (either
    // can come first); only then is the worker given the next one.
    function _settle(w) {
        if (w.key !== "" && w.exitCode >= 0 && w.streamDone) root._finished(w, w.exitCode, w.result)
    }
    function _finished(w, code, output) {
        // "!" = no preview (missing file, not a video…).
        if (w.text) {
            const t = Object.assign({}, root.fullTexts)
            t[w.key.slice(4)] = code !== 0 ? "!" : output.replace(/\r/g, "")
            root.fullTexts = t
        } else {
            const p = Object.assign({}, root.previews)
            p[w.key] = code !== 0 ? "!" : w.out
            root.previews = p
        }
        w.key = ""
        root._pump()
    }
    Process {
        id: worker1
        property string key: ""; property string out: ""; property bool text: false
        property int exitCode: -1; property bool streamDone: false; property string result: ""
        stdout: StdioCollector { onStreamFinished: { worker1.result = text; worker1.streamDone = true; root._settle(worker1) } }
        onExited: code => { worker1.exitCode = code; root._settle(worker1) }
    }
    Process {
        id: worker2
        property string key: ""; property string out: ""; property bool text: false
        property int exitCode: -1; property bool streamDone: false; property string result: ""
        stdout: StdioCollector { onStreamFinished: { worker2.result = text; worker2.streamDone = true; root._settle(worker2) } }
        onExited: code => { worker2.exitCode = code; root._settle(worker2) }
    }

    function refresh() {
        if (root.suppressRefresh) return
        readProc.buffer = []
        readProc.running = true
    }

    // cliphist ids are numbers; anything else is rejected rather than run.
    function _id(entry) {
        const id = String(entry ?? "").split("\t")[0].trim()
        return /^[0-9]+$/.test(id) ? id : ""
    }

    function copy(entry) {
        const id = root._id(entry); if (!id) return
        Quickshell.execDetached({ command: ["bash", "-c", `printf '%s' "$ID" | ${root.cliphistBinary} decode | wl-copy`], environment: ({ ID: id }) })
    }

    function paste(entry) {
        const id = root._id(entry); if (!id) return
        Quickshell.execDetached({ command: ["bash", "-c", `printf '%s' "$ID" | ${root.cliphistBinary} decode | wl-copy; ${root.pressPasteCommand}`], environment: ({ ID: id }) })
    }

    function superpaste(count, isImage = false) {
        const targetEntries = entries.filter(entry => !isImage || entryIsImage(entry)).slice(0, count)
        const pasteCommands = [...targetEntries].reverse().map(entry => {
            const id = root._id(entry) || "0" // ids are validated digits
            return `printf '%s' ${id} | ${root.cliphistBinary} decode | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`
        })
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)])
    }

    Process {
        id: deleteProc
        function deleteEntry(e) {
            const id = root._id(e); if (!id) return
            deleteProc.exec({ command: ["bash", "-c", `printf '%s' "$ID" | ${root.cliphistBinary} delete`], environment: ({ ID: id }) })
        }
        onExited: root.refresh()
    }

    function deleteEntry(entry) { deleteProc.deleteEntry(entry) }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: root.refresh()
    }

    function wipe() { wipeProc.running = true }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            if (root.suppressRefresh) return
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: readProc
        property list<string> buffer: []
        command: [root.cliphistBinary, "list"]
        stdout: SplitParser {
            onRead: line => { readProc.buffer.push(line) }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readProc.buffer
                root._prune()
            } else console.error("[Cliphist] Failed to refresh with code", exitCode)
        }
    }

    // Decoded images whose entries are gone are deleted (file previews stay
    // until the shell restarts; the directory is cleared then).
    function _prune() {
        const live = new Set(root.entries.map(e => root._id(e)))
        const p = {}, gone = []
        for (const k in root.previews) {
            if (k.startsWith("img:") && !live.has(k.slice(4))) { if (root.previews[k] !== "!") gone.push(root.previews[k]) }
            else p[k] = root.previews[k]
        }
        if (gone.length === 0) return
        root.previews = p
        const q = Object.assign({}, root._queued)
        for (const k in q) if (k.startsWith("img:") && !live.has(k.slice(4))) delete q[k]
        root._queued = q
        Quickshell.execDetached(["rm", "-f", "--"].concat(gone))
    }

    IpcHandler {
        target: "cliphistService"
        function update(): void { root.refresh() }
    }
}
