pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Launches the user's default apps (Config.options.apps.*). Keybinds and
 * shell actions route through here (or `ano run`), so changing an app never
 * means regenerating binds:  qs -c ano ipc call apps run terminal
 *
 * An app value is a command line split on spaces (e.g. "kitty -1"). When its
 * program isn't installed, the first installed app of the catalogue
 * (assets/default-apps.json: kitty, then ghostty, alacritty, …) is used, the
 * same rule as `ano run`.
 */
Singleton {
    id: root

    readonly property var keys: ["terminal", "browser", "fileManager"]
    property var catalog: ({})          // key → [{command, name, packages}]
    property var installed: ({})        // command → true
    property string packageManager: ""  // pacman | apt | dnf | zypper
    property string aurHelper: ""       // yay | paru
    property bool detected: false
    // A changed apps.* (e.g. a terminal not in the catalogue) is looked up again.
    readonly property string _configuredKey: root.keys.map(k => root._configured(k)[0] ?? "").join("|")
    on_ConfiguredKeyChanged: if (root.detected) root.detect()
    // Installed = on PATH, or an app with a desktop entry of that name.
    function isInstalled(cmd) {
        if (!cmd) return false
        if (root.installed[cmd]) return true
        return DesktopEntries.applications.values.some(e => e.id === cmd || e.id === cmd + ".desktop")
    }

    FileView {
        path: Quickshell.shellPath("assets/default-apps.json")
        onLoaded: {
            try { root.catalog = JSON.parse(text()) } catch (e) { console.warn(`[DefaultApps] catalogue: ${e}`) }
            root.detect()
        }
    }

    // Which catalogue programs (and the configured ones) are on PATH. Names
    // go in as arguments, never into the script text.
    function detect() {
        const names = new Set(["pacman", "apt", "dnf", "zypper", "yay", "paru"])
        for (const k of root.keys) {
            for (const a of root.catalog[k] ?? []) names.add(a.command)
            const mine = root._configured(k)[0]
            if (mine) names.add(mine)
        }
        detectProc.command = ["sh", "-c", 'for c in "$@"; do command -v -- "$c" >/dev/null 2>&1 && echo "$c"; done', "sh"].concat([...names])
        detectProc.running = true
    }
    Process {
        id: detectProc
        stdout: StdioCollector {
            onStreamFinished: {
                const found = {}
                for (const l of text.split("\n")) if (l.trim()) found[l.trim()] = true
                root.installed = found
                root.packageManager = ["pacman", "apt", "dnf", "zypper"].find(p => found[p]) ?? ""
                root.aurHelper = ["yay", "paru"].find(p => found[p]) ?? ""
                root.detected = true
            }
        }
    }

    function _configured(kind) {
        const value = (Config.options?.apps?.[kind] ?? "").trim()
        return value.length > 0 ? value.split(/\s+/) : []
    }

    // The command line that runs for `kind` (see the header).
    function command(kind: string): list<string> {
        const mine = root._configured(kind)
        if (!root.detected || (mine.length > 0 && root.isInstalled(mine[0]))) return mine
        const first = (root.catalog[kind] ?? []).find(a => root.installed[a.command])
        return first ? [first.command] : mine
    }

    // How to install a catalogue app here ("" when there's no known package).
    function installCommand(app) {
        const p = app?.packages ?? {}
        if (root.packageManager && p[root.packageManager]) {
            const verb = { pacman: "sudo pacman -S", apt: "sudo apt install", dnf: "sudo dnf install", zypper: "sudo zypper install" }[root.packageManager]
            return `${verb} ${p[root.packageManager]}`
        }
        if (root.aurHelper && p.aur) return `${root.aurHelper} -S ${p.aur}`
        return ""
    }

    // `-e cmd…` in what this terminal takes (kitty/foot: the command alone,
    // wezterm: start --, gnome-terminal: --), from the catalogue's `exec`.
    function terminalArgs(term, args) {
        if (!args?.length || args[0] !== "-e") return args ?? []
        const t = (root.catalog.terminal ?? []).find(a => a.command === String(term).split("/").pop())
        return t && Array.isArray(t.exec) ? t.exec.concat(args.slice(1)) : args
    }

    // kind: "terminal" | "browser" | "fileManager"; extra args appended (e.g. a path).
    function run(kind: string, args): bool {
        const cmd = root.command(kind)
        if (cmd.length === 0) {
            console.warn(`[DefaultApps] no ${kind} configured or installed`)
            return false
        }
        return root.launch(cmd.concat(kind === "terminal" ? root.terminalArgs(cmd[0], args) : (args ?? [])))
    }

    // How apps start, probed once rather than assumed (OpenRC, runit, s6 and
    // sysvinit have no user manager): "systemd" = its own transient scope in
    // app.slice, out of the shell's cgroup and lifetime; "setsid" = a new
    // session; "plain" = detached only. Until the probe answers: setsid.
    property string launchMode: "setsid"
    Process {
        running: true
        command: ["sh", "-c", 'if command -v systemd-run >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then echo systemd; elif command -v setsid >/dev/null 2>&1; then echo setsid; else echo plain; fi']
        stdout: StdioCollector { onStreamFinished: root.launchMode = text.trim() || "plain" }
    }
    // A unit name from an app id: only unit-safe characters.
    function _unitName(name) {
        const id = String(name ?? "app").replace(/\.desktop$/, "").replace(/[^A-Za-z0-9_.]/g, "_").slice(0, 60) || "app"
        return `app-anoshell-${id}-${Date.now().toString(16)}${Math.floor(Math.random() * 0xffff).toString(16)}.scope`
    }

    /// Start an app (argv) the way this system supports; every user-facing
    /// launch goes through here. `name` names its systemd unit.
    function launch(command, workingDirectory, name): bool {
        if (!Array.isArray(command) || command.length === 0) return false
        const argv = root.launchMode === "systemd"
            ? ["systemd-run", "--user", "--scope", "--quiet", "--collect", "--slice=app.slice",
               `--unit=${root._unitName(name ?? command[0])}`, "--"].concat(command)
            : root.launchMode === "setsid" ? ["setsid"].concat(command) : command
        Quickshell.execDetached(workingDirectory ? { command: argv, workingDirectory: workingDirectory } : argv)
        return true
    }
    /// A desktop entry, in the default terminal when it asks for one.
    function launchEntry(entry): bool {
        if (!entry) return false
        let cmd = entry.command
        if (entry.runInTerminal) {
            const term = root.command("terminal")
            if (term.length) cmd = term.concat(root.terminalArgs(term[0], ["-e"].concat(cmd)))
        }
        return root.launch(cmd, entry.workingDirectory, entry.id)
    }

    IpcHandler {
        target: "apps"
        function run(kind: string): void { root.run(kind, []) }
        function open(kind: string, arg: string): void { root.run(kind, [arg]) }
        /// How apps are launched here: systemd | setsid | plain.
        function launchMode(): string { return root.launchMode }
    }
}
