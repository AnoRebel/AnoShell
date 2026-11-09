pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.services

/**
 * Sound effects (ported from Bioma's services/Sounds.qml, GPL-3; the sounds
 * in assets/sounds are Bioma's own). All off by default: one switch per kind
 * (sounds.login / .notifications / .panels / .alerts), one volume for all.
 *
 * Every sound is a detached `pw-play`: nothing is loaded into the shell and no
 * stream is held open between sounds. Paths and names always go in as argv,
 * never into a shell script's text.
 *
 *   named(name)   a freedesktop sound-theme sound (sounds.theme, then
 *                 freedesktop), used by Battery through Audio.playSystemSound
 *   notification  called by Notifications for a notification that pops up
 *   panels        GlobalStates' panel flags: open, close (debounced)
 *   alerts        CPU / RAM over sounds.alertThreshold, battery critical
 *   login         once per session (marker in $XDG_RUNTIME_DIR)
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.sounds ?? ({})
    readonly property real volume: Math.max(0, Math.min(1, root.opts.volume ?? 0.6))
    function enabled(kind) { return Config.ready && root.opts[kind] === true }

    // ─── Playing ──────────────────────────────────────────────────────────
    readonly property var _pwPlay: ["pw-play", "--media-role", "Notification", "--volume", String(root.volume),
        "-P", "{ application.name = \"AnoShell\" }"]

    property var _last: ({}) // name → when it last started
    function _since(name) { return Date.now() - (root._last[name] ?? 0) }

    // One of the bundled sounds (assets/sounds/<name>.wav).
    function play(name) {
        if (root.volume <= 0 || root._since(name) < 60) return // the same sound twice inside 60 ms is one
        const stamps = Object.assign({}, root._last)
        stamps[name] = Date.now()
        root._last = stamps
        Quickshell.execDetached(root._pwPlay.concat([Quickshell.shellPath(`assets/sounds/${name}.wav`)]))
    }

    // Plays the first readable regular file among `candidates` (absolute
    // paths). sh only tests and execs; the paths are its arguments.
    function _playFirst(candidates) {
        if (root.volume <= 0 || candidates.length === 0) return
        Quickshell.execDetached(["sh", "-c",
            'v=$1; shift; for f; do [ -f "$f" ] && [ -r "$f" ] && exec pw-play --media-role Notification --volume "$v" -P "{ application.name = \\"AnoShell\\" }" "$f"; done',
            "sh", String(root.volume)].concat(candidates))
    }

    // A sound from the freedesktop sound theme (sounds.theme, falling back to
    // freedesktop), looked up where the theme spec says. Nothing found: silence.
    function named(name) {
        if (!/^[A-Za-z0-9._-]+$/.test(String(name ?? ""))) return
        const home = Quickshell.env("XDG_DATA_HOME") || `${Quickshell.env("HOME")}/.local/share`
        const dirs = [home].concat((Quickshell.env("XDG_DATA_DIRS") || "/usr/local/share:/usr/share").split(":").filter(d => d.startsWith("/")))
        const theme = String(root.opts.theme ?? "freedesktop")
        const themes = /^[A-Za-z0-9._-]+$/.test(theme) && theme !== "freedesktop" ? [theme, "freedesktop"] : ["freedesktop"]
        const out = []
        for (const t of themes)
            for (const dir of dirs)
                for (const sub of ["stereo/", ""])
                    for (const ext of ["oga", "ogg", "wav"])
                        out.push(`${dir}/sounds/${t}/${sub}${name}.${ext}`)
        root._playFirst(out)
    }

    // ─── Notifications ────────────────────────────────────────────────────
    // The freedesktop hints decide whose sound it is: suppress-sound means
    // none; sound-file / sound-name are the sender's own, which the server
    // plays. Only a notification with none of them gets ours.
    function notification(n) {
        if (!root.enabled("notifications") || root.volume <= 0) return
        const hints = n?.hints ?? ({})
        if (hints["suppress-sound"] === true || hints["suppress-sound"] === 1) return
        const file = root._soundFile(hints["sound-file"])
        if (file) { root._playFirst([file]); return }
        const name = String(hints["sound-name"] ?? "")
        if (name.length > 0) { root.named(name); return }
        root.play("notification")
    }
    // sound-file is untrusted: only an absolute path (or file:// URL) to an
    // audio file; that it is an existing regular file is checked by _playFirst.
    function _soundFile(v) {
        let p = String(v ?? "")
        if (p.startsWith("file://")) {
            try { p = decodeURIComponent(p.slice(7)) } catch (e) { return "" }
        }
        if (!p.startsWith("/") || /[\n\r\0]/.test(p) || p.includes("/../")) return ""
        return /\.(oga|ogg|wav|flac|mp3|opus)$/i.test(p) ? p : ""
    }

    // ─── Panels ───────────────────────────────────────────────────────────
    // Two panels trading places would play both, so a close waits 90 ms and
    // is dropped when an open comes inside it, before or after.
    readonly property var _panelFlags: ["sidebarLeftOpen", "sidebarRightOpen", "overviewOpen", "taskViewOpen",
        "searchOpen", "clipboardOpen", "controlPanelOpen", "cheatsheetOpen", "sessionOpen", "calendarOpen",
        "weatherPanelOpen", "mediaControlsOpen", "networkOrbitOpen", "wallpaperSelectorOpen", "settingsOverlayOpen",
        "focusTimeOpen", "displayManagerOpen"]
    readonly property string _panelState: root.enabled("panels")
        ? root._panelFlags.map(k => GlobalStates[k] ? "1" : "0").join("") : ""
    property string _prevPanels: ""
    on_PanelStateChanged: {
        const prev = root._prevPanels
        root._prevPanels = root._panelState
        if (prev.length !== root._panelState.length) return // just switched on
        let opened = false, closed = false
        for (let i = 0; i < prev.length; i++) {
            if (prev[i] === root._panelState[i]) continue
            if (root._panelState[i] === "1") opened = true
            else closed = true
        }
        if (opened) root.panel(true)
        else if (closed) root.panel(false)
    }
    function panel(open) {
        if (!root.enabled("panels")) return
        if (open) {
            closing.stop()
            root.play("open")
        } else if (root._since("open") > closing.interval) {
            closing.restart()
        }
    }
    Timer { id: closing; interval: 90; onTriggered: root.play("close") }

    // ─── Login ────────────────────────────────────────────────────────────
    // The shell restarts far more often than anyone logs in, so the session
    // remembers it was greeted in a marker in its runtime directory.
    property bool _greeting: false
    function greet() { root._greeting = true; root._tryGreet() }
    function _tryGreet() {
        if (!root._greeting || !Config.ready) return
        root._greeting = false
        greeted.running = true
    }
    Connections { target: Config; function onReadyChanged() { root._tryGreet() } }
    Process {
        id: greeted
        command: ["sh", "-c", 'm="${XDG_RUNTIME_DIR:-/tmp}/anoshell-greeted"; [ -e "$m" ] && exit 1; : > "$m"']
        onExited: code => { if (code === 0 && root.enabled("login")) root.play("login") }
    }

    // ─── Alerts ───────────────────────────────────────────────────────────
    // A value crossing into the alert zone sounds once on the way in; one that
    // left it must stay out sounds.alertGap seconds before it can sound again.
    // Nothing sounds in the first 15 s (the shell loading itself).
    readonly property bool _alerts: root.enabled("alerts")
    readonly property real _threshold: Math.max(10, Math.min(100, root.opts.alertThreshold ?? 90)) / 100
    readonly property int alertGap: Math.max(0, root.opts.alertGap ?? 300) * 1000
    ServiceLease { service: ResourceUsage; name: "sounds"; active: root._alerts }

    readonly property bool cpuRed: root._alerts && ResourceUsage.cpuUsage >= root._threshold
    readonly property bool ramRed: root._alerts && ResourceUsage.memoryUsedPercentage >= root._threshold
    readonly property bool batteryRed: root._alerts && Battery.available && Battery.isCriticalAndNotCharging
    onCpuRedChanged: root._redden("cpu", root.cpuRed)
    onRamRedChanged: root._redden("ram", root.ramRed)
    onBatteryRedChanged: root._redden("battery", root.batteryRed)

    property bool _armed: false
    Timer { interval: 15000; running: true; onTriggered: root._armed = true }
    property var _cooled: ({}) // key → when it last left the alert zone
    function _redden(key, red) {
        if (!red) {
            const next = Object.assign({}, root._cooled)
            next[key] = Date.now()
            root._cooled = next
            return
        }
        if (!root._armed || !root._alerts) return
        if (key in root._cooled && Date.now() - root._cooled[key] < root.alertGap) return
        if (root._since("alert") < 1500) return // two values turning red together are one alarm
        root.play("alert")
    }

    IpcHandler {
        target: "sounds"
        /// Play a bundled sound (login, notification, open, close, alert), whatever the switches say.
        function play(name: string): void { if (/^(login|notification|open|close|alert)$/.test(name)) root.play(name) }
        /// Play a sound-theme sound by name (e.g. bell, complete).
        function named(name: string): void { root.named(name) }
    }
}
