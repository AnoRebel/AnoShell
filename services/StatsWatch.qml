import QtQuick
import Quickshell

/**
 * Holds an anod statistics lease (stats.watch) while `active`, at `interval`
 * ms, and emits each pushed sample. `live` is true while anod feeds it; a
 * consumer reads /proc itself only while neither `live` nor `pending` (anod
 * down, or too old to know stats.watch).
 * The lease is tied to the shell's connection, so a crash or restart frees it.
 */
Scope {
    id: root
    property bool active: false
    property int interval: 2000
    property bool gpu: false // the samples should carry the GPUs (costlier on Intel)
    readonly property bool live: root._id > 0
    // Asking anod right now: a consumer waits rather than reading /proc meanwhile.
    readonly property bool pending: root._asking || (root._startup && !Anod.available)
    signal sample(var data)
    // Use your own reader now: neither live nor pending for 100 ms (bindings
    // and handlers react in no fixed order, so the raw state can blink true
    // for an instant while a lease starts); off again at once.
    readonly property bool _rawFallback: root.active && !root.live && !root.pending
    property bool fallback: false
    on_RawFallbackChanged: { if (!root._rawFallback) { fallbackDelay.stop(); root.fallback = false } else fallbackDelay.restart() }
    Timer { id: fallbackDelay; interval: 100; onTriggered: root.fallback = root._rawFallback }


    // The first 3 s: anod is usually still connecting, not missing; a consumer
    // waits rather than starting its own reader for that moment.
    property bool _startup: true
    Timer { running: true; interval: 3000; onTriggered: root._startup = false }
    property int _id: 0
    property bool _asking: false
    property int _leasedInterval: 0
    property bool _leasedGpu: false

    // Order matters: bindings react at once, so a lease being switched (a new
    // interval or GPU wish) must stay pending or live throughout, or a
    // consumer starts its /proc fallback for that instant.
    function _sync() {
        const want = root.active && Anod.available
        if (root._id > 0 && (!want || root._leasedInterval !== root.interval || root._leasedGpu !== root.gpu)) {
            const old = root._id
            if (want) root._asking = true // pending before not live
            root._id = 0
            Anod.call("stats.unwatch", { id: old }, () => {})
            if (want) root._ask()
            return
        }
        if (!want || root._id > 0 || root._asking) return
        root._asking = true
        root._ask()
    }
    function _ask() {
        const iv = root.interval, gpu = root.gpu
        Anod.call("stats.watch", { interval: iv, gpu: gpu }, (res, err) => {
            const id = res?.id ?? 0
            if (id && (!root.active || !Anod.available)) { Anod.call("stats.unwatch", { id }, () => {}); root._asking = false; return }
            if (id) {
                root._leasedInterval = iv
                root._leasedGpu = gpu
                root._id = id // live before not pending
            }
            root._asking = false
            if (id) root._sync() // the interval may have changed meanwhile
        })
    }
    onActiveChanged: root._sync()
    onIntervalChanged: root._sync()
    onGpuChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: if (root._id > 0) Anod.call("stats.unwatch", { id: root._id }, () => {})

    Connections {
        target: Anod
        // A new connection after anod restarts: the old leases died with it.
        function onAvailableChanged() { root._id = 0; root._asking = false; root._sync() }
        function onEvent(name, data) { if (name === "stats" && root._id > 0) root.sample(data) }
    }
}
