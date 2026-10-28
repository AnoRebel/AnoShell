import QtQuick
import qs.services

// A launcher plugin (docs/plugins.md): the host sets `active` (the query
// starts with "cb ") and `query` (what follows), and shows `results`.
QtObject {
    property bool active: false
    property string query: ""
    onActiveChanged: if (active) Cliphist.refresh()

    readonly property var results: {
        if (!active) return []
        const q = query.trim().toLowerCase()
        const out = []
        for (const entry of Cliphist.entries) {
            if (Cliphist.entryIsImage(entry)) continue
            const text = entry.replace(/^\d+\t/, "").trim()
            if (q && !text.toLowerCase().includes(q)) continue
            out.push({
                icon: "content_paste", title: text.replace(/\s+/g, " ").slice(0, 120),
                subtitle: "Enter copies it", run: () => Cliphist.copy(entry)
            })
            if (out.length >= 12) break
        }
        return out
    }
}
