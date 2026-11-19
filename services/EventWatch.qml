import QtQuick
import Quickshell

/**
 * Asks anod for one system event source (events.want: "udev", "nm",
 * "logind", "gamemode", "kdeconnect") while `active`, and emits its events.
 * `live` is true while anod delivers them; a service runs its own watcher
 * process only while neither `live` nor `pending` (anod down, too old, or
 * the source couldn't start, e.g. no system bus). A source anod loses
 * (events_lost) is asked for again.
 */
Scope {
    id: root
    required property string source
    property bool active: false
    readonly property bool live: root._on
    readonly property bool pending: root._asking || (root._startup && !Anod.available)
    signal event(var data)
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
    property bool _on: false
    property bool _asking: false
    property bool _failed: false   // anod said no: don't ask again until it reconnects

    function _sync() {
        // `active` can arrive before `source` while the object is built.
        const want = root.active && root.source !== "" && Anod.available && !root._failed
        if (root._on && !want) {
            Anod.call("events.want", { source: root.source, on: false }, () => {})
            root._on = false
        }
        if (!want || root._on || root._asking) return
        root._asking = true
        Anod.call("events.want", { source: root.source, on: true }, (res, err) => {
            if (!err && res && (!root.active || !Anod.available)) { Anod.call("events.want", { source: root.source, on: false }, () => {}); root._asking = false; return }
            if (err || !res) root._failed = true
            else root._on = true // live before not pending (bindings react at once)
            root._asking = false
        })
    }
    onActiveChanged: root._sync()
    onSourceChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: if (root._on) Anod.call("events.want", { source: root.source, on: false }, () => {})

    Connections {
        target: Anod
        // A new connection: anod forgot the old wants (and may now manage).
        function onAvailableChanged() { root._on = false; root._asking = false; root._failed = false; root._sync() }
        // Events also while asking: a source may send its first state (GameMode's
        // count) before anod's reply arrives.
        function onEvent(name, data) {
            if (!root._on && !root._asking) return
            if (name === root.source) root.event(data)
            else if (name === "events_lost" && data?.source === root.source) { root._on = false; root._sync() }
        }
    }
}
