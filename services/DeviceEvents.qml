pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Device events as short pills (or the OSD without a pill): Bluetooth
 * devices connecting, USB devices plugged/unplugged, the audio output
 * changing, displays added/removed. Wi-Fi changes and charging already have
 * their own indicators (osd.indicators.network, the charging transient).
 *
 * Sources the shell already has (Bluetooth, PipeWire, screens) plus one
 * `udevadm monitor` for USB devices while deviceEvents.usb is on; nothing
 * polls. The first seconds after start are quiet, and the same message
 * twice within a few seconds (one plug-in, several udev events) shows once.
 * (Idea from Ryoku's DeviceEvents.)
 *
 *   event(label, icon)  — consumed by the OSD, which hands it to the pill
 */
Singleton {
    id: root

    readonly property var cfg: Config.options?.deviceEvents ?? ({})
    readonly property bool enabled: Config.ready && (root.cfg.enable ?? true)
    function _on(kind) { return root.enabled && (root.cfg[kind] ?? true) }

    signal event(string label, string icon)

    property bool _armed: false
    Timer { running: Config.ready; interval: 6000; onTriggered: root._armed = true }
    property var _recent: ({})          // label → time shown
    function _emit(kind, label, icon) {
        if (!root._armed || !root._on(kind) || !label) return
        const now = Date.now()
        if (now - (root._recent[label] ?? 0) < 4000) return
        const r = {}
        for (const k in root._recent) if (now - root._recent[k] < 4000) r[k] = root._recent[k]
        r[label] = now
        root._recent = r
        root.event(label, icon)
    }

    // ── Bluetooth ────────────────────────────────────────────────────────
    property var _bt: []                // connected addresses last seen
    function _btSync() {
        const devs = BluetoothStatus.connectedDevices ?? []
        const now = devs.map(d => d.address)
        if (root._armed) {
            for (const d of devs) if (!root._bt.includes(d.address))
                root._emit("bluetooth", `${d.name || d.address} connected`, "bluetooth_connected")
            for (const a of root._bt) if (!now.includes(a))
                root._emit("bluetooth", `${root._btNames[a] ?? a} disconnected`, "bluetooth_disabled")
        }
        const names = {}
        for (const d of devs) names[d.address] = d.name || d.address
        root._btNames = Object.assign({}, root._btNames, names)
        root._bt = now
    }
    property var _btNames: ({})
    Connections {
        target: BluetoothStatus
        enabled: root._on("bluetooth")
        function onConnectedDevicesChanged() { root._btSync() }
    }

    // ── Audio output ─────────────────────────────────────────────────────
    property string _sink: ""
    Connections {
        target: Audio
        enabled: root._on("audio")
        function onSinkChanged() {
            const name = Audio.sink ? (Audio.friendlyDeviceName(Audio.sink) ?? Audio.sink.description ?? "") : ""
            if (name && root._sink && name !== root._sink) root._emit("audio", `Output: ${name}`, "speaker")
            root._sink = name
        }
    }

    // ── Displays ─────────────────────────────────────────────────────────
    property var _screens: []
    Connections {
        target: Quickshell
        enabled: root._on("displays")
        function onScreensChanged() {
            const now = Quickshell.screens.map(s => s.name)
            if (root._screens.length) {
                for (const n of now) if (!root._screens.includes(n)) root._emit("displays", `Display ${n} connected`, "desktop_windows")
                for (const n of root._screens) if (!now.includes(n)) root._emit("displays", `Display ${n} disconnected`, "desktop_access_disabled")
            }
            root._screens = now
        }
    }

    // ── USB ──────────────────────────────────────────────────────────────
    // `--property` prints a "UDEV  [time] action path (subsystem)" header,
    // then KEY=VALUE lines. An event ends at the next header, a blank line,
    // or a short quiet spell.
    property var _usb: null
    function _usbFlush() {
        const e = root._usb
        root._usb = null
        if (!e || (e.ACTION !== "add" && e.ACTION !== "remove")) return
        const vendor = e.ID_VENDOR_FROM_DATABASE || e.ID_VENDOR || ""
        const model = e.ID_MODEL_FROM_DATABASE || e.ID_MODEL || ""
        // Hubs come and go with docks and on resume: not news.
        if (/\bhub\b/i.test(model) || (e.ID_USB_INTERFACES ?? "").startsWith(":0900")) return
        const what = [vendor, model].filter(s => s).join(" ").replace(/_/g, " ") || "USB device"
        root._emit("usb", `${what} ${e.ACTION === "add" ? "plugged in" : "removed"}`, e.ACTION === "add" ? "usb" : "usb_off")
    }
    function _usbLine(line) {
        if (line.startsWith("UDEV") || line.trim() === "") {
            root._usbFlush()
            if (line.startsWith("UDEV")) root._usb = {}
            return
        }
        const i = line.indexOf("=")
        if (root._usb && i > 0) root._usb[line.slice(0, i)] = line.slice(i + 1)
        usbQuiet.restart()
    }
    Timer { id: usbQuiet; interval: 150; onTriggered: root._usbFlush() }
    Process {
        running: root._on("usb")
        command: ["setpriv", "--pdeathsig", "TERM", "--", "udevadm", "monitor", "--udev", "--property", "--subsystem-match=usb/usb_device"]
        stdout: SplitParser { onRead: line => root._usbLine(line) }
    }

    IpcHandler {
        target: "deviceEvents"
        // Shows a sample event (for checking the pill/OSD look).
        function test(label: string): void { root.event(label || "Test device connected", "devices") }
        function status(): string {
            return JSON.stringify({ enabled: root.enabled, armed: root._armed, sink: root._sink,
                bluetooth: root._bt.length, screens: root._screens })
        }
    }

    Component.onCompleted: {
        root._btSync()
        root._screens = Quickshell.screens.map(s => s.name)
        root._sink = Audio.sink ? (Audio.friendlyDeviceName(Audio.sink) ?? "") : ""
    }
}
