pragma Singleton

import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services

/**
 * Transient states the pill morphs into for a moment (volume, brightness, mic,
 * keyboard layout, notification, charging, recording, device events: `icon`
 * is then the Material symbol), then returns to its
 * face. Each kind is toggle-able (anoSpot.transients.<kind>); a kind the pill
 * takes is not shown by the standalone OSD.
 *
 *   PillTransient.wants("volume")   -> the pill handles it (OSD stays quiet)
 *   PillTransient.show("volume", 0.42, false, "")
 */
Singleton {
    id: root

    property string kind: ""
    property real value: 0
    property bool muted: false
    property string label: ""
    property string icon: ""
    readonly property bool active: kind !== ""

    readonly property var kinds: ["volume", "brightness", "mic", "keyboard", "notification", "charging", "recording", "device"]
    // Screens whose pill can show a transient right now (visible, revealed,
    // not tucked, not grown); set by AnoSpot. If the focused screen's can't,
    // the standalone OSD shows it instead of nothing.
    property var _hosts: ({})
    function setHost(screen, ok) { const h = Object.assign({}, root._hosts); h[screen] = ok; root._hosts = h }
    readonly property bool canShow: {
        const f = CompositorService.focusedMonitorName
        return f ? (root._hosts[f] ?? false) : Object.values(root._hosts).some(v => v)
    }
    function wants(k) {
        return kinds.includes(k) && root.canShow
            && ((Config.options?.anoSpot?.enable ?? false) || BarStyle.pillBar)
            && (Config.options?.anoSpot?.transients?.[k] ?? true)
    }

    function show(k, v, m, l, ic) {
        if (!wants(k)) return false
        root.kind = k
        root.value = v ?? 0
        root.muted = m ?? false
        root.label = l ?? ""
        root.icon = ic ?? ""
        hide.interval = k === "notification" ? (Config.options?.anoSpot?.notificationTimeoutMs ?? 4000) : (Config.options?.osd?.timeout ?? 1500)
        hide.restart()
        return true
    }
    function dismiss() { root.kind = "" }

    Timer { id: hide; onTriggered: root.kind = "" }

    // Sources the OSD doesn't cover. Startup reports are initial state, not news.
    property bool _armed: false
    Timer { running: true; interval: 2500; onTriggered: root._armed = true }
    Connections {
        target: Notifications
        function onNotify(n) {
            if (!root._armed || Notifications.silent) return
            root.show("notification", 0, false, n?.summary ?? n?.appName ?? "", n?.appIcon ?? "")
        }
    }
    Connections {
        target: Battery
        function onIsChargingChanged() {
            if (root._armed && Battery.available) root.show("charging", Battery.percentage, !Battery.isCharging, Battery.isCharging ? "Charging" : "On battery")
        }
    }
    Connections {
        target: RecorderStatus
        function onIsRecordingChanged() {
            if (root._armed) root.show("recording", 0, !RecorderStatus.isRecording, RecorderStatus.isRecording ? "Recording" : "Recording saved")
        }
    }
}
