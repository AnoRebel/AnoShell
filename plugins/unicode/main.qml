import QtQuick
import Quickshell
import Quickshell.Io

// Unicode symbols by name (docs/plugins.md); symbols.tsv is generated from
// Python's unicodedata (the common symbol blocks), read on first use.
QtObject {
    id: root
    property bool active: false
    property string query: ""
    property var symbols: []   // [[char, name]]
    property FileView file: FileView {
        path: root.active || root.symbols.length ? Qt.resolvedUrl("symbols.tsv").toString().replace("file://", "").split("/").map(decodeURIComponent).join("/") : ""
        onLoaded: root.symbols = text().split("\n").filter(l => l && !l.startsWith("#")).map(l => l.split("\t"))
    }

    readonly property var results: {
        const words = query.trim().toLowerCase().split(/\s+/).filter(w => w)
        if (!active || words.length === 0) return []
        const out = []
        for (const [ch, name] of root.symbols) {
            if (!words.every(w => name.includes(w))) continue
            out.push({ text: ch, title: name, subtitle: `U+${ch.codePointAt(0).toString(16).toUpperCase().padStart(4, "0")} · Enter copies it`,
                run: () => Quickshell.execDetached(["wl-copy", "--", ch]) })
            if (out.length >= 20) break
        }
        return out
    }
}
