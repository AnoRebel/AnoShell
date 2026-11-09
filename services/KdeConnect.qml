pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * KDE Connect (spec system-tools "KDE Connect"; kdeConnect.*, off by
 * default): paired phones with reachability and battery, and ring, ping,
 * share, clipboard and pairing. Talks to kdeconnectd on the session bus; the
 * shell never starts it. Informed by DMS's DankKDEConnect plugin (MIT).
 *
 * Signal-driven: one `gdbus monitor` on org.kde.kdeconnect (under a
 * parent-death signal) and a refetch of only the device a signal names; no
 * polling. Calls go through `busctl --json` with a 5 s timeout, one at a
 * time, so a daemon that owns its name but doesn't answer shows as
 * "not answering" instead of stalling anything. Values (URLs, text) are
 * process arguments, never shell strings.
 */
Singleton {
    id: root

    readonly property bool enabled: Config.options?.kdeConnect?.enable ?? false
    // "off" | "missing" (not on the bus) | "hung" (doesn't answer) | "ok"
    property string daemon: "off"
    // [{ id, name, type, reachable, paired, pairRequested, pairRequestedByPeer, charge (-1 unknown), charging }]
    property var devices: []
    readonly property var device: {
        const want = Config.options?.kdeConnect?.device ?? ""
        const paired = root.devices.filter(d => d.paired)
        return paired.find(d => d.id === want) ?? paired.find(d => d.reachable) ?? paired[0] ?? null
    }

    readonly property string _dest: "org.kde.kdeconnect"
    readonly property string _base: "/modules/kdeconnect"

    // ── Calls (one at a time) ───────────────────────────────────────────
    property var _queue: []
    property var _current: null
    function _call(path, iface, method, sig, args, cb) {
        // "--": busctl reorders arguments, so a value starting with "-" would be read as an option.
        const argv = ["busctl", "--user", "--json=short", "--timeout=5", "--", "call", root._dest, path, iface, method]
        if (sig) argv.push(sig, ...args.map(a => typeof a === "boolean" ? (a ? "true" : "false") : String(a)))
        root._queue = root._queue.concat([{ argv, cb }])
        root._next()
    }
    function _props(path, iface, cb) {
        root._call(path, "org.freedesktop.DBus.Properties", "GetAll", "s", [iface], (r, err) => {
            if (err) { cb(null, err); return }
            const out = {}
            const m = r?.data?.[0] ?? {}
            for (const k of Object.keys(m)) out[k] = m[k]?.data
            cb(out, "")
        })
    }
    function _next() {
        if (root._current || root._queue.length === 0) return
        root._current = root._queue[0]
        root._queue = root._queue.slice(1)
        caller.command = root._current.argv
        caller.running = true
        watchdog.restart()
    }
    // busctl gives up after 5 s; a call still open at 8 s never started (a
    // missing busctl never emits exited): end it so the queue keeps moving.
    Timer {
        id: watchdog
        interval: 8000
        onTriggered: if (root._current) { caller.running = false; root._finish(-1) }
    }
    Process {
        id: caller
        stdout: StdioCollector { id: callOut }
        stderr: StdioCollector { id: callErr }
        onExited: code => root._finish(code)
    }
    function _finish(code) {
        {
            if (!root._current) return
            watchdog.stop()
            const c = root._current
            root._current = null
            let r = null, err = ""
            // A method with no return value prints nothing.
            if (code === 0) { try { r = callOut.text.trim() ? JSON.parse(callOut.text) : null } catch (e) { err = "bad reply" } }
            else err = callErr.text.trim() || `busctl exited ${code}`
            if (code === -1) err = "busctl couldn't run"
            if (/timed out/i.test(err)) root._hung()
            if (root.enabled) try { c?.cb?.(r, err) } catch (e) { console.warn("[KdeConnect]", e) }
            root._next()
        }
    }

    // ── State ───────────────────────────────────────────────────────────
    function refresh() {
        if (!root.enabled) return
        root._call(root._base, "org.kde.kdeconnect.daemon", "devices", "bb", [false, false], (r, err) => {
            if (err) {
                if (/not provided by any|ServiceUnknown|was not provided/i.test(err)) { root.daemon = "missing"; root.devices = [] }
                return
            }
            root.daemon = "ok"
            const ids = r?.data?.[0] ?? []
            root.devices = root.devices.filter(d => ids.includes(d.id))
            for (const id of ids) root._refreshDevice(id)
        })
    }
    function _hung() {
        root.daemon = "hung"
        root._queue = [] // everything behind it would time out too
        retry.restart()
    }
    function _put(id, patch) {
        const i = root.devices.findIndex(d => d.id === id)
        const base = i >= 0 ? root.devices[i] : { id, name: id, type: "phone", reachable: false, paired: false,
            pairRequested: false, pairRequestedByPeer: false, charge: -1, charging: false }
        const next = Object.assign({}, base, patch)
        const list = root.devices.slice()
        if (i >= 0) list[i] = next; else list.push(next)
        if (!base.pairRequestedByPeer && next.pairRequestedByPeer) root._askPairing(next)
        root.devices = list
    }
    function _refreshDevice(id) {
        if (!/^[A-Za-z0-9_]+$/.test(id)) return
        const path = `${root._base}/devices/${id}`
        root._props(path, "org.kde.kdeconnect.device", (p, err) => {
            if (!p) return
            root._put(id, { name: p.name ?? id, type: p.type ?? "phone", reachable: !!p.isReachable, paired: !!p.isPaired,
                pairRequested: !!p.isPairRequested, pairRequestedByPeer: !!p.isPairRequestedByPeer })
            if (p.isPaired && p.isReachable)
                root._props(`${path}/battery`, "org.kde.kdeconnect.device.battery", b => {
                    if (b) root._put(id, { charge: b.charge ?? -1, charging: !!(b.isCharging ?? b.charging) })
                })
        })
    }

    // ── Actions (the selected device unless one is given) ───────────────
    function _act(plugin, iface, method, sig, args, id) {
        const d = id ?? root.device?.id
        if (!d || !/^[A-Za-z0-9_]+$/.test(d)) return
        root._call(`${root._base}/devices/${d}${plugin ? "/" + plugin : ""}`, iface, method, sig, args ?? [], (r, err) => {
            if (err) Quickshell.execDetached(["notify-send", "-a", "AnoShell", "KDE Connect", `${method} failed: ${err}`])
        })
    }
    function ring(id) { root._act("findmyphone", "org.kde.kdeconnect.device.findmyphone", "ring", "", [], id) }
    function ping(id) { root._act("ping", "org.kde.kdeconnect.device.ping", "sendPing", "", [], id) }
    function sendClipboard(id) { root._act("clipboard", "org.kde.kdeconnect.device.clipboard", "sendClipboard", "", [], id) }
    function shareUrl(url, id) { if (url) root._act("share", "org.kde.kdeconnect.device.share", "shareUrl", "s", [url], id) }
    function shareText(text, id) { if (text) root._act("share", "org.kde.kdeconnect.device.share", "shareText", "s", [text], id) }
    function sendFile(path, id) { if (path) root.shareUrl(path.startsWith("file://") ? path : "file://" + path, id) }
    // A file picked in zenity, sent to the device.
    function pickAndSend(id) {
        if (picker.running) return
        picker.deviceId = id ?? root.device?.id ?? ""
        picker.running = true
    }
    Process {
        id: picker
        property string deviceId: ""
        command: ["zenity", "--file-selection", "--title=Send to phone"]
        stdout: StdioCollector { onStreamFinished: { const p = text.trim(); if (p) root.sendFile(p, picker.deviceId) } }
    }
    function acceptPairing(id) { root._act("", "org.kde.kdeconnect.device", "acceptPairing", "", [], id) }
    function rejectPairing(id) { root._act("", "org.kde.kdeconnect.device", "cancelPairing", "", [], id) }

    // A pairing request: a notification with Accept / Reject.
    // One notification (and process) per request, each answering for its own
    // device; "--" so a device name starting with "-" isn't read as an option.
    function _askPairing(d) {
        const p = pairAsk.createObject(root, { deviceId: d.id,
            command: ["timeout", "120", "notify-send", "-a", "AnoShell", "-w", "-A", "accept=Accept", "-A", "reject=Reject", "--",
                "KDE Connect", `${d.name} wants to pair`] })
        p.running = true
    }
    Component {
        id: pairAsk
        Process {
            id: ask
            property string deviceId: ""
            stdout: StdioCollector {
                onStreamFinished: {
                    const a = text.trim()
                    if (a === "accept") root.acceptPairing(ask.deviceId)
                    else if (a === "reject") root.rejectPairing(ask.deviceId)
                }
            }
            onExited: ask.destroy()
        }
    }

    // ── Signals ─────────────────────────────────────────────────────────
    // gdbus monitor lines: "/modules/kdeconnect/devices/<id>/battery: org.kde.…refreshed (…)",
    // plus "The name org.kde.kdeconnect is owned by …" / "… does not have an owner".
    property var _dirty: ({})
    function _onLine(line) {
        if (line.includes("does not have an owner")) { root.daemon = "missing"; root.devices = []; return }
        if (line.includes("is owned by")) { root.daemon = "ok"; root.refresh(); return }
        const m = line.match(/^\/modules\/kdeconnect\/devices\/([A-Za-z0-9_]+)/)
        if (m) { const d = Object.assign({}, root._dirty); d[m[1]] = true; root._dirty = d; settle.restart(); return }
        if (/^\/modules\/kdeconnect: /.test(line)) { root._dirty = { "*": true }; settle.restart() }
    }
    // Signals come in bursts (a reconnect sends several): refetch once.
    Timer {
        id: settle
        interval: 300
        onTriggered: {
            const d = root._dirty
            root._dirty = ({})
            if (d["*"]) root.refresh()
            else for (const id of Object.keys(d)) root._refreshDevice(id)
        }
    }
    Process {
        id: monitor
        running: root.enabled
        command: ["setpriv", "--pdeathsig", "TERM", "--", "gdbus", "monitor", "--session", "--dest", root._dest]
        stdout: SplitParser { onRead: line => { root._monFails = 0; root._onLine(line) } }
        // gdbus exits if the bus restarts: watch again, giving up after a few
        // quick failures (no gdbus: ano doctor says so).
        onRunningChanged: if (!running && root.enabled && ++root._monFails <= 5) remonitor.start()
    }
    property int _monFails: 0
    Timer { id: remonitor; interval: 5000; onTriggered: monitor.running = root.enabled }
    // A hung daemon: look again now and then (only while it's hung).
    Timer { id: retry; interval: 60000; onTriggered: if (root.enabled && root.daemon === "hung") root.refresh() }

    onEnabledChanged: {
        remonitor.stop(); retry.stop(); root._monFails = 0
        monitor.running = root.enabled
        if (root.enabled) root.refresh()
        else { root.daemon = "off"; root.devices = []; root._queue = [] }
    }
    Component.onCompleted: if (root.enabled) root.refresh()

    IpcHandler {
        target: "kdeConnect"
        function status(): string { return JSON.stringify({ daemon: root.daemon, device: root.device, devices: root.devices }) }
        function ring(): void { root.ring() }
        function ping(): void { root.ping() }
        function sendClipboard(): void { root.sendClipboard() }
        function refresh(): void { root.refresh() }
    }
}
