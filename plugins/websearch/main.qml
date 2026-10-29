import QtQuick

// Web search (docs/plugins.md). The engine list is ours; the idea is common to
// several sibling shells (inir's "?" search, ilyamiro's provider table).
// URLs are built with encodeURIComponent and opened by the default browser.
QtObject {
    property bool active: false
    property string query: ""

    readonly property var engines: [
        { key: "ddg", name: "DuckDuckGo", url: "https://duckduckgo.com/?q=" },
        { key: "g", name: "Google", url: "https://www.google.com/search?q=" },
        { key: "yt", name: "YouTube", url: "https://www.youtube.com/results?search_query=" },
        { key: "w", name: "Wikipedia", url: "https://en.wikipedia.org/w/index.php?search=" },
        { key: "gh", name: "GitHub", url: "https://github.com/search?q=" },
        { key: "aw", name: "Arch Wiki", url: "https://wiki.archlinux.org/index.php?search=" },
        { key: "aur", name: "AUR", url: "https://aur.archlinux.org/packages?K=" },
        { key: "b", name: "Brave Search", url: "https://search.brave.com/search?q=" }
    ]

    readonly property var results: {
        const q = query.trim()
        if (!active || !q) return []
        const sp = q.indexOf(" ")
        const first = sp > 0 ? q.slice(0, sp).toLowerCase() : ""
        const only = engines.find(e => e.key === first)
        const text = only ? q.slice(sp + 1).trim() : q
        if (!text) return []
        return (only ? [only] : engines).map(e => ({
            icon: "travel_explore",
            title: `${e.name}: ${text}`,
            subtitle: only ? "Enter opens it in your browser" : `"? ${e.key} …" for only ${e.name}`,
            run: () => Qt.openUrlExternally(e.url + encodeURIComponent(text))
        }))
    }
}
