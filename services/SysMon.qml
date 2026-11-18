pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * The busiest processes, open apps and temperature sensors for the bubble views (anod's sysmon.*, read from /proc).
 * Samples once a second, and only while a view holds a lease. mode "apps" groups the open windows by app (their
 * pids where the compositor reports them, else the app id's name).
 */
Singleton {
    id: root

    property var procs: []      // [{pid, name, cpu 0..1, mem, memShare, threads, user, start, paused, cmd}]
    property var apps: []       // [{app, cpu, mem, memShare, procs, top}]
    property var sensors: []    // [{chip, label, c}]
    property int processCount: 0
    property int cores: 0
    property var history: ({})  // "p<pid>" / "a<app>" → recent CPU shares (the last 60)
    readonly property bool available: Anod.available
    readonly property string mode: Config.options?.bubbleMonitor?.mode ?? "processes"

    property var _leases: ({})
    property int leaseCount: 0
    function acquire(name) { root._leases[name] = (root._leases[name] ?? 0) + 1; root.leaseCount++ }
    function release(name) {
        if (!root._leases[name]) return
        if (--root._leases[name] <= 0) delete root._leases[name]
        root.leaseCount--
    }
    readonly property bool running: root.leaseCount > 0
    onRunningChanged: {
        if (root.running && root.mode === "apps") CompositorService.acquireWindows("sysmon")
        else CompositorService.releaseWindows("sysmon")
        if (!root.running) root.history = ({})
    }
    onModeChanged: if (root.running) {
        if (root.mode === "apps") CompositorService.acquireWindows("sysmon")
        else CompositorService.releaseWindows("sysmon")
    }

    function _remember(hist, key, v) {
        const h = (root.history[key] ?? []).concat([v])
        hist[key] = h.length > 60 ? h.slice(h.length - 60) : h
    }

    function _groups() {
        const by = {}
        for (const w of CompositorService.windows) {
            const app = w.appId || w.title
            if (!app) continue
            const g = by[app] ?? (by[app] = { app: app, pids: [], names: [String(app).split(".").pop()] })
            if (w.pid > 0 && !g.pids.includes(w.pid)) g.pids.push(w.pid)
        }
        return Object.values(by)
    }

    function sample() {
        if (!Anod.available) return
        Anod.call("sysmon.top", { n: 12 }, (res, err) => {
            if (err || !res) return
            root.procs = res.procs ?? []
            root.processCount = res.count ?? 0
            root.cores = res.cores ?? 0
            if (root.mode !== "processes") return
            const hist = {}
            for (const p of root.procs) root._remember(hist, `p${p.pid}`, p.cpu)
            root.history = hist
        })
        if (root.mode === "apps")
            Anod.call("sysmon.apps", { groups: root._groups() }, (res, err) => {
                if (err || !res) return
                root.apps = res.filter(a => a.procs > 0).slice(0, 12)
                const hist = {}
                for (const a of root.apps) root._remember(hist, `a${a.app}`, a.cpu)
                root.history = hist
            })
        if (root._tick++ % 5 === 0)
            Anod.call("sysmon.sensors", null, res => root.sensors = res ?? [])
    }
    property int _tick: 0

    // One process's details (null when it has gone).
    function details(pid, cb) { Anod.call("sysmon.proc", { pid: pid }, (res, err) => cb(err ? null : res)) }

    Timer {
        running: root.running && Anod.available
        interval: 1000; repeat: true; triggeredOnStart: true
        onTriggered: root.sample()
    }
}
