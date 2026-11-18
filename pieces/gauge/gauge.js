.pragma library

// Helpers for the Gauge piece: what fits at a size, the battery's colour, and the points of a wavy ring.

// What shows inside the ring at a piece size (px): the value from 48 px, the label from 110, the icon from 150.
function parts(w, h) {
    const s = Math.min(w, h)
    return { value: s >= 48, label: s >= 110, icon: s >= 150 }
}

// "charging" (green), "low" (red: 20% or less, unplugged) or "" (the accent).
function batteryState(fraction, charging, pluggedIn) {
    if (charging) return "charging"
    if (!pluggedIn && fraction <= 0.2) return "low"
    return ""
}

// Points along a ring of radius r around (cx, cy) whose edge is a sine wave of `waves` crests and amplitude `amp`,
// from the top clockwise over `fraction` of the turn. Returns [] for nothing to draw.
function wavePoints(cx, cy, r, amp, waves, fraction, steps) {
    const f = Math.max(0, Math.min(1, fraction))
    if (f <= 0) return []
    const n = Math.max(2, Math.ceil((steps || 180) * f))
    const out = []
    for (let i = 0; i <= n; i++) {
        const t = (i / n) * f * Math.PI * 2
        const rr = r + amp * Math.sin(t * waves)
        const a = t - Math.PI / 2
        out.push(Qt.point(cx + rr * Math.cos(a), cy + rr * Math.sin(a)))
    }
    return out
}
