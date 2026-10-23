pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Night light: warms the display through wlsunset (any compositor with
 * wlr-gamma-control: Hyprland, niri, sway).
 *
 *   nightLight.enable    the quick toggle: warm now, at nightTemp, whatever
 *                        the schedule says.
 *   nightLight.schedule  runs on its own while set:
 *                        "sun"   warm from sunset to sunrise where you are
 *                                (services/Location; waits until it's known)
 *                        "times" warm from `start` to `end` (HH:mm), fading
 *                                over `fade` minutes
 *                        "off"   only the toggle
 *
 * One wlsunset process, restarted when its arguments change. There's no
 * cross-compositor way to read the gamma back, so `active` is process state.
 */
Singleton {
    id: root

    readonly property var opts: Config.options?.nightLight
    readonly property bool enabled: opts?.enable ?? false
    readonly property string schedule: opts?.schedule ?? "off"
    readonly property int dayTemp: opts?.dayTemp ?? 6500
    readonly property int nightTemp: opts?.nightTemp ?? 4000
    // From Settings → Services → Location (services/Location.qml).
    readonly property real latitude: Location.latitude
    readonly property real longitude: Location.longitude
    readonly property string start: opts?.start ?? "20:00"
    readonly property string end: opts?.end ?? "07:00"
    readonly property int fade: opts?.fade ?? 30
    readonly property real gamma: opts?.gamma ?? 1.0
    readonly property var outputs: Array.from(opts?.outputs ?? [])

    readonly property bool scheduled: root.schedule === "sun" || root.schedule === "times"
    readonly property bool active: proc.running
    // For tooltips: "20:00–07:00" or "sunset–sunrise".
    readonly property string scheduleText: root.schedule === "times" ? `${root.start}–${root.end}`
        : root.schedule === "sun" ? "sunset–sunrise" : ""

    function toggle(): void {
        Config.setNestedValue("nightLight.enable", !root.enabled)
    }

    // HH:mm, 00:00–23:59
    function validTime(t: string): bool {
        return /^([01]\d|2[0-3]):[0-5]\d$/.test(t)
    }

    // Options every mode shares: gamma, and the monitors (-o each; none = all).
    readonly property var common: {
        const a = ["-g", String(root.gamma)]
        for (const o of root.outputs) a.push("-o", o)
        return a
    }
    readonly property var args: {
        const mode = root.modeArgs
        return mode.length ? ["wlsunset"].concat(mode, root.common) : []
    }
    readonly property var modeArgs: {
        if (root.enabled) // held at nightTemp: day and night 1 K apart, so the time doesn't matter
            return ["-T", String(root.nightTemp + 1), "-t", String(root.nightTemp),
                    "-l", "0", "-L", "0"]
        if (root.schedule === "sun" && Location.valid)
            return ["-T", String(root.dayTemp), "-t", String(root.nightTemp),
                    "-l", String(root.latitude), "-L", String(root.longitude)]
        if (root.schedule === "times" && root.validTime(root.start) && root.validTime(root.end))
            return ["-T", String(root.dayTemp), "-t", String(root.nightTemp),
                    "-s", root.start, "-S", root.end, "-d", String(Math.max(0, root.fade) * 60)]
        return []
    }

    Process {
        id: proc
        command: root.args
        running: Config.ready && root.args.length > 0
        onCommandChanged: if (running) { running = false; Qt.callLater(() => running = Qt.binding(() => Config.ready && root.args.length > 0)) }
    }
}
