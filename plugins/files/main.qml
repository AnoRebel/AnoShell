import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Files in the home by name (docs/plugins.md). Ported from Bioma's
// services/Files.qml (GPL-3.0): no index, `fd` walks the home each time
// (it skips hidden files and what .gitignore/.fdignore exclude, so it's
// quick), the words matched in order, ranked: the name starting with what
// was typed, then a word in it, then the nearest to the home. A newer
// query stops the older walk; only the walk still wanted lands.
QtObject {
    id: root
    property bool active: false
    property string query: ""

    readonly property string home: Quickshell.env("HOME")
    property var found: []
    property string answered: ""
    property var walking: null

    readonly property var words: {
        const w = query.trim().toLowerCase().split(/\s+/).filter(x => x)
        return active && w.join(" ").length >= 3 ? w : []
    }
    onWordsChanged: {
        if (root.walking) { root.walking.running = false; root.walking = null }
        if (root.words.length === 0) { settle.stop(); root.found = []; return }
        settle.restart()
    }
    property Timer settle: Timer {
        interval: 150
        onTriggered: {
            const pattern = root.words.map(w => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*")
            root.walking = root.walker.createObject(root, { asked: root.words.join(" "),
                command: ["fd", "--color", "never", "--ignore-case", "--absolute-path", "--max-results", "300", "--", pattern, root.home] })
            root.walking.running = true
        }
    }
    property Component walker: Component {
        Process {
            id: walk
            property string asked: ""
            stdout: StdioCollector { onStreamFinished: root.land(walk.asked, text) }
            onExited: walk.destroy()
        }
    }
    function land(asked, text) {
        if (asked !== root.words.join(" ")) return
        const out = []
        for (const line of text.split("\n")) {
            const e = line ? root.describe(line, root.words) : null
            if (e) out.push(e)
        }
        out.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name))
        root.found = out.slice(0, 20)
        root.walking = null
    }
    function describe(line, words) {
        const dir = line.endsWith("/")
        const path = dir ? line.slice(0, -1) : line
        const cut = path.lastIndexOf("/")
        const name = path.slice(cut + 1), lowered = name.toLowerCase()
        let from = 0, score = 0
        for (const word of words) {
            const at = lowered.indexOf(word, from)
            if (at < 0) return null
            score += at === 0 ? 8 : /[\s._\-]/.test(lowered[at - 1]) ? 4 : 0
            from = at + word.length
        }
        if ((dir ? lowered : lowered.replace(/\.[^.]+$/, "")) === words.join(" ")) score += 10
        score -= (path.slice(root.home.length).split("/").length - 2) * 0.75 + name.length * 0.02
        const folder = path.slice(0, cut)
        return { path, name, dir, score, folder: folder.startsWith(root.home) ? "~" + folder.slice(root.home.length) : folder }
    }
    function icon(e) {
        if (e.dir) return "folder"
        const ext = e.name.toLowerCase().split(".").pop()
        if (/^(png|jpe?g|gif|webp|svg|bmp|tiff?|heic|avif)$/.test(ext)) return "image"
        if (/^(mp4|mkv|webm|mov|avi)$/.test(ext)) return "movie"
        if (/^(mp3|flac|ogg|opus|wav|m4a|aac)$/.test(ext)) return "music_note"
        if (ext === "pdf") return "picture_as_pdf"
        if (/^(zip|tar|gz|xz|zst|7z|rar|bz2)$/.test(ext)) return "folder_zip"
        return "description"
    }

    readonly property var results: !active ? [] : root.found.map(e => ({
        icon: root.icon(e), title: e.name, subtitle: e.folder,
        run: () => DefaultApps.launch(["xdg-open", e.path])
    }))
}
