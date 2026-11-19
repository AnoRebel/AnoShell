pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * System resource monitor: CPU (total and per core), RAM, swap, network I/O (the machine's own links), the CPU
 * temperature and disk use of /, with rolling histories for the charts. anod samples them (stats.watch, pushed
 * "stats" events) while a consumer holds a lease; the /proc reading below only runs while anod is unavailable.
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

    // The GPU anod shows (vitals.gpu_card, else the discrete one, else the first); anod only.
    property bool gpuPresent: false
    property string gpuName: ""
    property real gpuUsage: NaN         // 0..1, NaN while unknown (first sample, no driver figure)
    property real gpuMHz: NaN
    property real gpuMemUsed: NaN       // bytes, dedicated memory only
    property real gpuMemTotal: NaN
    property real gpuTemperature: NaN   // °C
    property string gpuNote: ""
    property list<real> gpuUsageHistory: []

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
    // anod feeds the figures while it runs; the timer below is the fallback.
    readonly property int pollMs: GameMode.slowPolling ? GameMode.pollInterval : (Config.options?.resources?.updateInterval ?? 3000)
    readonly property bool _fallback: root.leaseCount > 0 && !watch.live && !watch.pending
    on_FallbackChanged: if (root._fallback && !root.tempPath) tempProbe.running = true
    property real _lastHist: 0
    // Leases whose views show no GPU: anod skips reading it while only these hold.
    readonly property var noGpuLeases: ["barResources", "gaugePiece"]
    readonly property bool _gpuWanted: { root.leaseCount; return Object.keys(root._leases).some(n => !root.noGpuLeases.includes(n)) }
    StatsWatch {
        id: watch
        active: root.leaseCount > 0
        interval: root.pollMs
        gpu: root._gpuWanted
        onSample: data => root._apply(data)
    }
    function _apply(d) {
        const m = d.mem ?? {}
        root.memoryTotal = m.totalKB || 1
        root.memoryFree = m.availKB ?? 0
        root.swapTotal = m.swapTotalKB ?? 0
        root.swapFree = m.swapFreeKB ?? 0
        const c = d.cpu ?? {}
        if (c.total !== null && c.total !== undefined) root.cpuUsage = c.total // null: the first sample
        if (c.cores) root.coreUsage = Array.from(c.cores)
        if (c.maxMHz > 0) root.maxAvailableCpuString = (c.maxMHz / 1000).toFixed(0) + " GHz"
        root.temperature = d.temp?.c ?? NaN
        const disk = d.disks?.[0]
        if (disk) { root.diskSize = disk.size; root.diskUsed = disk.used }
        if (d.net?.rx !== null && d.net?.rx !== undefined) { root.networkDownloadSpeed = d.net.rx; root.networkUploadSpeed = d.net.tx }
        const gpus = Array.from(d.gpus ?? [])
        const g = gpus.find(x => x.shown) ?? null
        const n = v => (v === null || v === undefined) ? NaN : v
        root.gpuPresent = !!g
        root.gpuName = g?.name ?? ""
        root.gpuUsage = g ? n(g.load) / 100 : NaN
        root.gpuMHz = n(g?.mhz)
        root.gpuMemUsed = n(g?.memUsed)
        root.gpuMemTotal = n(g?.memTotal)
        root.gpuTemperature = n(g?.temp)
        root.gpuNote = g?.note ?? ""
        // Another consumer may ask anod for faster samples: the histories keep this one's pace.
        if (d.t - root._lastHist >= root.pollMs * 0.9) { root._lastHist = d.t; root.updateHistories() }
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

        if (!isNaN(gpuUsage)) {
            gpuUsageHistory = [...gpuUsageHistory, gpuUsage]
            if (gpuUsageHistory.length > historyLength) gpuUsageHistory.shift()
        }
        if (!isNaN(temperature)) {
            temperatureHistory = [...temperatureHistory, temperature]
            if (temperatureHistory.length > historyLength) temperatureHistory.shift()
        }
    }

    Timer {
        id: pollTimer
        interval: 1 // first sample immediately, then the configured interval
        running: root._fallback
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
            interval = root.pollMs
        }
    }

    FileView { id: fileMeminfo; path: "/proc/meminfo" }
    FileView { id: fileStat; path: "/proc/stat" }
    FileView { id: fileNetDev; path: "/proc/net/dev" }

    // Fallback only (anod picks the sensor itself): the zone is picked once (x86_pkg_temp, else the first; a one-off
    // listing, not tied to the lease: a lease dropped mid-pick used to kill it and leave no zone).
    property string tempPath: ""
    Process {
        id: tempProbe
        command: ["sh", "-c", "for z in /sys/class/thermal/thermal_zone*; do [ -r \"$z/temp\" ] && printf '%s %s\\n' \"$z\" \"$(cat \"$z/type\")\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const zones = text.trim().split("\n").filter(l => l).map(l => l.split(" "))
                const pkg = zones.find(z => z[1] === "x86_pkg_temp") ?? zones[0]
                if (pkg?.[0]) root.tempPath = `${pkg[0]}/temp`
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

    // The CPU's top clock (kHz), read once: anod's samples carry it too.
    FileView {
        path: "/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq"
        printErrors: false
        onLoaded: { const khz = parseInt(text()); if (khz > 0) root.maxAvailableCpuString = (khz / 1e6).toFixed(0) + " GHz" }
    }
}
