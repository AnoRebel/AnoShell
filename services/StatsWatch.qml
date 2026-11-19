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
    readonly property bool live: root._id > 0
    // Asking anod right now: a consumer waits rather than reading /proc meanwhile.
    readonly property bool pending: root._asking
    signal sample(var data)

    property int _id: 0
    property bool _asking: false
    property int _leasedInterval: 0

    function _sync() {
        const want = root.active && Anod.available
        if (root._id > 0 && (!want || root._leasedInterval !== root.interval)) {
            Anod.call("stats.unwatch", { id: root._id }, () => {})
            root._id = 0
        }
        if (!want || root._id > 0 || root._asking) return
        root._asking = true
        const iv = root.interval
        Anod.call("stats.watch", { interval: iv }, (res, err) => {
            root._asking = false
            const id = res?.id ?? 0
            if (!id) return
            if (!root.active || !Anod.available) { Anod.call("stats.unwatch", { id }, () => {}); return }
            root._id = id
            root._leasedInterval = iv
            root._sync() // the interval may have changed meanwhile
        })
    }
    onActiveChanged: root._sync()
    onIntervalChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: if (root._id > 0) Anod.call("stats.unwatch", { id: root._id }, () => {})

    Connections {
        target: Anod
        // A new connection after anod restarts: the old leases died with it.
        function onAvailableChanged() { root._id = 0; root._asking = false; root._sync() }
        function onEvent(name, data) { if (name === "stats" && root._id > 0) root.sample(data) }
    }
}
