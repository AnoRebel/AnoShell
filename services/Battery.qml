pragma Singleton

import qs.services
import qs.modules.common
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import Quickshell.Io

/**
 * Battery service using UPower. Provides charge state, health,
 * low/critical/suspend/full notifications, and automatic suspend.
 */
Singleton {
    id: root
    property bool available: UPower.displayDevice.isLaptopBattery
    property var chargeState: UPower.displayDevice.state
    property bool isCharging: chargeState === UPowerDeviceState.Charging
    // UPower's line-power flag: a charge limit (state "pending-charge" or
    // "discharging" at the threshold on some firmware) still counts as plugged in.
    property bool isPluggedIn: !UPower.onBattery
    // Readings before the device is ready (startup, resume) are defaults, so
    // warnings wait until it is ready and has settled for 2 s.
    property bool settled: false
    Timer {
        running: UPower.displayDevice.ready
        interval: 2000
        onTriggered: root.settled = true
    }
    // Whole percents (0..1 in 0.01 steps): UPower reports fractional changes every
    // few seconds while charging, and each one re-animated every battery ring.
    // A 0% reading in the Unknown state (boot, resume, a charger being moved on
    // some firmware) is no reading: keep the last real one, so it can't
    // trigger the critical warning or automatic suspend.
    property real _lastGood: 1
    readonly property real _raw: UPower.displayDevice?.percentage ?? 1
    readonly property bool _bogus: _raw <= 0 && chargeState === UPowerDeviceState.Unknown
    on_RawChanged: if (!_bogus) _lastGood = _raw
    Component.onCompleted: if (!_bogus) _lastGood = _raw
    property real percentage: Math.round((_bogus ? _lastGood : _raw) * 100) / 100
    readonly property bool allowAutomaticSuspend: Config.options.battery.automaticSuspend
    readonly property bool soundEnabled: Config.options.sounds.battery

    property bool isLow: available && (percentage <= Config.options.battery.low / 100)
    property bool isCritical: available && (percentage <= Config.options.battery.critical / 100)
    property bool isSuspending: available && (percentage <= Config.options.battery.suspend / 100)
    property bool isFull: available && (percentage >= Config.options.battery.full / 100)

    property bool isLowAndNotCharging: settled && isLow && !isPluggedIn
    property bool isCriticalAndNotCharging: settled && isCritical && !isPluggedIn
    property bool isSuspendingAndNotCharging: settled && allowAutomaticSuspend && isSuspending && !isPluggedIn
    property bool isFullAndCharging: settled && isFull && isCharging

    property real energyRate: UPower.displayDevice.changeRate
    property real timeToEmpty: UPower.displayDevice.timeToEmpty
    property real timeToFull: UPower.displayDevice.timeToFull

    property real health: {
        const devList = UPower.devices.values
        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i]
            if (dev.isLaptopBattery && dev.healthSupported) {
                const h = dev.healthPercentage
                if (h === 0) return 0.01
                else if (h < 1) return h * 100
                else return h
            }
        }
        return 0
    }

    onIsLowAndNotChargingChanged: {
        if (!root.available || !isLowAndNotCharging) return
        Quickshell.execDetached(["notify-send", "Low battery", "Consider plugging in your device", "-u", "critical", "-a", "Ano Shell", "--hint=int:transient:1"])
        if (root.soundEnabled) Audio.playSystemSound("dialog-warning")
    }

    onIsCriticalAndNotChargingChanged: {
        if (!root.available || !isCriticalAndNotCharging) return
        Quickshell.execDetached(["notify-send", "Critically low battery",
            `Please charge! Automatic suspend at ${Config.options.battery.suspend}%`,
            "-u", "critical", "-a", "Ano Shell", "--hint=int:transient:1"])
        if (root.soundEnabled) Audio.playSystemSound("suspend-error")
    }

    onIsSuspendingAndNotChargingChanged: {
        if (root.available && isSuspendingAndNotCharging)
            Quickshell.execDetached(["bash", "-c", "systemctl suspend || loginctl suspend"])
    }

    onIsFullAndChargingChanged: {
        if (!root.available || !isFullAndCharging) return
        Quickshell.execDetached(["notify-send", "Battery full", "Please unplug the charger", "-a", "Ano Shell", "--hint=int:transient:1"])
        if (root.soundEnabled) Audio.playSystemSound("complete")
    }

    onIsPluggedInChanged: {
        if (!root.available || !root.settled || !root.soundEnabled) return
        Audio.playSystemSound(isPluggedIn ? "power-plug" : "power-unplug")
    }
}
