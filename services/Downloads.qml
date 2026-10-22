pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common

/**
 * Downloads in progress in the download folder, from anod's "downloads"
 * watcher (anod/internal/downloads): browsers' partial files with the bytes
 * so far and a smoothed rate (no total: browsers don't write it anywhere),
 * and the last few that finished while anod watched.
 */
Singleton {
    id: root

    property string dir: ""
    // [{ path, name, size, rate }]
    property var active: []
    // [{ path, name, size, at }], newest first
    property var finished: []
    readonly property bool downloading: root.active.length > 0
    readonly property bool any: root.downloading || root.finished.length > 0
    readonly property real rate: root.active.reduce((sum, f) => sum + f.rate, 0)

    function _set(d) {
        root.dir = d?.dir ?? ""
        root.active = d?.active ?? []
        root.finished = d?.finished ?? []
    }
    Connections {
        target: Anod
        function onEvent(name, data) { if (name === "downloads") root._set(data) }
        function onAvailableChanged() { root._ask() }
    }
    function _ask() {
        if (!Anod.available) { root._set(null); return }
        Anod.call("downloads.list", {}, (r, e) => { if (!e) root._set(r) })
    }
    Component.onCompleted: root._ask()

    function open(path: string): void { DefaultApps.launch(["xdg-open", path]) }
    function showFolder(path: string): void { DefaultApps.launch(["xdg-open", path.substring(0, path.lastIndexOf("/")) || "/"]) }
    function clear(path: string): void { Anod.call("downloads.clear", { path: path }, (r, e) => { if (!e) root._set(r) }) }
}
