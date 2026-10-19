pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

/**
 * Pomodoro and stopwatch (pomodoro.enable). Independent of focusTime: no DND,
 * no app tracking. The timer only ticks while something runs.
 */
Singleton {
    id: root
    readonly property var cfg: Config.options?.pomodoro ?? {}
    // ── Pomodoro ──────────────────────────────────────────────────────
    property string phase: "focus"          // focus | break | longBreak
    property int remaining: (cfg.focusMinutes ?? 25) * 60
    property bool running: false
    property int completed: 0              // focus sessions finished
    readonly property int phaseLength: (phase === "focus" ? (cfg.focusMinutes ?? 25) : phase === "break" ? (cfg.breakMinutes ?? 5) : (cfg.longBreakMinutes ?? 15)) * 60

    function start() { root.running = true }
    function pause() { root.running = false }
    function reset() { root.running = false; root.phase = "focus"; root.remaining = (cfg.focusMinutes ?? 25) * 60; root.completed = 0 }
    function skip() { root._next() }
    function _next() {
        if (root.phase === "focus") {
            root.completed++
            root.phase = root.completed % Math.max(1, cfg.cyclesBeforeLongBreak ?? 4) === 0 ? "longBreak" : "break"
        } else {
            root.phase = "focus"
        }
        root.remaining = root.phaseLength
        Quickshell.execDetached(["notify-send", "-a", "AnoShell", "Pomodoro",
            root.phase === "focus" ? "Back to focus" : root.phase === "break" ? "Short break" : "Long break"])
    }

    // ── Stopwatch ─────────────────────────────────────────────────────
    property bool swRunning: false
    property real swStart: 0      // ms epoch of the current run
    property real swBanked: 0     // ms from earlier runs
    property real swNow: 0
    readonly property real swElapsed: root.swBanked + (root.swRunning ? root.swNow - root.swStart : 0)
    function swToggle() {
        if (root.swRunning) { root.swBanked += Date.now() - root.swStart; root.swRunning = false }
        else { root.swStart = Date.now(); root.swNow = root.swStart; root.swRunning = true }
    }
    function swReset() { root.swRunning = false; root.swBanked = 0 }

    // Off with pomodoro.enable: nothing ticks or notifies without the UI.
    readonly property bool enabled: cfg.enable ?? false
    Timer {
        interval: 1000
        repeat: true
        running: root.enabled && root.running
        onTriggered: {
            if (root.remaining > 0) root.remaining--
            else root._next()
        }
    }
    Timer {
        interval: 100
        repeat: true
        running: root.enabled && root.swRunning
        onTriggered: root.swNow = Date.now()
    }
}
