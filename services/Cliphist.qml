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
    property string error: "" // why the last refresh failed ("" when fine)
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
        // Only file lists read fullTexts, so other rows don't re-evaluate when it changes.
        const full = listed.startsWith("file://") ? root.fullTexts[id] : undefined
        const text = full !== undefined && full !== "!" ? full : listed
        // A cut-off file list: the row asks for the whole text (requestText) first.
        if (full === undefined && listed.startsWith("file://") && listed.endsWith("…"))
            return { id: id, kind: "text", text: listed, needsText: true }
        const bin = text.match(/^\[\[ binary data (.+?) (\w+) (\d+)x(\d+) \]\]$/)
        if (bin) return { id: id, kind: "image", ext: bin[2].toLowerCase(), size: bin[1], width: +bin[3], height: +bin[4], text: text }
        const uris = text.match(/file:\/\/[^\s…]+(?=\s|$)/g)
        if (uris && text.replace(/file:\/\/[^\s]+/g, "").trim().replace(/^…$/, "") === "") {
            // uri: for Image and Open (stays encoded: "#", "?" in names); path: for ffmpeg and display.
            const files = uris.map(u => { let path; try { path = decodeURIComponent(u.slice(7)) } catch (e) { path = u.slice(7) } return { uri: u, path: path, name: path.split("/").pop(), kind: root.fileKind(path) } })
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
        // An entry deleted (or the history wiped) meanwhile: ids get reused, so drop it.
        const id = w.key.startsWith("img:") || w.key.startsWith("txt:") ? w.key.slice(4) : ""
        if (id && !root.entries.some(e => root._id(e) === id)) {
            const q = Object.assign({}, root._queued); delete q[w.key]; root._queued = q
            if (!w.text && code === 0) Quickshell.execDetached(["rm", "-f", "--", w.out])
            w.key = ""
            root._pump()
            return
        }
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

    // Deleting hides the entry at once; cliphist deletes it only once its
    // Undo is gone (Undo's commit), so Undo brings it back in its place.
    property var _hidden: ({})
    function deleteEntry(entry) {
        const id = root._id(entry); if (!id || root._hidden[id]) return
        root._hidden[id] = true
        root.entries = root.entries.filter(e => root._id(e) !== id)
        const text = String(entry).split("\t").slice(1).join("\t")
        Undo.push({
            label: root.entryIsImage(entry) ? "Deleted an image" : `Deleted “${text.length > 40 ? text.slice(0, 40) + "…" : text}”`,
            restore: () => { delete root._hidden[id]; root.refresh() },
            // cliphist ids only grow, so the id can stay hidden after the delete.
            commit: () => Quickshell.execDetached({ command: ["bash", "-c", `printf '%s' "$ID" | ${root.cliphistBinary} delete`], environment: ({ ID: id }) })
        })
    }

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
        // No database yet (nothing copied since cliphist was set up): cliphist
        // exits 1 with "please store something first". An empty history.
        stderr: StdioCollector { id: readErr }
        onExited: (exitCode, exitStatus) => {
            root.error = ""
            if (exitCode === 0) {
                root.entries = readProc.buffer.filter(e => !root._hidden[root._id(e)])
                root._prune()
            } else if (readErr.text.indexOf("store something first") >= 0) {
                root.entries = []
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, readErr.text.trim())
                root.error = readErr.text.trim() || `cliphist list failed (exit ${exitCode})`
            }
        }
    }

    // Decoded images whose entries are gone are deleted (file previews stay
    // until the shell restarts; the directory is cleared then).
    function _prune() {
        const live = new Set(root.entries.map(e => root._id(e)))
        const isGone = k => (k.startsWith("img:") || k.startsWith("txt:")) && !live.has(k.slice(4))
        const p = {}, gone = []
        for (const k in root.previews) {
            if (!isGone(k)) p[k] = root.previews[k]
            else if (root.previews[k] !== "!") gone.push(root.previews[k])
        }
        const t = {}
        for (const id in root.fullTexts) if (live.has(id)) t[id] = root.fullTexts[id]
        const q = {}
        for (const k in root._queued) if (!isGone(k)) q[k] = root._queued[k]
        root.previews = p
        root.fullTexts = t
        root._queued = q
        root._jobs = root._jobs.filter(j => !isGone(j.key))
        if (gone.length) Quickshell.execDetached(["rm", "-f", "--"].concat(gone))
    }

    // ── Pins: kept in anoshell/clipboard-pins.json (pinned images copied to
    // clipboard-pins/ beside it), so a cliphist wipe doesn't take them.
    // A pin: { key, kind: "text" | "image", text?, file?, ext?, width?, height?,
    //   from? (the entry's id), source? (the picture file it was copied from) }
    readonly property string pinsDir: `${Directories.anoData}/clipboard-pins`
    property var pins: []
    property bool _pinsLoaded: false
    Process { running: true; command: ["mkdir", "-p", "--", root.pinsDir] }
    FileView {
        id: pinsFile
        path: `${Directories.anoData}/clipboard-pins.json`
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.pins = Array.isArray(d) ? d : []
                root._pinsLoaded = true
            } catch (e) { console.warn(`[Cliphist] clipboard-pins.json: ${e}; not saving pins`) }
        }
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) root._pinsLoaded = true }
    }
    function _savePins(list) {
        if (!root._pinsLoaded) return
        root.pins = list
        pinsFile.setText(JSON.stringify(list, null, 1))
    }
    function isPin(item) { return typeof item === "object" && item !== null && !!item.key }
    // A pin seen like an entry (entryInfo's shape).
    function pinInfo(pin) {
        if (pin.kind === "image") return { id: "", kind: "image", ext: pin.ext ?? "png", size: "pinned", width: pin.width ?? 0, height: pin.height ?? 0, file: pin.file, text: "" }
        const info = root.entryInfo("0\t" + (pin.text ?? ""))
        return Object.assign(info, { id: "", needsText: false })
    }
    // Pin an entry: its full content is decoded first (the list is cut short).
    function pin(entry) {
        const id = root._id(entry)
        if (!id || pinProc.running || pinProc.pending) return
        if (!root._pinsLoaded) {
            Quickshell.execDetached(["notify-send", "-a", "AnoShell", "Clipboard", "clipboard-pins.json can't be read, so nothing is pinned (fix or remove the file)"])
            return
        }
        const info = root.entryInfo(entry)
        const key = `${Date.now()}`
        if (info.kind === "image") {
            const file = `${root.pinsDir}/${key}.${info.ext || "png"}`
            pinProc.pending = { key: key, kind: "image", file: file, ext: info.ext, width: info.width, height: info.height, from: id }
            pinProc.exec({ command: ["bash", "-c", 'printf "%s" "$ID" | "$BIN" decode > "$OUT"'], environment: ({ ID: id, BIN: root.cliphistBinary, OUT: file }) })
        } else {
            pinProc.pending = { key: key, kind: "text", from: id }
            pinProc.exec({ command: ["bash", "-c", 'printf "%s" "$ID" | "$BIN" decode | head -c 1048576'], environment: ({ ID: id, BIN: root.cliphistBinary }) })
        }
    }
    // Pin text that isn't in the history (OCR, the scratchpad).
    function pinText(text) {
        if (!text) return
        if (!root._pinsLoaded) {
            Quickshell.execDetached(["notify-send", "-a", "AnoShell", "Clipboard", "clipboard-pins.json can't be read, so nothing is pinned (fix or remove the file)"])
            return
        }
        if (root.pins.some(q => q.kind === "text" && q.text === text)) return
        root._savePins([{ key: `${Date.now()}`, kind: "text", text: text }].concat(root.pins))
    }
    // Pin a picture file (a screenshot on the AnoSpot shelf): copied in, so
    // the temp file going doesn't take it. `source` remembers where from.
    function pinFile(path) {
        if (!path || pinProc.running || pinProc.pending || root.pins.some(q => q.source === path)) return
        if (!root._pinsLoaded) {
            Quickshell.execDetached(["notify-send", "-a", "AnoShell", "Clipboard", "clipboard-pins.json can't be read, so nothing is pinned (fix or remove the file)"])
            return
        }
        const key = `${Date.now()}`
        const ext = ((path.match(/\.([A-Za-z0-9]+)$/) ?? [])[1] ?? "png").toLowerCase()
        const file = `${root.pinsDir}/${key}.${ext}`
        pinProc.pending = { key: key, kind: "image", file: file, ext: ext, source: path }
        pinProc.exec({ command: ["cp", "--", path, file] })
    }
    // A text pin is saved once its output is read, an image pin once the
    // file is written (exit and end of output can come in either order).
    Process {
        id: pinProc
        property var pending: null
        stdout: StdioCollector {
            onStreamFinished: {
                const p = pinProc.pending
                if (!p || p.kind !== "text") return
                pinProc.pending = null
                if (text === "") return
                p.text = text
                if (root.pins.some(q => q.kind === "text" && q.text === text)) return // already pinned
                root._savePins([p].concat(root.pins))
            }
        }
        onExited: code => {
            const p = pinProc.pending
            if (!p || p.kind !== "image") return
            pinProc.pending = null
            if (code === 0) root._savePins([p].concat(root.pins))
        }
    }
    // Undo puts the pin back in its place; its image file goes only once the Undo is gone.
    function unpin(pin) {
        const i = root.pins.findIndex(p => p.key === pin.key)
        if (i < 0) return
        root._savePins(root.pins.filter(p => p.key !== pin.key))
        const t = pin.text ?? ""
        Undo.push({
            label: "Unpinned " + (pin.kind === "image" ? "an image" : `“${t.length > 40 ? t.slice(0, 40) + "…" : t}”`),
            restore: () => {
                if (root.pins.some(p => p.key === pin.key)) return false
                const l = root.pins.slice(); l.splice(Math.min(i, l.length), 0, pin)
                root._savePins(l)
            },
            commit: () => { if (pin.kind === "image" && pin.file && !root.pins.some(p => p.key === pin.key)) Quickshell.execDetached(["rm", "-f", "--", pin.file]) }
        })
    }
    // Copy (and optionally paste) a pin: values go in as environment, not script text.
    function copyPin(pin, andPaste) {
        const press = andPaste ? `; ${root.pressPasteCommand}` : ""
        if (pin.kind === "image")
            Quickshell.execDetached({ command: ["bash", "-c", 'wl-copy -t "image/$EXT" < "$F"' + press], environment: ({ EXT: ({ jpg: "jpeg" })[pin.ext] ?? (pin.ext || "png").replace(/[^a-z0-9]/gi, ""), F: pin.file }) })
        else {
            const uris = /^file:\/\//.test(pin.text ?? "")
            Quickshell.execDetached({ command: ["bash", "-c", (uris ? 'printf "%s" "$T" | wl-copy -t text/uri-list' : 'printf "%s" "$T" | wl-copy') + press], environment: ({ T: pin.text ?? "" }) })
        }
    }
    // Either kind of row (a pin object, or a cliphist entry line).
    function copyItem(item) { if (root.isPin(item)) root.copyPin(item, false); else root.copy(item) }
    function pasteItem(item) { if (root.isPin(item)) root.copyPin(item, true); else root.paste(item) }
    function deleteItem(item) { if (root.isPin(item)) root.unpin(item); else root.deleteEntry(item) }
    function togglePin(item) { if (root.isPin(item)) root.unpin(item); else root.pin(item) }

    IpcHandler {
        target: "cliphistService"
        function update(): void { root.refresh() }
    }
}
