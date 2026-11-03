pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Scratchpad & Pins (scratchpad.enable, off by default; spec
 * productivity-widgets "Scratchpad and Pins"). The tabs are the notepad,
 * to-do, clipboard and calendar services (held on while this is on); its own
 * data is only the pinned commands, in anoshell/scratchpad-pins.json:
 *   [{ key, command, terminal }]
 * A command runs in your terminal (terminal: true) or in the background,
 * where a non-zero exit notifies with its error output. The command is always
 * a single argument to `sh -c`, never spliced into another script.
 *
 *   qs -c ano ipc call scratchpad toggle|open|close
 *   qs -c ano ipc call scratchpad prompt ">>notify-send hi"
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.scratchpad?.enable ?? false
    property bool open: false
    onEnabledChanged: { if (!enabled) open = false; Notepad.hold(enabled); Todo.hold(enabled) }
    Component.onCompleted: if (enabled) { Notepad.hold(true); Todo.hold(true) }

    // ── Pins ─────────────────────────────────────────────────────────────
    property var pins: []
    property bool _loaded: false
    FileView {
        id: pinsFile
        path: root.enabled ? `${Directories.anoData}/scratchpad-pins.json` : ""
        printErrors: false
        // Off and on again: nothing from before counts until it reads again.
        onPathChanged: { root._loaded = false; root.pins = [] }
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.pins = (Array.isArray(d) ? d : []).filter(p => p && typeof p.command === "string" && p.command)
                root._loaded = true
            } catch (e) { console.warn(`[Scratchpad] scratchpad-pins.json: ${e}; not saving pins`) }
        }
        onLoadFailed: error => { if (error === FileViewError.FileNotFound) root._loaded = true }
    }
    function _save(list) {
        if (!root._loaded) {
            Quickshell.execDetached(["notify-send", "-a", "AnoShell", "--", "Scratchpad", "scratchpad-pins.json can't be read, so nothing is pinned (fix or remove the file)"])
            return false
        }
        root.pins = list
        pinsFile.setText(JSON.stringify(list, null, 1)) // FileView writes atomically
        return true
    }
    function pin(command, terminal) {
        const c = String(command ?? "").trim()
        if (!c || root.pins.some(p => p.command === c)) return false
        return root._save(root.pins.concat([{ key: `${Date.now()}`, command: c, terminal: !!terminal }]))
    }
    function unpin(key) { root._save(root.pins.filter(p => p.key !== key)) }
    function setTerminal(key, terminal) { root._save(root.pins.map(p => p.key === key ? Object.assign({}, p, { terminal: !!terminal }) : p)) }

    // ── Running ──────────────────────────────────────────────────────────
    // Background: its own unit/session (outlives the shell); a failure
    // notifies with the exit code and the start of the error output.
    // Only the error output's last 300 bytes are kept; pipefail keeps the command's exit code.
    readonly property string _bg: 'set -o pipefail; err=$(sh -c "$1" 2>&1 >/dev/null | tail -c 300); c=$?; '
        + '[ "$c" -eq 0 ] || notify-send -a AnoShell -- "Command failed (exit $c)" "$(printf \'%s\\n%s\' "$1" "$err")"'
    // Terminal: stays open after the command so its output can be read.
    readonly property string _held: 'sh -c "$1"; printf "\\n[exit %s · Enter closes]" "$?"; read -r _'
    function run(command, terminal) {
        const c = String(command ?? "").trim()
        if (!c) return false
        if (terminal) return DefaultApps.run("terminal", ["-e", "sh", "-c", root._held, "sh", c])
        return DefaultApps.launch(["bash", "-c", root._bg, "bash", c], "", "scratchpad") // bash: pipefail
    }
    function runPin(p) { return root.run(p.command, p.terminal) }
    function copy(text) {
        if (text) Quickshell.execDetached({ command: ["bash", "-c", 'printf "%s" "$T" | wl-copy'], environment: ({ T: String(text) }) })
    }

    // ── Prompt ───────────────────────────────────────────────────────────
    // What a prompt line means: { kind, text }
    //   ">>cmd" run · ">cmd" pin (the UI asks terminal or not) · "t …" to-do
    //   "?? …" AI · "? …" web search · anything else: the current note.
    function parse(line) {
        const s = String(line ?? "")
        const t = s.trim()
        if (!t) return { kind: "", text: "" }
        if (t.startsWith(">>")) return { kind: "run", text: t.slice(2).trim() }
        if (t.startsWith(">")) return { kind: "pin", text: t.slice(1).trim() }
        if (t.startsWith("??")) return { kind: "ai", text: t.slice(2).trim() }
        if (/^\?\s/.test(t)) return { kind: "web", text: t.slice(1).trim() }
        if (/^t\s/.test(t)) return { kind: "todo", text: t.slice(1).trim() }
        return { kind: "note", text: s }
    }
    // Acts on a line, except "pin" (the UI asks first; `terminal` given = no question).
    // { ok, msg }: msg for the prompt bar; the bar keeps the line when !ok.
    function submit(line, terminal) {
        const p = root.parse(line)
        const r = (ok, msg) => ({ ok: ok, msg: msg })
        if (!p.text) return r(false, "")
        switch (p.kind) {
        case "run": return root.run(p.text, false) ? r(true, "Running in the background") : r(false, "Couldn't start it")
        case "pin":
            if (terminal === undefined) return r(false, "ask")
            return root.pin(p.text, terminal) ? r(true, "Pinned") : r(false, "Already pinned")
        case "todo":
            if (!Todo.writable) return r(false, "The to-do list isn't ready")
            Todo.add(p.text); return r(true, "Added to the to-do list")
        case "web": return root.webSearch(p.text) ? r(true, "Opened in your browser") : r(false, "No search engine")
        case "ai": { const m = root.ask(p.text); return r(m === "Asking…", m) }
        default: return Notepad.appendText(p.text) ? r(true, "Added to the note") : r(false, "The notepad isn't ready")
        }
    }

    // "? text" (or "? g text"): the launcher's web search plugin, its first result.
    property QtObject _web: null
    function webSearch(q) {
        if (!root._web) {
            const c = Qt.createComponent("file://" + Quickshell.shellPath("plugins/websearch/main.qml"))
            if (c.status !== Component.Ready) { console.warn("[Scratchpad] websearch plugin:", c.errorString()); return false }
            root._web = c.createObject(root)
        }
        root._web.query = q
        root._web.active = true
        const r = root._web.results[0]
        root._web.active = false
        if (!r) return false
        r.run()
        return true
    }

    // "?? text": the AI chat's current model (the same conversation as the
    // sidebar). The answer is the newest assistant message.
    property string answerId: ""
    readonly property var answer: root.answerId ? (Ai.messageByID[root.answerId] ?? null) : null
    function ask(q) {
        if (Ai.pendingRequest) return "The AI is still answering"
        if (!Ai.currentModelId || !Ai.models[Ai.currentModelId]) return "No AI model chosen (left sidebar → AI)"
        if (!Ai.currentModelHasApiKey) return "No AI provider set up (left sidebar → AI: /key)"
        Ai.sendUserMessage(q)
        root.answerId = Ai.messageIDs[Ai.messageIDs.length - 1] ?? ""
        return "Asking…"
    }

    IpcHandler {
        target: "scratchpad"
        function toggle(): void { if (root.enabled) root.open = !root.open }
        // `open`, not `show`: `qs ipc call <target> show` lists the target instead of calling it.
        function open(): void { if (root.enabled) root.open = true }
        function close(): void { root.open = false }
        function prompt(line: string): string { return root.enabled ? root.submit(line, false).msg : "off" }
        function pins(): string { return root.enabled ? JSON.stringify(root.pins) : "off" }
    }
}
