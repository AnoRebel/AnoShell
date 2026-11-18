pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * System resource monitor. Polls /proc for CPU (total and per core), RAM, swap and network I/O, the CPU temperature
 * (the x86_pkg_temp thermal zone, else the first) and disk use of /. Keeps rolling histories for the charts.
 * Everything is sampled only while a consumer holds a lease.
 */
Singleton {
    id: root
    property real memoryTotal: 1
    property real memoryFree: 0
    property real memoryUsed: memoryTotal - memoryFree
    property real memoryUsedPercentage: memoryUsed / memoryTotal
    property real swapTotal: 1
    property real swapFree: 0
    property real swapUsed: swapTotal - swapFree
    property real swapUsedPercentage: swapTotal > 0 ? (swapUsed / swapTotal) : 0
    property real cpuUsage: 0
    property var previousCpuStats

    // Network speed
    property var coreUsage: []          // 0..1 per core
    property real temperature: NaN      // °C
    property real diskUsed: NaN         // bytes
    property real diskSize: NaN
    readonly property real diskUsedPercentage: root.diskSize > 0 ? root.diskUsed / root.diskSize : 0
    property var previousCoreStats: []

    property real networkDownloadSpeed: 0
    property real networkUploadSpeed: 0
    property var previousNetworkStats

    property string maxAvailableMemoryString: kbToGbString(root.memoryTotal)
    property string maxAvailableSwapString: kbToGbString(root.swapTotal)
    property string maxAvailableCpuString: "--"

    readonly property int historyLength: Config?.options.resources.historyLength ?? 60

    // Polling runs only while a visible consumer holds a lease (ServiceLease).
    property var _leases: ({})
    property int leaseCount: 0
    // Counted per name: several instances (e.g. one bar per screen) may share a name.
    function acquire(name) { root._leases[name] = (root._leases[name] ?? 0) + 1; root.leaseCount++ }
    function release(name) {
        if (!root._leases[name]) return
        if (--root._leases[name] <= 0) delete root._leases[name]
        root.leaseCount--
    }
    // On pause, forget the last sample: the first sample after resuming must
    // not average network/CPU over the whole pause as if it were one tick.
    onLeaseCountChanged: if (leaseCount === 0) {
        pollTimer.interval = 1
        previousCpuStats = undefined
        previousNetworkStats = undefined
        previousCoreStats = []
    }
    property list<real> cpuUsageHistory: []
    property list<real> memoryUsageHistory: []
    property list<real> swapUsageHistory: []
    property list<real> temperatureHistory: []

    function kbToGbString(kb) {
        return (kb / (1024 * 1024)).toFixed(1) + " GB"
    }

    function updateHistories() {
        memoryUsageHistory = [...memoryUsageHistory, memoryUsedPercentage]
        if (memoryUsageHistory.length > historyLength) memoryUsageHistory.shift()

        swapUsageHistory = [...swapUsageHistory, swapUsedPercentage]
        if (swapUsageHistory.length > historyLength) swapUsageHistory.shift()

        cpuUsageHistory = [...cpuUsageHistory, cpuUsage]
        if (cpuUsageHistory.length > historyLength) cpuUsageHistory.shift()

        if (!isNaN(temperature)) {
            temperatureHistory = [...temperatureHistory, temperature]
            if (temperatureHistory.length > historyLength) temperatureHistory.shift()
        }
    }

    Timer {
        id: pollTimer
        interval: 1 // first sample immediately, then the configured interval
        running: root.leaseCount > 0
        repeat: true
        onTriggered: {
            fileMeminfo.reload()
            fileStat.reload()
            fileNetDev.reload()

            // Memory & swap
            const textMeminfo = fileMeminfo.text()
            memoryTotal = Number(textMeminfo.match(/MemTotal: *(\d+)/)?.[1] ?? 1)
            memoryFree = Number(textMeminfo.match(/MemAvailable: *(\d+)/)?.[1] ?? 0)
            swapTotal = Number(textMeminfo.match(/SwapTotal: *(\d+)/)?.[1] ?? 1)
            swapFree = Number(textMeminfo.match(/SwapFree: *(\d+)/)?.[1] ?? 0)

            // CPU
            const textStat = fileStat.text()
            const cpuLine = textStat.match(/^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cpuLine) {
                const stats = cpuLine.slice(1).map(Number)
                const total = stats.reduce((a, b) => a + b, 0)
                const idle = stats[3] + stats[4]  // idle + iowait, as top/btop count it
                if (previousCpuStats) {
                    const totalDiff = total - previousCpuStats.total
                    const idleDiff = idle - previousCpuStats.idle
                    cpuUsage = totalDiff > 0 ? (1 - idleDiff / totalDiff) : 0
                }
                previousCpuStats = { total, idle }
            }
            const cores = []
            const prevCores = root.previousCoreStats
            const coreStats = []
            for (const line of textStat.split("\n")) {
                if (!/^cpu\d/.test(line)) continue
                const v = line.trim().split(/\s+/).slice(1, 8).map(Number)
                const total = v.reduce((a, b) => a + b, 0), idle = v[3] + v[4]
                const prev = prevCores[coreStats.length]
                cores.push(prev && total > prev.total ? 1 - (idle - prev.idle) / (total - prev.total) : 0)
                coreStats.push({ total, idle })
            }
            root.previousCoreStats = coreStats
            root.coreUsage = cores

            if (root.tempPath) { tempFile.reload(); root.temperature = parseInt(tempFile.text()) / 1000 }
            if (root._diskTick++ % 20 === 0) df.running = true

            // Network
            const textNetDev = fileNetDev.text()
            const netLines = textNetDev.split('\n')
            let totalReceived = 0, totalTransmitted = 0
            for (let i = 2; i < netLines.length; i++) {
                const line = netLines[i].trim()
                if (line.length === 0) continue
                const parts = line.split(/\s+/)
                if (parts.length < 10) continue
                const iface = parts[0].replace(':', '')
                if (iface === 'lo') continue
                totalReceived += parseInt(parts[1] || 0)
                totalTransmitted += parseInt(parts[9] || 0)
            }
            if (previousNetworkStats) {
                const timeDiff = interval / 1000
                networkDownloadSpeed = (totalReceived - previousNetworkStats.received) / timeDiff
                networkUploadSpeed = (totalTransmitted - previousNetworkStats.transmitted) / timeDiff
            }
            previousNetworkStats = { received: totalReceived, transmitted: totalTransmitted }

            root.updateHistories()
            interval = GameMode.slowPolling ? GameMode.pollInterval : (Config.options?.resources?.updateInterval ?? 3000)
        }
    }

    FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView { id: fileNetDev; path: "/proc/net/dev" }

    // The CPU temperature: the zone is picked once (x86_pkg_temp, else the first), then read with each sample.
    property string tempPath: ""
    property bool _tempPicked: false
    Process {
        running: root.leaseCount > 0 && !root._tempPicked
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do [ -r \"$z/temp\" ] && printf '%s %s\\n' \"$z\" \"$(cat \"$z/type\")\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const zones = text.trim().split("\n").filter(l => l).map(l => l.split(" "))
                const pkg = zones.find(z => z[1] === "x86_pkg_temp") ?? zones[0]
                if (pkg?.[0]) root.tempPath = `${pkg[0]}/temp`
                root._tempPicked = true
            }
        }
    }
    FileView { id: tempFile; path: root.tempPath; blockLoading: true }
    // Disk use of /: every 20th sample (a minute at the default 3 s).
    property int _diskTick: 0
    Process {
        id: df
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = text.trim().split("\n").pop().trim().split(/\s+/).map(Number)
                if (n.length === 2 && n[0] > 0) { root.diskSize = n[0]; root.diskUsed = n[1] }
            }
        }
    }

    Process {
        id: findCpuMaxFreqProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        command: ["bash", "-c", "lscpu | grep 'CPU max MHz' | awk '{print $4}'"]
        running: true
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                root.maxAvailableCpuString = (parseFloat(outputCollector.text) / 1000).toFixed(0) + " GHz"
            }
        }
    }
}
