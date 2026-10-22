pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * FocusTime Service — manages the focus tracking daemon lifecycle.
 * Launches focus_daemon.py on startup, kills on shutdown.
 * Provides IPC target for toggling the FocusTime panel.
 */
Singleton {
    id: root

    readonly property string scriptsDir: Quickshell.shellPath("scripts/focustime")
    readonly property string daemonScript: root.scriptsDir + "/focus_daemon.py"
    readonly property string statsScript: root.scriptsDir + "/get_stats.py"
    readonly property string xdgRuntime: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string stateFile: root.xdgRuntime + "/focustime_state.json"

    // The daemon only runs while Focus Time is enabled; changing the exclude
    // list restarts it with the new list.
    readonly property bool wanted: Config.ready && (Config.options?.focusTime?.enable ?? true)
    readonly property var excludeApps: Config.options?.focusTime?.excludeApps ?? []
    onExcludeAppsChanged: if (daemon.running) { daemon.running = false; Qt.callLater(() => daemon.running = root.wanted) }

    // A child of the shell (it exits with the shell, even a killed one:
    // PR_SET_PDEATHSIG in the script). The pkill replaces a daemon left by an
    // older shell; anchored to "python3 ..." so it never matches this sh
    // wrapper, and the script path is an argument, not interpolated.
    Process {
        id: daemon
        running: root.wanted
        command: ["sh", "-c", 'pkill -f "^python3 .*focus_daemon[.]py" 2>/dev/null; sleep 0.2; exec python3 "$1"', "sh", root.daemonScript]
        environment: ({ FOCUSTIME_EXCLUDE: JSON.stringify(root.excludeApps) })
    }
}
