pragma Singleton

import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services
import "root:services/anoSpotLogic.js" as AnoSpotLogic

/**
 * Transient states the pill morphs into for a moment (volume, brightness, mic,
 * keyboard layout, notification, charging, recording, device events: `icon`
 * is then the Material symbol; a download finished, a screenshot taken), then
 * returns to its face. Each kind is toggle-able (anoSpot.transients.<kind>);
 * a kind the pill takes is not shown by the standalone OSD.
 *
 * One on show is only replaced by one of at least its rank
 * (anoSpotLogic.replaces): a notification doesn't hide "Recording saved".
 * A job-done transient carries a `target` (its file); tapping the pill opens it.
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
    property string target: ""
    readonly property bool active: kind !== ""

    readonly property var kinds: ["volume", "brightness", "mic", "keyboard", "notification", "charging", "recording", "device", "download", "screenshot"]
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

    function show(k, v, m, l, ic, tgt) {
        if (!wants(k) || (root.active && !AnoSpotLogic.replaces(root.kind, k))) return false
        root.kind = k
        root.value = v ?? 0
        root.muted = m ?? false
        root.label = l ?? ""
        root.icon = ic ?? ""
        root.target = tgt ?? ""
        // Something to tap stays as long as a notification.
        hide.interval = k === "notification" || root.target ? (Config.options?.anoSpot?.notificationTimeoutMs ?? 4000) : (Config.options?.osd?.timeout ?? 1500)
        hide.restart()
        return true
    }
    function dismiss() { root.kind = "" }
    // The tap on a job-done transient: open its file.
    function openTarget() {
        if (root.target) DefaultApps.launch(["xdg-open", root.target])
        root.dismiss()
    }

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
        function onIsRecordingChanged() { if (root._armed && RecorderStatus.isRecording) root.show("recording", 0, false, "Recording") }
        function onSaved(path) { root.show("recording", 0, true, "Recording saved", "", path) }
    }
    Connections {
        target: Screenshot
        function onCaptured(path, mode) { root.show("screenshot", 0, false, "Screenshot taken", "", path) }
    }
    // Downloads finished since the last report (the first report is what was
    // already there). anod pushes these; nothing is polled.
    property var _seenDownloads: null
    Connections {
        target: Downloads
        function onFinishedChanged() {
            // anod gone: the next list (a restart's) is a fresh start.
            if (!Anod.available) { root._seenDownloads = null; return }
            const fresh = AnoSpotLogic.newlyFinished(root._seenDownloads, Downloads.finished)
            root._seenDownloads = Downloads.finished.map(f => f.path)
            if (root._armed && fresh.length)
                root.show("download", 0, false, fresh.length > 1 ? `${fresh.length} downloads finished` : fresh[0].name, "", fresh[0].path)
        }
    }
}
