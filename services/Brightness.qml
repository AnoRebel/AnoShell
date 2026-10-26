pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

/**
 * Brightness service. Supports brightnessctl (backlight) and ddcutil (DDC/CI for external monitors).
 * Compositor-agnostic — uses CompositorService for focused monitor detection.
 */
Singleton {
    id: root
    signal brightnessChanged()

    property var ddcMonitors: []
    readonly property list<BrightnessMonitor> monitors: Quickshell.screens.map(screen => monitorComp.createObject(root, { screen }))

    function getMonitorForScreen(screen): var {
        return monitors.find(m => m.screen === screen)
    }

    function increaseBrightness(): void {
        const focusedName = CompositorService.focusedMonitorName
        const monitor = monitors.find(m => focusedName === m.screen.name)
        if (monitor) monitor.setBrightness(monitor.brightness + 0.05)
    }

    function decreaseBrightness(): void {
        const focusedName = CompositorService.focusedMonitorName
        const monitor = monitors.find(m => focusedName === m.screen.name)
        if (monitor) monitor.setBrightness(monitor.brightness - 0.05)
    }

    reloadableId: "brightness"

    onMonitorsChanged: {
        ddcMonitors = []
        ddcProc.running = true
    }

    function initializeMonitor(i): void {
        if (i >= monitors.length) return
        monitors[i].initialize()
    }

    function ddcDetectFinished(): void {
        initializeMonitor(0)
    }

    Process {
        id: ddcProc
        // Only when ddcutil is installed (it's optional: external monitors).
        command: ["sh", "-c", "command -v ddcutil >/dev/null && exec ddcutil detect --brief"]
        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: data => {
                if (data.startsWith("Display ")) {
                    const lines = data.split("\n").map(l => l.trim())
                    const connLine = lines.find(l => l.startsWith("DRM connector:"))
                    const busLine = lines.find(l => l.startsWith("I2C bus:"))
                    if (connLine && busLine) {
                        root.ddcMonitors.push({
                            name: connLine.split("-").slice(1).join('-'),
                            busNum: busLine.split("/dev/i2c-")[1]
                        })
                    }
                }
            }
        }
        onExited: root.ddcDetectFinished()
    }

    Process {
        id: setProc
    }

    component BrightnessMonitor: QtObject {
        id: monitor
        required property var screen
        property bool isDdc
        property string busNum
        property int rawMaxBrightness: 100
        property real brightness
        property bool ready: false
        property bool animateChanges: !monitor.isDdc

        // Single onBrightnessChanged handler — fans out to both the
        // root-level signal (for UI consumers) and the debounced
        // setTimer (which actually pushes the value to the device).
        onBrightnessChanged: {
            if (!monitor.ready) return
            root.brightnessChanged()
            if (!monitor._fromFile) setTimer.restart()
        }

        // The kernel notifies actual_brightness on every change, whoever
        // made it, so this needs no polling.
        readonly property FileView backlightFile: FileView {
            path: monitor.backlightDir ? monitor.backlightDir + "/actual_brightness" : ""
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                const raw = parseInt(text())
                if (isNaN(raw) || !monitor.ready || monitor.setTimer.running) return
                const value = raw / monitor.rawMaxBrightness
                // Our own writes land on whole percents: ignore that rounding.
                if (Math.abs(value - monitor.brightness) <= 0.0101) return
                monitor._fromFile = true
                monitor.brightness = value
                monitor._fromFile = false
            }
        }

        function initialize() {
            monitor.ready = false
            const match = root.ddcMonitors.find(m => m.name === screen.name && !root.monitors.slice(0, root.monitors.indexOf(this)).some(mon => mon.busNum === m.busNum))
            isDdc = !!match
            busNum = match?.busNum ?? ""
            const device = Config.options.light.device
            initProc.command = isDdc
                ? ["ddcutil", "-b", busNum, "getvcp", "10", "--brief"]
                : ["brightnessctl", "-m"].concat(device ? ["-d", device] : ["-c", "backlight"], ["i"])
            initProc.running = true
        }

        // The backlight device brightnessctl picked; its actual_brightness is
        // watched so keys, firmware and other tools show up here too.
        property string backlightDir: ""
        property bool _fromFile: false

        readonly property Process initProc: Process {
            stdout: SplitParser {
                onRead: data => {
                    if (monitor.isDdc) {
                        // "VCP 10 C <current> <max>"
                        const parts = data.split(" ")
                        monitor.rawMaxBrightness = parseInt(parts[4] || "100")
                        monitor.brightness = parseInt(parts[3] || "0") / monitor.rawMaxBrightness
                    } else {
                        // "<device>,<class>,<current>,<percent>,<max>"
                        const parts = data.split(",")
                        if (parts.length < 5) return
                        monitor.rawMaxBrightness = parseInt(parts[4]) || 100
                        monitor.brightness = (parseInt(parts[2]) || 0) / monitor.rawMaxBrightness
                        monitor.backlightDir = `/sys/class/${parts[1]}/${parts[0]}`
                    }
                    monitor.ready = true
                }
            }
            onExited: (exitCode, exitStatus) => {
                initializeMonitor(root.monitors.indexOf(monitor) + 1)
            }
        }

        property var setTimer: Timer {
            interval: monitor.isDdc ? 300 : 0
            onTriggered: syncBrightness()
        }

        function syncBrightness() {
            const brightnessValue = Math.max(brightness, 0)
            if (isDdc) {
                const rawValueRounded = Math.max(Math.floor(brightnessValue * monitor.rawMaxBrightness), 1)
                setProc.exec(["ddcutil", "-b", busNum, "setvcp", "10", rawValueRounded])
            } else {
                const valuePercentNumber = Math.floor(brightnessValue * 100)
                let valuePercent = `${valuePercentNumber}%`
                if (valuePercentNumber === 0) valuePercent = "1"
                const device = Config.options.light.device
                const cmd = ["brightnessctl"]
                if (device) {
                    cmd.push("-d", device)
                } else {
                    cmd.push("--class", "backlight")
                }
                cmd.push("s", valuePercent, "--quiet")
                setProc.exec(cmd)
            }
        }

        function setBrightness(value): void {
            monitor.brightness = Math.max(0, Math.min(1, value))
        }
    }

    Component {
        id: monitorComp
        BrightnessMonitor {}
    }

    // IPC
    IpcHandler {
        target: "brightness"
        function increment(): void { root.increaseBrightness() }
        function decrement(): void { root.decreaseBrightness() }
        // Per screen: { screen, percent, ddc } (read-only, for scripts and tests).
        function status(): string {
            return JSON.stringify(root.monitors.map(m => ({ screen: m.screen.name, percent: Math.round(m.brightness * 100), ddc: m.isDdc })))
        }
    }

    GlobalShortcut {
        name: "brightnessIncrease"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }
    GlobalShortcut {
        name: "brightnessDecrease"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }
}
