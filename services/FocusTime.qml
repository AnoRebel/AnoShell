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

    property bool daemonRunning: false

    // The daemon only runs while Focus Time is enabled; changing the exclude
    // list restarts it with the new list.
    readonly property bool wanted: Config.ready && (Config.options?.focusTime?.enable ?? true)
    readonly property var excludeApps: Config.options?.focusTime?.excludeApps ?? []
    onWantedChanged: wanted ? root.startDaemon() : root.stopDaemon()
    onExcludeAppsChanged: if (root.daemonRunning) root.restartDaemon()

    Component.onCompleted: {
        if (root.wanted) root.startDaemon();
    }

    Component.onDestruction: {
        root.stopDaemon();
    }

    function startDaemon(): void {
        if (root.daemonRunning) return;
        // Replace any stale daemon; the script path is an argument, not interpolated.
        // Anchored to "python3 ..." so pkill never matches this sh wrapper (whose
        // argv contains the script path).
        Quickshell.execDetached({
            command: ["sh", "-c", 'pkill -f "^python3 .*focus_daemon[.]py" 2>/dev/null; sleep 0.2; exec python3 "$1"', "sh", root.daemonScript],
            environment: ({ FOCUSTIME_EXCLUDE: JSON.stringify(root.excludeApps) })
        });
        root.daemonRunning = true;
    }

    function stopDaemon(): void {
        Quickshell.execDetached(["pkill", "-f", "^python3 .*focus_daemon[.]py"]);
        root.daemonRunning = false;
    }

    function restartDaemon(): void {
        root.stopDaemon();
        Qt.callLater(root.startDaemon);
    }
}
