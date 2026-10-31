import QtQuick
import Quickshell
import qs.services

// Your keybinds (anod's keybinds.list, the set Settings → Keybinds edits),
// fetched when the plugin becomes active. Enter copies the chord.
QtObject {
    id: root
    property bool active: false
    property string query: ""
    property var binds: []
    onActiveChanged: if (active && Anod.available)
        Anod.call("keybinds.list", {}, (r, e) => { if (r) root.binds = r.binds ?? [] })

    function describe(b) {
        const args = b.raw ? "a Lua function" : (b.args ?? []).join(" ")
        const name = ({ hyprland: "Hyprland action:", niri: "niri action:" })[b.action] ?? b.action
        return b.action === "exec" ? `Run ${args}` : args ? `${name} ${args}` : name
    }
    readonly property var results: {
        if (!active) return []
        if (!Anod.available) return [{ icon: "keyboard", title: "Keybinds need anod", subtitle: "Start it with ano setup, or check ano doctor", run: () => false }]
        const words = query.trim().toLowerCase().split(/\s+/).filter(w => w)
        return root.binds.filter(b => {
            const hay = `${b.chord} ${root.describe(b)}`.toLowerCase()
            return words.every(w => hay.includes(w))
        }).slice(0, 20).map(b => ({
            icon: "keyboard", title: b.chord, subtitle: root.describe(b),
            run: () => Quickshell.execDetached(["wl-copy", "--", b.chord])
        }))
    }
}
