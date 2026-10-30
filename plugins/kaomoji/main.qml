import QtQuick
import Quickshell
import Quickshell.Io

// Kaomoji by category (docs/plugins.md). kaomoji.json comes from
// github.com/dhrruvsharma's dotfiles (GPL-3.0): [{ name, categories: [{ name, emoticons }] }].
// Read once, when the plugin first answers.
QtObject {
    id: root
    property bool active: false
    property string query: ""

    property var groups: []   // [{ group, category, faces }]
    property FileView file: FileView {
        path: root.active || root.groups.length ? Qt.resolvedUrl("kaomoji.json").toString().replace("file://", "").split("/").map(decodeURIComponent).join("/") : ""
        onLoaded: {
            try {
                root.groups = [].concat(...JSON.parse(text()).map(g => (g.categories ?? []).map(c => ({ group: g.name, category: c.name, faces: c.emoticons ?? [] }))))
            } catch (e) { console.warn("[kaomoji]", e) }
        }
    }

    readonly property var results: {
        if (!active) return []
        const q = query.trim().toLowerCase()
        const hits = groups.filter(c => !q || c.category.toLowerCase().includes(q) || c.group.toLowerCase().includes(q))
        const out = []
        for (const c of hits) {
            for (const f of c.faces) {
                out.push({ text: "ツ", title: f, subtitle: `${c.group} · ${c.category} · Enter copies it`,
                    run: () => Quickshell.execDetached(["wl-copy", "--", f]) })
                if (out.length >= 20) return out
            }
        }
        return out
    }
}
