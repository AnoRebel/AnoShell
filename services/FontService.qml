pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * FontService — enumerates installed font families via `fc-list` so the
 * Settings UI can offer real font pickers (and flag a configured font that
 * isn't installed).
 *
 * Exposes:
 *   families        sorted, de-duplicated list of installed family names
 *   ready           true once the first scan has completed
 *   isInstalled(n)  case-insensitive membership test
 */
Singleton {
    id: root

    property var families: []
    property bool ready: false

    function isInstalled(name) {
        if (!name) return false;
        const lower = String(name).toLowerCase();
        return root.families.some(f => f.toLowerCase() === lower);
    }

    function refresh() {
        fcListProc.running = true;
    }

    Component.onCompleted: root.refresh()

    Process {
        id: fcListProc
        // `fc-list : family` prints one family-name spec per line; a spec can be
        // a comma-separated list of localized aliases. Take the first alias of
        // each line, dedupe, sort. Scalable only: bitmap families can't be
        // drawn at other sizes (and each logs a warning in the picker).
        command: ["fc-list", ":scalable=true", "family"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const out = [];
                const lines = this.text.split("\n");
                for (const line of lines) {
                    const raw = line.trim();
                    if (raw.length === 0) continue;
                    const fam = raw.split(",")[0].trim();
                    if (fam.length === 0) continue;
                    const key = fam.toLowerCase();
                    if (seen[key]) continue;
                    seen[key] = true;
                    out.push(fam);
                }
                out.sort((a, b) => a.localeCompare(b));
                root.families = out;
                root.ready = true;
            }
        }
    }
}
