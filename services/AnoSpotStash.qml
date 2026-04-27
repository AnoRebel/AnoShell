pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "root:modules/common"

/**
 * AnoSpot stash — ephemeral staging directory for items dropped onto the
 * AnoSpot overlay. Files are copied in (originals untouched), the user
 * picks an action in the popout (LocalSend, Open, Copy path, etc.), then
 * clears the stash.
 *
 * Storage location resolution order:
 *   1. Config.options.anoSpot.stashDir   (explicit override; empty = auto)
 *   2. $XDG_RUNTIME_DIR/anoSpot          (preferred — per-user, ephemeral)
 *   3. /tmp/anoSpot-<UID>                (fallback if XDG_RUNTIME_DIR unset)
 *
 * The directory is created lazily on first use and on every refresh.
 */
Singleton {
    id: root

    // ─── Path resolution ─────────────────────────────────────────────────
    readonly property string xdgRuntimeDir: Quickshell.env("XDG_RUNTIME_DIR")
    readonly property string uid: Quickshell.env("UID") || ""
    readonly property string configuredDir: Config.options?.anoSpot?.stashDir ?? ""

    readonly property string stashDir: {
        if (configuredDir.length > 0) return configuredDir;
        if (xdgRuntimeDir.length > 0) return xdgRuntimeDir + "/anoSpot";
        return "/tmp/anoSpot-" + (uid || "user");
    }

    // ─── Item model ──────────────────────────────────────────────────────
    // Each entry: { fileURL, filePath, name, isDir, sizeBytes (number),
    //               sizeText (e.g. "1.4 MB") }
    ListModel { id: itemsModel }
    property alias items: itemsModel
    readonly property int count: itemsModel.count
    readonly property bool empty: count === 0

    // Aggregate size of every staged item, formatted.
    property real totalSizeBytes: 0
    readonly property string totalSizeText: _formatSize(totalSizeBytes)

    // ─── Public API ──────────────────────────────────────────────────────
    function addUrls(urls) {
        if (!urls || urls.length === 0) return;
        // Build a single shell command: ensure dir, then `cp -a` each url
        // (decoded from file:// scheme) into it. URLs that aren't file://
        // are skipped here — http(s) downloads are out of scope for v1.
        let parts = ["mkdir -p " + _shEsc(root.stashDir)];
        for (let i = 0; i < urls.length; i++) {
            let u = urls[i].toString();
            if (u.startsWith("file://")) {
                let p = decodeURIComponent(u.substring(7));
                parts.push("cp -a --backup=numbered " + _shEsc(p) + " " + _shEsc(root.stashDir) + "/");
            }
            // Non-file URLs (http, data:) intentionally ignored in v1.
        }
        if (parts.length === 1) return;  // only the mkdir, no actual files
        copyProc.command = ["bash", "-c", parts.join(" && ")];
        copyProc.running = true;
    }

    function remove(filePath) {
        if (!filePath || filePath.length === 0) return;
        // Guard: only remove paths under our own stash dir (defense-in-depth).
        if (!filePath.startsWith(root.stashDir + "/")) {
            console.warn("[AnoSpotStash] refusing to remove path outside stashDir:", filePath);
            return;
        }
        rmProc.command = ["rm", "-rf", "--", filePath];
        rmProc.running = true;
    }

    function clear() {
        // Remove only items inside the stash dir (preserve the dir itself).
        clearProc.command = ["bash", "-c",
            "[ -d " + _shEsc(root.stashDir) + " ] && find " + _shEsc(root.stashDir) +
            " -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +"];
        clearProc.running = true;
    }

    function refresh() {
        if (!scanProc.running) scanProc.running = true;
    }

    // ─── Internals ───────────────────────────────────────────────────────
    function _shEsc(s) {
        // Single-quote escape: 'foo' -> ''\''foo'\''
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    function _formatSize(bytes) {
        const n = Number(bytes) || 0;
        if (n < 1024) return n + " B";
        if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB";
        if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1) + " MB";
        return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB";
    }

    function _refreshFromOutput(text) {
        itemsModel.clear();
        let total = 0;
        if (!text) { root.totalSizeBytes = 0; return; }
        // Each line: "<bytes>\t<name>" where name from ls -1p (dirs end /).
        // For directories, du gives the recursive size.
        const lines = text.split("\n");
        for (const line of lines) {
            const t = line.trim();
            if (!t || t.indexOf("\t") < 0) continue;
            const tab = t.indexOf("\t");
            const sizeBytes = parseInt(t.substring(0, tab), 10) || 0;
            const rawName = t.substring(tab + 1);
            const isDir = rawName.endsWith("/");
            const name = isDir ? rawName.slice(0, -1) : rawName;
            const fullPath = root.stashDir + "/" + name;
            itemsModel.append({
                fileURL: "file://" + fullPath,
                filePath: fullPath,
                name: name,
                isDir: isDir,
                sizeBytes: sizeBytes,
                sizeText: _formatSize(sizeBytes)
            });
            total += sizeBytes;
        }
        root.totalSizeBytes = total;
    }

    Process {
        id: copyProc
        onExited: (code, _) => {
            if (code !== 0)
                console.warn("[AnoSpotStash] copy failed with code", code);
            root.refresh();
        }
    }

    Process {
        id: rmProc
        onExited: () => root.refresh()
    }

    Process {
        id: clearProc
        onExited: () => root.refresh()
    }

    Process {
        id: scanProc
        // Emits "<bytes>\t<name>" per entry. ls -1p tags directories with
        // trailing /. For files, `stat -c%s` is byte-accurate; for dirs,
        // `du -sb` reports the recursive byte total.
        command: ["bash", "-c",
            "set -e; d=" + _shEsc(root.stashDir) + "; mkdir -p \"$d\"; " +
            "ls -1p \"$d\" 2>/dev/null | while IFS= read -r entry; do " +
            "  case \"$entry\" in */) " +
            "    sz=$(du -sb -- \"$d/${entry%/}\" 2>/dev/null | cut -f1);" +
            "    printf '%s\\t%s\\n' \"${sz:-0}\" \"$entry\" ;;" +
            "  *) " +
            "    sz=$(stat -c%s -- \"$d/$entry\" 2>/dev/null);" +
            "    printf '%s\\t%s\\n' \"${sz:-0}\" \"$entry\" ;;" +
            "  esac;" +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: root._refreshFromOutput(this.text)
        }
    }

    // Keep the model fresh whenever the stash dir itself changes (rare —
    // only when the user edits Config.options.anoSpot.stashDir).
    onStashDirChanged: refresh()

    // Initial scan once Config is ready.
    Connections {
        target: Config
        function onReadyChanged() {
            if (Config.ready) root.refresh();
        }
    }
}
