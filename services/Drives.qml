pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Removable drives (spec system-integration): USB sticks, SD cards and other
 * hot-pluggable disks with their partitions, mount/unmount, eject (unmount
 * everything, then power off) and whether data is still being written.
 *
 * Listed with `lsblk -J`, refreshed on udev block events (`udevadm monitor`),
 * so nothing polls; actions go through udisks (`udisksctl`), device paths as
 * arguments. The write rate comes from /sys/block/<disk>/stat and inflight,
 * read every second only while a drive is busy or a panel watches.
 *
 * drives: [{ name, path, model, size, tran, parts: [{ name, path, label,
 *            fstype, size, mountpoints }] }]
 */
Singleton {
    id: root

    property var drives: []
    readonly property bool any: root.drives.length > 0
    property var busy: ({})           // disk name → "mounting" | "unmounting" | "ejecting"
    property var writing: ({})        // disk name → { rate (B/s), inflight }
    property real pendingBytes: 0     // dirty + writeback, system-wide
    property string lastError: ""

    // ── Listing ──────────────────────────────────────────────────────────
    property bool _loaded: false
    function refresh() { if (lsblk.running) lsblk.again = true; else lsblk.running = true }
    Process {
        id: lsblk
        property bool again: false
        running: true
        command: ["lsblk", "-J", "-b", "-o", "NAME,PATH,TYPE,RM,HOTPLUG,TRAN,MODEL,VENDOR,SIZE,LABEL,FSTYPE,MOUNTPOINTS"]
        stdout: StdioCollector {
            onStreamFinished: {
                let devs = []
                try { devs = JSON.parse(text).blockdevices ?? [] } catch (e) { console.warn(`[Drives] lsblk: ${e}`) }
                const next = devs.filter(d => d.type === "disk" && (d.rm || d.hotplug)).map(d => ({
                    name: d.name, path: d.path, size: d.size, tran: d.tran ?? "",
                    model: [String(d.vendor ?? "").trim(), String(d.model ?? "").trim()].filter(x => x).join(" ") || d.name,
                    parts: (d.children ?? []).filter(p => p.type === "part" || p.type === "crypt").map(p => ({
                        name: p.name, path: p.path, label: p.label ?? "", fstype: p.fstype ?? "", size: p.size,
                        mountpoints: (p.mountpoints ?? []).filter(m => !!m) }))
                }))
                if (root._loaded) {
                    for (const d of next)
                        if (!root.drives.some(o => o.name === d.name)) root._notify("Drive connected", `${d.model} · ${root.formatSize(d.size)}`)
                }
                root.drives = next
                root._loaded = true
            }
        }
        onExited: if (again) { again = false; running = true }
    }
    // udev reports disks and partitions coming, going and changing.
    Process {
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", "udevadm", "monitor", "--udev", "--subsystem-match=block"]
        stdout: SplitParser { onRead: line => { if (/\b(add|remove|change)\b/.test(line)) settle.restart() } }
    }
    Timer { id: settle; interval: 400; onTriggered: root.refresh() }

    // ── Actions ──────────────────────────────────────────────────────────
    function mount(part) { root._run(part.name, "mounting", ["udisksctl", "mount", "-b", part.path]) }
    function unmount(part) { root._run(part.name, "unmounting", ["udisksctl", "unmount", "-b", part.path]) }
    /// Unmount every mounted partition, then power the drive off.
    function eject(drive) {
        const mounted = drive.parts.filter(p => p.mountpoints.length > 0).map(p => p.path)
        root._run(drive.name, "ejecting", ["sh", "-c",
            'disk=$1; shift; for p; do udisksctl unmount -b "$p" || exit 1; done; udisksctl power-off -b "$disk"',
            "sh", drive.path].concat(mounted))
    }
    function _run(name, what, argv) {
        if (root.busy[name]) return
        root._setBusy(name, what)
        root.lastError = ""
        actionComp.createObject(root, { name: name, what: what, command: argv })
    }
    function _setBusy(name, what) {
        const b = Object.assign({}, root.busy)
        if (what) b[name] = what; else delete b[name]
        root.busy = b
    }
    Component {
        id: actionComp
        Process {
            id: act
            property string name
            property string what
            running: true
            stderr: StdioCollector { id: err }
            onExited: code => {
                root._setBusy(act.name, "")
                if (code !== 0) {
                    root.lastError = err.text.trim().split("\n").pop() || `${act.what} failed (${code})`
                    console.warn(`[Drives] ${act.what} ${act.name}: exit ${code}: ${err.text.trim()}`)
                    root._notify(`Drive: ${act.what} failed`, root.lastError)
                } else if (act.what === "ejecting") {
                    root._notify("Safe to remove", "The drive is powered off.")
                }
                root.refresh()
                act.destroy()
            }
        }
    }

    // ── Writing, while it matters ────────────────────────────────────────
    property int _watchers: 0
    /// A panel showing drives: read the write rate while it's open.
    function watch(on) { root._watchers = Math.max(0, root._watchers + (on ? 1 : -1)); if (on) root.refresh() }
    readonly property bool _sampling: root.any && (root._watchers > 0 || Object.keys(root.busy).length > 0
        || Object.keys(root.writing).length > 0)
    property var _last: ({})          // disk → { sectors, at }
    Timer {
        interval: 1000; repeat: true; triggeredOnStart: true
        running: root._sampling
        onTriggered: if (!stat.running) {
            stat.command = ["sh", "-c",
                'for d; do printf "%s %s %s\\n" "$d" "$(cat "/sys/block/$d/stat")" "$(cat "/sys/block/$d/inflight")"; done; grep -E "^(Dirty|Writeback):" /proc/meminfo',
                "sh"].concat(root.drives.map(d => d.name))
            stat.running = true
        }
        onRunningChanged: if (!running) { root.writing = ({}); root._last = ({}) }
    }
    Process {
        id: stat
        stdout: StdioCollector {
            onStreamFinished: {
                const now = Date.now(), w = {}, last = {}
                let pending = 0
                for (const line of text.split("\n")) {
                    const f = line.trim().split(/\s+/)
                    if (f[0] === "Dirty:" || f[0] === "Writeback:") { pending += Number(f[1]) * 1024; continue }
                    if (f.length < 12) continue
                    // stat: field 7 = sectors written; inflight: reads writes (last two).
                    const sectors = Number(f[7]), inflight = Number(f[f.length - 1])
                    last[f[0]] = { sectors: sectors, at: now }
                    const prev = root._last[f[0]]
                    const raw = prev ? (sectors - prev.sectors) * 512 / Math.max(0.001, (now - prev.at) / 1000) : 0
                    // Smoothed: a stick writes in bursts (0–8 MB/s second to second).
                    const rate = 0.4 * raw + 0.6 * (root.writing[f[0]]?.rate ?? raw)
                    if (raw > 0 || inflight > 0) w[f[0]] = { rate: rate, inflight: inflight }
                }
                root._last = last
                root.writing = w
                root.pendingBytes = pending
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────
    function _part(path) {
        for (const d of root.drives) for (const p of d.parts) if (p.path === path) return p
        return null
    }
    function formatSize(bytes) {
        const u = ["B", "KB", "MB", "GB", "TB"]
        let v = Number(bytes) || 0, i = 0
        while (v >= 1000 && i < u.length - 1) { v /= 1000; i++ }
        return `${v >= 10 || i === 0 ? Math.round(v) : v.toFixed(1)} ${u[i]}`
    }
    function _notify(title, body) {
        if (!(Config.options?.drives?.notify ?? true)) return
        Quickshell.execDetached(["notify-send", "-a", "AnoShell", "-i", "drive-removable-media", title, body])
    }

    IpcHandler {
        target: "drives"
        /// The drives as JSON, with busy and writing state.
        function list(): string { return JSON.stringify({ drives: root.drives, busy: root.busy, writing: root.writing, pendingBytes: root.pendingBytes, lastError: root.lastError }) }
        function watch(on: bool): void { root.watch(on) }
        /// Mount or unmount a partition by its device path (/dev/sda1).
        function mount(path: string): void { const p = root._part(path); if (p) root.mount(p) }
        function unmount(path: string): void { const p = root._part(path); if (p) root.unmount(p) }
        /// Unmount and power off a drive by its device path (/dev/sda).
        function eject(path: string): void { const d = root.drives.find(x => x.path === path); if (d) root.eject(d) }
    }
}
