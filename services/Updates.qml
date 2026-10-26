pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Pending package updates (updates.enable, Arch: checkupdates from
 * pacman-contrib, which syncs a private copy of the databases, plus
 * `<aur helper> -Qua` when paru or yay is installed). Checked a minute after
 * start, then every updates.intervalMin; never runs the update itself:
 * update() opens updates.command (default: the AUR helper or
 * `sudo pacman -Syu`) in the user's terminal.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.updates?.enable ?? false
    readonly property int intervalMin: Math.max(15, Config.options?.updates?.intervalMin ?? 120)
    readonly property string customCommand: Config.options?.updates?.command ?? ""

    property int repoCount: 0
    property int aurCount: 0
    readonly property int count: root.repoCount + root.aurCount
    property var packages: []       // ["name old -> new", …], repo then AUR
    property bool checking: false
    property string error: ""
    property real lastChecked: 0

    function check() {
        if (!root.enabled || checker.running) return
        root.checking = true
        checker.running = true
    }

    // Opens the update in the terminal; the window stays until Enter.
    function update() {
        const helper = DefaultApps.aurHelper
        const cmd = root.customCommand ? ["sh", "-c", root.customCommand]
            : helper ? [helper, "-Syu"] : ["sudo", "pacman", "-Syu"]
        DefaultApps.run("terminal", ["-e", "sh", "-c", '"$@"; printf "\\nDone. Press Enter to close. "; read _', "sh"].concat(cmd))
        recheck.restart()
    }

    Process {
        id: checker
        // Fixed script; exit 2 from checkupdates means "none".
        command: ["sh", "-c", "checkupdates; c=$?; [ $c -le 2 ] || echo \"!checkupdates failed ($c)\"; echo '---'; "
            + "for h in paru yay; do command -v $h >/dev/null 2>&1 && { $h -Qua 2>/dev/null; break; }; done; true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [repo, aur] = (this.text || "").split(/^---$/m)
                const lines = s => (s ?? "").split("\n").map(l => l.trim()).filter(l => l && !l.startsWith("!"))
                const fail = (repo ?? "").split("\n").find(l => l.startsWith("!"))
                root.error = fail ? fail.slice(1) : ""
                const r = lines(repo), a = lines(aur)
                root.repoCount = r.length
                root.aurCount = a.length
                root.packages = r.concat(a.map(l => l + " (AUR)"))
                root.lastChecked = Date.now()
                root.checking = false
            }
        }
    }

    Timer {
        id: tick
        running: root.enabled && Config.ready
        interval: 60 * 1000          // first check a minute after start
        repeat: true
        onTriggered: { interval = root.intervalMin * 60 * 1000; root.check() }
    }
    // After an update ran in the terminal, look again a little later.
    Timer { id: recheck; interval: 5 * 60 * 1000; onTriggered: root.check() }

    IpcHandler {
        target: "updates"
        function check(): void { root.check() }
        function update(): void { root.update() }
        function status(): string {
            return JSON.stringify({ count: root.count, repo: root.repoCount, aur: root.aurCount, error: root.error, checking: root.checking })
        }
    }
}
