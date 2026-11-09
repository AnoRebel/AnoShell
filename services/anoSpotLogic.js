.pragma library

// The pill's decisions (services/PillTransient, modules/anoSpot): which
// transient may replace the one on show, which timer the timer activity
// shows, which downloads just finished. Pure; tested in
// scripts/dev/test-anospot-logic.js.

// A transient on show is only replaced by one of at least its rank. Levels
// (volume, brightness, mic, keyboard) are the user's own hand: rank 0, so
// anything replaces them, and they replace anything (always shown at once).
const RANK = { notification: 1, device: 1, charging: 2, recording: 3, download: 3, screenshot: 3 }
const LEVELS = ["volume", "brightness", "mic", "keyboard"]

function replaces(current, next) {
    if (!current || LEVELS.includes(next)) return true
    return (RANK[next] ?? 0) >= (RANK[current] ?? 0)
}

// "4:05", "1:02:03"
function clock(s) {
    s = Math.max(0, Math.floor(s))
    const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
    return (h ? `${h}:${String(m).padStart(2, "0")}` : `${m}`) + `:${String(sec).padStart(2, "0")}`
}

// The running timer to show (services/Pomodoro's state), or null. A countdown
// first (it ends), then the pomodoro, then the stopwatch.
//   p: { enabled, running, phase, remaining (s), cdRunning, cdLeft (ms), swRunning, swElapsed (ms) }
//   → { mode: "countdown" | "focus" | "stopwatch", icon, text }
function timer(p) {
    if (!p || !p.enabled) return null
    if (p.cdRunning) return { mode: "countdown", icon: "hourglass_bottom", text: clock(Math.ceil(p.cdLeft / 1000)) }
    if (p.running) return { mode: "focus", icon: p.phase === "focus" ? "self_improvement" : "coffee", text: clock(p.remaining) }
    if (p.swRunning) return { mode: "stopwatch", icon: "timer", text: clock(p.swElapsed / 1000) }
    return null
}

// Finished downloads not seen before (newest first, as given). `seen` is the
// previous list of paths, or null the first time (that list is what was
// already there: nothing is new).
function newlyFinished(seen, finished) {
    if (!seen) return []
    return (finished || []).filter(f => !seen.includes(f.path))
}
