import QtQuick
import qs.services

// Open windows, most recently used first (services/WindowMru), through the
// Wayland toplevel protocol, so it works wherever the alt-switcher does.
QtObject {
    property bool active: false
    property string query: ""

    readonly property var results: {
        if (!active) return []
        const words = query.trim().toLowerCase().split(/\s+/).filter(w => w)
        return WindowMru.ordered.filter(t => {
            const hay = `${t.title ?? ""} ${t.appId ?? ""}`.toLowerCase()
            return words.every(w => hay.includes(w))
        }).slice(0, 20).map(t => ({
            icon: "select_window",
            title: t.title || t.appId || "Window",
            subtitle: t.appId ?? "",
            run: () => t.activate()
        }))
    }
}
