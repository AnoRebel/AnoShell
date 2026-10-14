pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs
import qs.modules.common

// Anod — the shell's client for the anod daemon ($XDG_RUNTIME_DIR/ano/anod.sock,
// NDJSON, see anod/internal/ipc). The shell never depends on it: without anod
// `available` is false and daemon features show as unavailable. There is no
// polling: the socket directory is watched (inotify) and a connect is tried
// at startup and whenever anod creates or removes its socket.
//
// It also reports shell-owned events (lock, theme mode, Wi-Fi, battery, …) to
// anod, which runs the user's hooks (`hooks.*` in config.json).
Singleton {
    id: root

    readonly property int apiVersion: 1
    readonly property string socketPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/ano/anod.sock`
    property bool available: false
    property string version: ""
    property string error: ""     // last version/protocol problem ("" when fine)
    signal event(string name, var data)

    // call(method, params, cb(result, error)) — false when anod is unavailable.
    function call(method, params, cb) {
        if (!root.available) { if (cb) cb(null, { code: "unavailable", message: "anod is not running" }); return false }
        root._send(method, params, cb)
        return true
    }
    // Fire-and-forget shell event (dropped while anod is unavailable).
    function emit(name, data) { root.call("event.emit", { event: name, data: data ?? {} }) }

    property int _nextId: 0
    property var _pending: ({})
    property bool _versionBlocked: false
    property int _retries: 0
    property bool _startedSent: false

    function _send(method, params, cb) {
        const id = ++root._nextId
        if (cb) root._pending[id] = cb
        sock.write(JSON.stringify({ v: root.apiVersion, id, method, params: params ?? {} }) + "\n")
        sock.flush()
    }

    function _onLine(line) {
        let msg
        try { msg = JSON.parse(line) } catch (e) { console.warn(`[anod] bad line: ${line}`); return }
        if (msg.event) { root.event(msg.event, msg.data ?? {}); return }
        const cb = root._pending[msg.id]
        delete root._pending[msg.id]
        if (cb) cb(msg.result ?? null, msg.error ?? null)
    }

    function _handshake() {
        // Subscribing doubles as the version check.
        root._send("subscribe", {}, (res, err) => {
            if (err?.code === "version_mismatch") {
                root._versionBlocked = true
                root.error = err.message
                sock.connected = false
                Quickshell.execDetached(["notify-send", "-a", "ano", "anod version mismatch", err.message])
                return
            }
            if (err) { root.error = err.message; return }
            root.error = ""
            root.available = true
            root._send("version", {}, r => { root.version = r?.version ?? "" })
            if (!root._startedSent) { root._startedSent = true; root.emit("started", {}) }
        })
    }

    Socket {
        id: sock
        path: root.socketPath
        parser: SplitParser { onRead: line => root._onLine(line) }
        onConnectedChanged: {
            if (connected) { root._handshake(); return }
            root.available = false
            root.version = ""
            const pending = root._pending
            root._pending = {}
            for (const id in pending) pending[id](null, { code: "unavailable", message: "anod disconnected" })
        }
    }
    // Connect attempts: a few quick tries (the socket file appears just before
    // anod listens), then wait for the next change in the socket directory.
    function _tryConnect(retries) {
        if (sock.connected || root._versionBlocked) return
        root._retries = retries
        sock.connected = true
        retryTimer.restart()
    }
    Timer {
        id: retryTimer
        interval: 600
        onTriggered: {
            if (sock.connected || root._versionBlocked || root._retries <= 0) return
            root._retries--
            sock.connected = true
            retryTimer.restart()
        }
    }
    // FolderListModel doesn't list sockets, but it reloads on every change in the
    // directory, which is exactly the "anod (re)started or stopped" signal.
    readonly property string _socketDir: root.socketPath.substring(0, root.socketPath.lastIndexOf("/"))
    FolderListModel {
        id: dirWatch
        showDirs: false
        nameFilters: ["anod.sock"]
        readonly property real createdAt: Date.now()
        // Loads during startup get single attempts (no retry burst).
        // Later loads mean the directory changed: anod (re)started or stopped.
        onStatusChanged: if (status === FolderListModel.Ready) root._tryConnect(Date.now() - createdAt > 2000 ? 3 : 0)
    }
    // anod creates the same 0700 directory; making it here lets the watch start
    // before anod has ever run.
    Process {
        running: true
        command: ["mkdir", "-p", "-m", "700", root._socketDir]
        onExited: dirWatch.folder = "file://" + root._socketDir
    }

    IpcHandler {
        target: "anod"
        function status(): string {
            return JSON.stringify({ available: root.available, version: root.version, error: root.error, socket: root.socketPath })
        }
    }

    // ── Shell events → anod hooks ───────────────────────────────────────────
    function _mode() { return Appearance.m3colors.darkmode ? "dark" : "light" }
    Connections {
        target: Appearance.m3colors
        function onDarkmodeChanged() { root.emit("theme_mode_changed", { themeMode: root._mode() }) }
    }
    Connections {
        target: Config.options?.background ?? null
        function onWallpaperPathChanged() {
            root.emit("wallpaper_changed", { wallpaper: Config.options.background.wallpaperPath, themeMode: root._mode() })
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { root.emit(GlobalStates.screenLocked ? "session_locked" : "session_unlocked", {}) }
    }
    Connections {
        target: Network
        function onWifiEnabledChanged() { root.emit("wifi_changed", { wifi: Network.wifiEnabled ? "on" : "off" }) }
    }
    Connections {
        target: BluetoothStatus
        function onEnabledChanged() { root.emit("bluetooth_changed", { bluetooth: BluetoothStatus.enabled ? "on" : "off" }) }
    }
    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            const p = PowerProfiles.profile
            root.emit("power_profile_changed", { powerProfile: p === PowerProfile.PowerSaver ? "power-saver"
                : p === PowerProfile.Performance ? "performance" : "balanced" })
        }
    }

    // Battery: fires on charge-state changes and when crossing hooks.batteryThreshold.
    readonly property string batteryState: !Battery.available ? "" : Battery.isCharging ? "charging"
        : Battery.isPluggedIn ? "full" : "discharging"
    readonly property bool batteryLow: Battery.available
        && Math.round(Battery.percentage * 100) <= (Config.options?.hooks?.batteryThreshold ?? 20)
    function _emitBattery() {
        if (!Battery.available) return
        root.emit("battery_changed", { batteryPercent: Math.round(Battery.percentage * 100),
            batteryState: root.batteryState, batteryLow: root.batteryLow ? "true" : "false" })
    }
    onBatteryStateChanged: root._emitBattery()
    onBatteryLowChanged: root._emitBattery()
}
