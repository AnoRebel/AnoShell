pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs
import qs.services

/**
 * ShellErrors: the running shell's QML warnings and errors since it started
 * (Settings → About → Errors, and the count on About in the Settings rail).
 * Quickshell has no in-process API for its log, so anod reads
 * $XDG_RUNTIME_DIR/quickshell/by-pid/<pid>/log.log (`shell.errors`): only
 * WARN/ERROR lines of the qml and scene categories, deduplicated with counts,
 * the newest 200. Nothing polls: Settings refreshes it when it opens and the
 * Errors card while it is shown.
 */
Singleton {
    id: root

    property var entries: []   // [{level, category, message, count, first, last}], newest last
    property int total: 0      // lines, duplicates included
    property int errors: 0     // of which ERROR
    property int dropped: 0    // distinct messages beyond the 200 shown
    property string log: ""
    property string error: ""
    property bool loading: false
    readonly property int count: root.entries.length + root.dropped

    function refresh() {
        if (root.loading) return
        if (!Anod.available) { root.error = "Reading the shell's log needs anod (the AnoShell daemon)."; return }
        root.loading = true
        // The standalone Settings window is its own process: anod then finds the shell's log itself.
        Anod.call("shell.errors", { pid: Quickshell.processId }, (r, e) => {
            root.loading = false
            if (!r) { root.error = e?.message ?? "anod didn't answer"; return }
            root.error = ""
            root.entries = r.entries ?? []
            root.total = r.total ?? 0
            root.errors = r.errors ?? 0
            root.dropped = r.dropped ?? 0
            root.log = r.log ?? ""
        })
    }

    Connections {
        target: GlobalStates
        function onSettingsOpenChanged() { if (GlobalStates.settingsOpen) root.refresh() }
    }
    Connections {
        target: Anod
        function onAvailableChanged() { if (Anod.available) root.refresh() }
    }
    Component.onCompleted: root.refresh()
}
