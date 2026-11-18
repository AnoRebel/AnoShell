.pragma library

// The corner revolver's geometry. The cylinder is a disc centred on the screen corner with 12 chambers, three per
// quarter; one quarter shows. After `turns` quarter turns, quarter mod(turns, 4) is in view; each quarter holds a set
// of three actions so that the next set waits one quarter ahead and the previous one a quarter behind.

// The actions a chamber can hold (Settings lists them; Revolver.qml runs them). toggle: stays open, glows while on.
const CATALOG = [
    { id: "lock", label: "Lock", icon: "lock" },
    { id: "wallpaperPicker", label: "Wallpaper picker", icon: "wallpaper" },
    { id: "shuffleWallpaper", label: "Shuffle wallpaper", icon: "shuffle" },
    { id: "nightLight", label: "Night light", icon: "nightlight", toggle: true },
    { id: "settings", label: "Settings", icon: "settings" },
    { id: "restartShell", label: "Restart shell", icon: "restart_alt" },
    { id: "dnd", label: "Do not disturb", icon: "notifications_off", toggle: true },
    { id: "caffeine", label: "Keep awake", icon: "coffee", toggle: true },
    { id: "performance", label: "Performance mode", icon: "speed", toggle: true },
    { id: "overview", label: "Overview", icon: "grid_view" },
    { id: "clipboard", label: "Clipboard", icon: "content_paste" },
    { id: "session", label: "Power menu", icon: "power_settings_new" },
    { id: "sidebarLeft", label: "Left sidebar", icon: "left_panel_open" },
    { id: "sidebarRight", label: "Right sidebar", icon: "right_panel_open" }
]
function info(id) { return CATALOG.find(c => c.id === id) ?? null }

function mod(a, n) { return ((a % n) + n) % n }
function setCount(n) { return Math.max(1, Math.ceil(n / 3)) }

// Which set (0..) quarter q shows after `turns` turns.
function quarterSet(q, turns, sets) {
    const d = mod(q - mod(turns, 4), 4)
    return mod(turns + (d === 3 ? -1 : d), sets)
}

// The action id in each of the 12 slots ("" for an empty chamber).
function slots(ids, turns) {
    const sets = setCount(ids.length), out = []
    for (let s = 0; s < 12; s++) {
        const set = quarterSet(Math.floor(s / 3), turns, sets)
        out.push(ids[set * 3 + s % 3] ?? "")
    }
    return out
}

// A slot's angle in degrees from the screen edge (0 = along the bottom/top edge, 90 = along the side) for a disc
// turned to `disc` degrees (disc = -90 * turns shows quarter `turns`).
function angle(slot, disc) { return 15 + 30 * slot + disc }

// A point at `deg` and radius r from the corner, in a w×h window sitting in that corner.
function point(corner, deg, r, w, h) {
    const a = deg * Math.PI / 180
    const dx = Math.cos(a) * r, dy = Math.sin(a) * r
    return {
        x: corner.endsWith("Left") || corner.endsWith("left") ? dx : w - dx,
        y: corner.startsWith("bottom") ? h - dy : dy
    }
}

// Whether a slot at `deg` is in the visible quarter (with a margin so chambers swing in and out smoothly).
function shown(deg) { const d = mod(deg, 360); return d > -1 && d < 91 || d > 349 }

// The corner diagonally opposite (where a shot flies).
function opposite(corner) {
    return ({ bottomLeft: "topRight", bottomRight: "topLeft", topLeft: "bottomRight", topRight: "bottomLeft" })[corner] ?? "topRight"
}
