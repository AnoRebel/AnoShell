pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * Actions: macros you write on Settings → Actions and run from the ring
 * (modules/actions/ActionsRing.qml, the first 8), a key, or IPC:
 *
 *   qs -c ano ipc call actions run "<name>"   ·   list   ·   ring
 *
 * actions.macros: [{ name, icon, steps: [{ type, … }] }]. Each step kind is
 * one object in `kinds` (label, icon, fresh(), fields, describe(), run());
 * the runner and the Settings editor both read it, so a new kind is one
 * block here. run(step, done) calls done("") when the step is through, or
 * done("why not") — a failing step stops the macro and posts a shell
 * notification naming it. A macro asked for while another runs is queued.
 * Shape after Bioma's services/Actions.qml (GPL-3).
 */
Singleton {
    id: root

    readonly property var macros: {
        const list = Config.options?.actions?.macros ?? []
        return Array.from(list).filter(m => m && typeof m.name === "string" && m.name.length > 0)
    }
    readonly property int ringSize: 8
    readonly property var ring: root.macros.slice(0, root.ringSize)

    function find(name) { return root.macros.find(m => m.name === name) ?? null }

    // ── Helpers the kinds share ─────────────────────────────────────────
    function expand(path) {
        const home = FileUtils.trimFileProtocol(Directories.home)
        return String(path ?? "").trim().replace(/^~(?=\/|$)/, home).replace(/^\$HOME(?=\/|$)/, home)
    }
    function entryOf(id) {
        const s = String(id ?? "").trim().replace(/\.desktop$/, "")
        return s ? (DesktopEntries.byId(s) ?? DesktopEntries.heuristicLookup(s)) : null
    }
    function baseName(path) { return String(path ?? "").split("/").pop() }
    function configValue(key) {
        let v = Config.options
        for (const part of String(key).split(".")) { v = v?.[part]; if (v === undefined) return undefined }
        return v
    }
    // A copy of what the shell reads now (a JsonObject becomes plain JSON).
    function snapshot(key) {
        const v = root.configValue(key)
        return v === undefined ? null : JSON.parse(JSON.stringify(v))
    }

    // Presets (bundled presets/ and ~/.config/anoshell/presets/), for the
    // editor's choices; a step reads its file again when it runs.
    property var presets: []   // [{ path, name }]
    function loadPresets() { presetLister.running = false; presetLister.running = true }
    Process {
        id: presetLister
        command: ["sh", "-c", 'for d in "$1" "$2"; do for f in "$d"/*.json; do [ -f "$f" ] && { printf "%s\\t" "$f"; tr -d "\\n" < "$f"; echo; }; done; done',
            "sh", Quickshell.shellPath("presets"), `${FileUtils.trimFileProtocol(Directories.config)}/anoshell/presets`]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    if (tab < 0) continue
                    try { out.push({ path: line.slice(0, tab), name: JSON.parse(line.slice(tab + 1)).name ?? root.baseName(line.slice(0, tab)) }) } catch (e) {}
                }
                root.presets = out
            }
        }
    }
    property var _presetDone: null
    Process {
        id: presetReader
        stdout: StdioCollector {
            onStreamFinished: {
                const done = root._presetDone
                root._presetDone = null
                if (!done) return
                let values = null
                try { values = JSON.parse(text).values } catch (e) {}
                if (!values || typeof values !== "object") { done("the preset file can't be read"); return }
                for (const k of Object.keys(values)) Config.setNestedValue(k, values[k])
                done("")
            }
        }
    }

    // ── The kinds of step ───────────────────────────────────────────────
    // fields: what the editor shows, { key, label, type: text|app|percent|
    // seconds|bool|choice|snapshot, choices() → [{ value, label }], placeholder }.
    readonly property var order: ["launch", "open", "volume", "brightness", "dnd", "powerProfile", "performance",
        "wallpaper", "preset", "look", "wait", "command", "config"]
    readonly property var kinds: ({
        "launch": {
            label: "Launch app", icon: "apps",
            fresh: () => ({ type: "launch", app: "" }),
            fields: [{ key: "app", label: "Application", type: "app", placeholder: "Name or desktop id (firefox)" }],
            describe: s => root.entryOf(s.app)?.name ?? (s.app || "No application"),
            run: (s, done) => {
                const e = root.entryOf(s.app)
                if (!e) return done(`no application "${s.app ?? ""}"`)
                done(DefaultApps.launchEntry(e) ? "" : "it could not be started")
            }
        },
        "open": {
            label: "Open file or URL", icon: "open_in_new",
            fresh: () => ({ type: "open", target: "" }),
            fields: [{ key: "target", label: "File or URL", type: "text", placeholder: "~/Documents/notes.md or https://…" }],
            describe: s => s.target ? (/^[a-z]+:/i.test(s.target) ? s.target : root.baseName(s.target)) : "Nothing to open",
            run: (s, done) => {
                const t = String(s.target ?? "").trim()
                if (!t) return done("nothing to open")
                done(DefaultApps.launch(["xdg-open", /^[a-z][a-z0-9+.-]*:/i.test(t) ? t : root.expand(t)], "", "xdg-open") ? "" : "xdg-open could not start")
            }
        },
        "volume": {
            label: "Set volume", icon: "volume_up",
            fresh: () => ({ type: "volume", percent: 50 }),
            fields: [{ key: "percent", label: "Volume", type: "percent" }],
            describe: s => `${Math.round(s.percent ?? 50)}%`,
            run: (s, done) => {
                if (!Audio.sink?.audio) return done("there is no audio output")
                Audio.sink.audio.volume = Math.max(0, Math.min(100, s.percent ?? 50)) / 100
                done("")
            }
        },
        "brightness": {
            label: "Set brightness", icon: "brightness_6",
            fresh: () => ({ type: "brightness", percent: 70 }),
            fields: [{ key: "percent", label: "Brightness (every display that can)", type: "percent" }],
            describe: s => `${Math.round(s.percent ?? 70)}%`,
            run: (s, done) => {
                const ready = Brightness.monitors.filter(m => m.ready)
                if (ready.length === 0) return done("no display's brightness can be set")
                for (const m of ready) m.setBrightness(Math.max(1, Math.min(100, s.percent ?? 70)) / 100)
                done("")
            }
        },
        "dnd": {
            label: "Do not disturb", icon: "do_not_disturb_on",
            fresh: () => ({ type: "dnd", on: true }),
            fields: [{ key: "on", label: "Do not disturb on", type: "bool" }],
            describe: s => s.on ? "On" : "Off",
            run: (s, done) => { Notifications.silent = s.on === true; done("") }
        },
        "powerProfile": {
            label: "Power profile", icon: "battery_profile",
            fresh: () => ({ type: "powerProfile", profile: "balanced" }),
            fields: [{ key: "profile", label: "Profile", type: "choice", choices: () => [
                { value: "power-saver", label: "Power saver", icon: "eco" },
                { value: "balanced", label: "Balanced", icon: "balance" },
                { value: "performance", label: "Performance", icon: "speed" }] }],
            describe: s => ({ "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" })[s.profile] ?? "Balanced",
            run: (s, done) => {
                const p = { "power-saver": PowerProfile.PowerSaver, "balanced": PowerProfile.Balanced, "performance": PowerProfile.Performance }[s.profile]
                if (p === undefined) return done(`no power profile "${s.profile ?? ""}"`)
                if (!PowerProfilePersistence.available) return done("power-profiles-daemon isn't running")
                if (p === PowerProfile.Performance && !PowerProfiles.hasPerformanceProfile) return done("this machine has no performance profile (is power-profiles-daemon running?)")
                PowerProfiles.profile = p
                done("")
            }
        },
        "performance": {
            label: "Performance mode", icon: "speed",
            fresh: () => ({ type: "performance", on: true }),
            fields: [{ key: "on", label: "Performance mode on", type: "bool" }],
            describe: s => s.on ? "On" : "Off",
            // The by-hand switch: off here still leaves it on while a game holds GameMode.
            run: (s, done) => { GameMode.manual = s.on === true; done("") }
        },
        "wallpaper": {
            label: "Wallpaper", icon: "wallpaper",
            fresh: () => ({ type: "wallpaper", path: Config.options?.background?.wallpaperPath ?? "" }),
            fields: [{ key: "path", label: "Image or video", type: "text", placeholder: "~/Pictures/Wallpapers/…" }],
            describe: s => s.path ? root.baseName(s.path) : "No wallpaper",
            run: (s, done) => {
                if (!String(s.path ?? "").trim()) return done("no wallpaper chosen")
                Wallpapers.apply(root.expand(s.path))
                done("")
            }
        },
        "preset": {
            label: "Apply preset", icon: "auto_awesome_mosaic",
            fresh: () => ({ type: "preset", path: "" }),
            fields: [{ key: "path", label: "Preset", type: "choice", choices: () => root.presets.map(p => ({ value: p.path, label: p.name, icon: "auto_awesome_mosaic" })) }],
            describe: s => root.presets.find(p => p.path === s.path)?.name ?? (s.path ? root.baseName(s.path).replace(/\.json$/, "") : "No preset"),
            run: (s, done) => {
                if (!s.path) return done("no preset chosen")
                root._presetDone = done
                presetReader.running = false
                presetReader.command = ["cat", "--", s.path]
                presetReader.running = true
            }
        },
        "look": {
            label: "Apply look", icon: "palette",
            fresh: () => ({ type: "look", id: Looks.activeId }),
            fields: [{ key: "id", label: "Look", type: "choice", choices: () => Looks.list.map(l => ({ value: l.id, label: l.name, icon: "palette" })) }],
            describe: s => Looks.entries[s.id]?.name ?? (s.id || "No look"),
            run: (s, done) => {
                if (!Looks.usable(s.id)) return done(`no usable look "${s.id ?? ""}"`)
                Config.setNestedValue("appearance.look", s.id)
                done("")
            }
        },
        "wait": {
            label: "Wait", icon: "hourglass_empty",
            fresh: () => ({ type: "wait", seconds: 2 }),
            fields: [{ key: "seconds", label: "Seconds", type: "seconds" }],
            describe: s => `${s.seconds ?? 2} s`,
            run: (s, done) => {
                root._waitDone = done
                waitTimer.interval = Math.max(0, Math.min(3600, Number(s.seconds ?? 2) || 0)) * 1000
                waitTimer.restart()
            }
        },
        "command": {
            label: "Shell command", icon: "terminal",
            fresh: () => ({ type: "command", command: "" }),
            fields: [{ key: "command", label: "Command (run by sh, detached)", type: "text", placeholder: "notify-send hi" }],
            describe: s => s.command || "No command",
            // The text is sh's argument, never spliced into another command line.
            run: (s, done) => {
                const c = String(s.command ?? "")
                if (!c.trim()) return done("no command")
                done(DefaultApps.launch(["sh", "-c", c], "", "action") ? "" : "it could not be started")
            }
        },
        "config": {
            label: "Set a setting", icon: "tune",
            fresh: () => ({ type: "config", key: "", value: null }),
            fields: [{ key: "key", label: "Setting", type: "snapshot", placeholder: "bar.style" }],
            describe: s => s.key ? `${s.key} = ${JSON.stringify(s.value)}` : "No setting",
            run: (s, done) => {
                const k = String(s.key ?? "").trim()
                if (!k) return done("no setting chosen")
                if (k === "actions" || k.startsWith("actions.")) return done("a macro can't change the macros")
                if (root.configValue(k) === undefined) return done(`there is no setting "${k}"`)
                Config.setNestedValue(k, s.value)
                done("")
            }
        }
    })

    function kindOf(step) { return step && root.kinds[step.type] ? root.kinds[step.type] : null }
    function describe(step) { return root.kindOf(step)?.describe(step) ?? `Unknown step "${step?.type ?? ""}"` }

    property var _waitDone: null
    Timer {
        id: waitTimer
        onTriggered: { const d = root._waitDone; root._waitDone = null; if (d) d("") }
    }

    // ── Running ─────────────────────────────────────────────────────────
    property string running: ""        // the macro running now
    property int stepIndex: -1
    property var queue: []             // names waiting their turn
    property var _steps: []
    property int _token: 0             // a late done() from a finished run is ignored

    signal finished(string name)
    signal failed(string name, string reason)

    // "running", "queued", or "" when there is no such macro.
    function run(name) {
        const m = root.find(name)
        if (!m) return ""
        if (root.running !== "") { root.queue = root.queue.concat([name]); return "queued" }
        root.running = name
        root._steps = JSON.parse(JSON.stringify(Array.from(m.steps ?? [])))
        root.stepIndex = -1
        root._next()
        return "running"
    }

    function _next() {
        const token = ++root._token
        root.stepIndex++
        if (root.stepIndex >= root._steps.length) { root._end(""); return }
        const step = root._steps[root.stepIndex]
        const kind = root.kindOf(step)
        const done = reason => {
            if (token !== root._token) return
            if (reason) root._end(reason)
            else Qt.callLater(root._next)   // a long macro never deepens the stack
        }
        if (!kind) { done(`it is of a kind this shell doesn't know ("${step?.type ?? ""}")`); return }
        try { kind.run(step, done) } catch (e) { done(String(e?.message ?? e)) }
    }

    function _end(reason) {
        const name = root.running
        root._token++
        if (reason) {
            const step = root._steps[root.stepIndex]
            const label = root.kindOf(step)?.label ?? "Step"
            const msg = `Step ${root.stepIndex + 1} (${label}: ${root.describe(step)}) failed: ${reason}.`
            console.warn(`[Actions] "${name}" stopped. ${msg}`)
            Notifications.post(`Action "${name}" stopped`, msg, false)
            root.failed(name, reason)
        } else root.finished(name)
        root.running = ""
        root.stepIndex = -1
        root._steps = []
        if (root.queue.length) {
            const nextName = root.queue[0]
            root.queue = root.queue.slice(1)
            if (root.run(nextName) === "") Notifications.post("Action not found", `"${nextName}" was removed before its turn.`, false)
        }
    }

    // ── Editing (Settings) ──────────────────────────────────────────────
    function write(list) { Config.setNestedValue("actions.macros", JSON.parse(JSON.stringify(list))) }

    IpcHandler {
        target: "actions"
        function run(name: string): string {
            const r = root.run(name)
            return r === "queued" ? `queued "${name}" after "${root.running}"` : r ? `running "${name}"` : `no action "${name}"`
        }
        function list(): string { return root.macros.map(m => m.name).join("\n") }
        function ring(): string {
            if (!PanelGate.enabled("anoActions")) return "the actions ring is off (Settings → Modules)"
            GlobalStates.actionsRingOpen = !GlobalStates.actionsRingOpen
            return GlobalStates.actionsRingOpen ? "ring open" : "ring closed"
        }
    }
}
