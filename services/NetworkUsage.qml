pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Aggregate network throughput: anod's samples (the machine's own links) while
 * it runs, else polling /proc/net/dev (all non-loopback interfaces). Exposes:
 *   downloadSpeed / uploadSpeed   bytes per second (instantaneous)
 *   downloadTotal / uploadTotal   bytes since service start
 *   downloadHistory / uploadHistory   plain JS arrays of recent speeds
 *                                     (length up to historyLength) for
 *                                     sparklines
 *
 * Plus formatBytes(b) and formatBytesTotal(b) helpers returning
 * {value, unit} for UI rendering.
 *
 * Service is dormant when Config.options.network.usage.enable is false
 * (the default — opt in when a UI surface needs the data).
 *
 * Adapted from caelestia/services/NetworkUsage.qml. Changes:
 *   - Caelestia.Internal.CircularBuffer replaced with a plain JS array
 *     trimmed to historyLength on each push (no QML-side consumer needs
 *     a typed CircularBuffer for ano's surfaces today).
 *   - Caelestia.Config.GlobalConfig replaced with
 *     Config.options.network.usage.{enable, intervalMs}.
 *   - Ref-counting Timer dropped in favour of the simpler enable-flag
 *     gate, consistent with other ano services (e.g. RecorderStatus).
 */
Singleton {
    id: root

    readonly property bool serviceEnabled: Config.options?.network?.usage?.enable ?? false
    readonly property int intervalMs: Config.options?.network?.usage?.intervalMs ?? 1000
    readonly property int historyLength: Config.options?.network?.usage?.historyLength ?? 30

    // Current speeds in bytes per second
    property real downloadSpeed: 0
    property real uploadSpeed: 0

    // Total bytes transferred since service start
    property real downloadTotal: 0
    property real uploadTotal: 0

    // Sparkline history
    property var downloadHistory: []
    property var uploadHistory: []

    // Internal accounting
    property real _prevRxBytes: 0
    property real _prevTxBytes: 0
    property real _prevTimestamp: 0
    property real _initialRxBytes: 0
    property real _initialTxBytes: 0
    property bool _initialized: false

    function formatBytes(bytes) {
        if (bytes < 0 || isNaN(bytes) || !isFinite(bytes))
            return { value: 0, unit: "B/s" };
        if (bytes < 1024)              return { value: bytes,                       unit: "B/s"  };
        if (bytes < 1024 * 1024)       return { value: bytes / 1024,                unit: "KB/s" };
        if (bytes < 1024 * 1024 * 1024) return { value: bytes / (1024 * 1024),       unit: "MB/s" };
        return                                { value: bytes / (1024 * 1024 * 1024), unit: "GB/s" };
    }

    function formatBytesTotal(bytes) {
        if (bytes < 0 || isNaN(bytes) || !isFinite(bytes))
            return { value: 0, unit: "B" };
        if (bytes < 1024)              return { value: bytes,                       unit: "B"  };
        if (bytes < 1024 * 1024)       return { value: bytes / 1024,                unit: "KB" };
        if (bytes < 1024 * 1024 * 1024) return { value: bytes / (1024 * 1024),       unit: "MB" };
        return                                { value: bytes / (1024 * 1024 * 1024), unit: "GB" };
    }

    function parseNetDev(content) {
        const lines = (content || "").split("\n");
        let totalRx = 0;
        let totalTx = 0;
        for (let i = 2; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;
            const parts = line.split(/\s+/);
            if (parts.length < 10) continue;
            const iface = parts[0].replace(":", "");
            if (iface === "lo") continue;
            totalRx += parseFloat(parts[1]) || 0;
            totalTx += parseFloat(parts[9]) || 0;
        }
        return { rx: totalRx, tx: totalTx };
    }

    function _push(arr, value) {
        const next = arr.slice();
        next.push(value);
        if (next.length > root.historyLength)
            next.shift();
        return next;
    }

    FileView {
        id: netDevFile
        path: "/proc/net/dev"
    }

    // anod's samples (the machine's own links) while it runs; /proc/net/dev here otherwise.
    StatsWatch {
        id: watch
        active: root.serviceEnabled && Config.ready
        interval: root.intervalMs
        onSample: d => { if (d.net) root._take(d.net.rxBytes, d.net.txBytes, d.t) }
    }

    Timer {
        interval: root.intervalMs
        running: root.serviceEnabled && Config.ready && !watch.live && !watch.pending
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            netDevFile.reload();
            const content = netDevFile.text();
            if (!content) return;
            const data = root.parseNetDev(content);
            root._take(data.rx, data.tx, Date.now());
        }
    }
    onServiceEnabledChanged: if (!root.serviceEnabled) { root._initialized = false; root.downloadTotal = 0; root.uploadTotal = 0 }
    // anod and the fallback count different links: start a new baseline, keep the totals.
    Connections { target: watch; function onLiveChanged() { root._initialized = false } }

    // One reading of the cumulative counters.
    function _take(rx, tx, now) {
        if (!root._initialized) {
            root._initialRxBytes = rx - root.downloadTotal;
            root._initialTxBytes = tx - root.uploadTotal;
            root._prevRxBytes = rx;
            root._prevTxBytes = tx;
            root._prevTimestamp = now;
            root._initialized = true;
            return;
        }
        // Counters that went down: a link left (or the source switched): no
        // rate this time, and the totals continue from the new baseline.
        if (rx < root._prevRxBytes || tx < root._prevTxBytes) {
            root._initialRxBytes = rx - root.downloadTotal;
            root._initialTxBytes = tx - root.uploadTotal;
        } else {
            const timeDelta = (now - root._prevTimestamp) / 1000;
            if (timeDelta > 0) {
                root.downloadSpeed = (rx - root._prevRxBytes) / timeDelta;
                root.uploadSpeed = (tx - root._prevTxBytes) / timeDelta;
                root.downloadHistory = root._push(root.downloadHistory, root.downloadSpeed);
                root.uploadHistory = root._push(root.uploadHistory, root.uploadSpeed);
            }
            root.downloadTotal = rx - root._initialRxBytes;
            root.uploadTotal = tx - root._initialTxBytes;
        }
        root._prevRxBytes = rx;
        root._prevTxBytes = tx;
        root._prevTimestamp = now;
    }
}
