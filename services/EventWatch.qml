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
    readonly property bool pending: root._asking
    signal event(var data)

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
            root._asking = false
            if (err || !res) { root._failed = true; return }
            if (!root.active || !Anod.available) { Anod.call("events.want", { source: root.source, on: false }, () => {}); return }
            root._on = true
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
