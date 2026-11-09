pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import "root:services/anoSpotLogic.js" as AnoSpotLogic

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

    // ─── Shelf ───────────────────────────────────────────────────────────
    // Beside the dropped files, the popout is a shelf: pins (services/Cliphist's,
    // kept in clipboard-pins.json, pictures copied beside it) and the
    // anoSpot.shelfSize newest clipboard entries and screenshots (the
    // screenshots only in memory: their temp files go within a day; a pin
    // keeps a copy).
    readonly property int shelfSize: Math.max(0, Config.options?.anoSpot?.shelfSize ?? 8)
    property var shots: []   // [{ path, at }], newest first
    Connections {
        target: Screenshot
        function onCaptured(path, mode) { root.shots = AnoSpotLogic.addShot(root.shots, path, Date.now(), root.shelfSize) }
    }
    onShelfSizeChanged: root.shots = root.shots.slice(0, root.shelfSize)
    // Drop screenshots whose file is gone (saved elsewhere, deleted); run when
    // the popout opens.
    function pruneShots() {
        if (root.shots.length === 0 || shotCheck.running) return
        shotCheck.exec({ command: ["sh", "-c", 'for f; do [ -e "$f" ] && printf "%s\\n" "$f"; done', "sh"].concat(root.shots.map(s => s.path)) })
    }
    Process {
        id: shotCheck
        stdout: StdioCollector {
            onStreamFinished: {
                const live = this.text.split("\n")
                root.shots = root.shots.filter(s => live.includes(s.path))
            }
        }
    }
    // A picture file to the clipboard, typed by its extension.
    function copyImage(path) {
        const ext = ((path.match(/\.([A-Za-z0-9]+)$/) ?? [])[1] ?? "png").toLowerCase()
        Quickshell.execDetached({ command: ["sh", "-c", 'wl-copy -t "image/$EXT" < "$F"'],
            environment: ({ EXT: ({ jpg: "jpeg", svg: "svg+xml" })[ext] ?? ext.replace(/[^a-z0-9]/g, ""), F: path }) })
    }

    // ─── Built-in action runtimes ───────────────────────────────────────
    // Each one operates on the current staged item set. Stateless helpers;
    // higher-level orchestration (e.g. LocalSend's discover → pick → send
    // flow) is owned by the popout UI.

    readonly property string scriptsDir: Quickshell.env("HOME") + "/.config/quickshell/ano/scripts/anoSpot"
    readonly property string discoverScript: scriptsDir + "/localsend_discover.sh"
    readonly property string sendScript: scriptsDir + "/localsend_send.sh"

    // LocalSend discovery state. Consumers bind to discoverState +
    // discoveredDevices; after calling localSendDiscover() the state
    // transitions: idle -> scanning -> ready (or back to idle on stop).
    property string discoverState: "idle"
    ListModel { id: discoveredDevicesModel }
    property alias discoveredDevices: discoveredDevicesModel

    function localSendDiscover() {
        if (discoverState === "scanning") return;
        discoveredDevicesModel.clear();
        discoverState = "scanning";
        discoverProc.command = ["bash", "-c", "exec " + _shEsc(root.discoverScript)];
        discoverProc.running = true;
    }

    function localSendStop() {
        discoverState = "idle";
    }

    // Send every staged file to <targetIp> via the ported send script.
    // Each invocation is fire-and-forget (notify-send handles success/fail
    // feedback). Caller is responsible for clear()ing the stash on success
    // if desired.
    function localSendAll(targetIp) {
        if (!targetIp || targetIp.length === 0) return;
        for (let i = 0; i < itemsModel.count; i++) {
            const it = itemsModel.get(i);
            if (it.isDir) continue;  // LocalSend protocol is per-file
            sendProc.command = ["bash", "-c",
                "exec " + _shEsc(root.sendScript) + " " + _shEsc(it.filePath) + " " + _shEsc(targetIp)];
            sendProc.running = true;
        }
    }

    // Open every staged item with the user's default handler.
    function openAll() {
        for (let i = 0; i < itemsModel.count; i++) {
            const it = itemsModel.get(i);
            xdgOpenProc.command = ["xdg-open", it.filePath];
            xdgOpenProc.running = true;
        }
    }

    // Reveal the parent directory of the first staged item (or the stash
    // dir itself if empty) in the user's default file manager.
    function revealFirst() {
        const target = itemsModel.count > 0
            ? itemsModel.get(0).filePath.replace(/\/[^\/]*$/, "")
            : root.stashDir;
        xdgOpenProc.command = ["xdg-open", target];
        xdgOpenProc.running = true;
    }

    // Comma-joined paths to the wl-clipboard.
    function copyPaths() {
        if (itemsModel.count === 0) return;
        const paths = [];
        for (let i = 0; i < itemsModel.count; i++)
            paths.push(itemsModel.get(i).filePath);
        wlCopyProc.command = ["bash", "-c",
            "printf %s " + _shEsc(paths.join("\n")) + " | wl-copy"];
        wlCopyProc.running = true;
    }

    // Run a user-defined command from Config.options.anoSpot.dropTargets.
    // Rule: { name, action: "exec"|"shell", command, perItem: bool }
    //   - exec   -> argv-split (safe), each arg goes through placeholder substitution
    //   - shell  -> bash -c <command after substitution> (full shell semantics)
    //   - perItem true  -> invoked once per staged item with {path}/{name}/{dir}/{ext}
    //     perItem false -> invoked once total with {paths} (newline-joined) + {names}
    function runCustomRule(rule) {
        if (!rule || !rule.command) return;
        const isShell = rule.action === "shell";
        if (rule.perItem) {
            for (let i = 0; i < itemsModel.count; i++) {
                _runRuleOnce(rule, isShell, [itemsModel.get(i)]);
            }
        } else {
            const all = [];
            for (let i = 0; i < itemsModel.count; i++) all.push(itemsModel.get(i));
            _runRuleOnce(rule, isShell, all);
        }
    }

    function _runRuleOnce(rule, isShell, items) {
        const first = items[0] || { filePath: "", name: "", isDir: false };
        const vals = {
            path: first.filePath, name: first.name,
            dir: first.filePath.replace(/\/[^\/]*$/, ""),
            ext: (first.name.match(/\.([^.]+)$/) || [, ""])[1],
            paths: items.map(i => i.filePath).join("\n"),
            names: items.map(i => i.name).join("\n")
        };
        const subst = (str) => String(str).replace(/\{(paths|names|path|name|dir|ext)\}/g, (_, k) => vals[k]);
        if (isShell) {
            // Shell mode: the values travel as environment variables, never as
            // shell text, so a file called `$(cmd).png` stays a name.
            const env = {};
            for (const k in vals) env["ANO_" + k.toUpperCase()] = vals[k];
            customProc.environment = env;
            customProc.command = ["bash", "-c", String(rule.command).replace(/\{(paths|names|path|name|dir|ext)\}/g, (_, k) => "${ANO_" + k.toUpperCase() + "}")];
        } else {
            customProc.environment = ({});
            // Exec mode: split on whitespace, substitute each arg.
            const argv = String(rule.command).trim().split(/\s+/).map(subst);
            customProc.command = argv;
        }
        customProc.running = true;
    }

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
        id: discoverProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.discoverState !== "scanning") return;
                discoveredDevicesModel.clear();
                const lines = (this.text || "").split("\n");
                for (const line of lines) {
                    const t = line.trim();
                    if (!t) continue;
                    const tab = t.indexOf("\t");
                    if (tab < 0) continue;
                    const alias = t.substring(0, tab);
                    const ip = t.substring(tab + 1);
                    if (alias && ip) discoveredDevicesModel.append({ alias: alias, ip: ip });
                }
                root.discoverState = "ready";
            }
        }
    }

    Process {
        id: sendProc
        onExited: (code, _) => {
            if (code !== 0)
                console.warn("[AnoSpotStash] localsend_send exited", code);
        }
    }

    Process {
        id: xdgOpenProc
        onExited: (code, _) => {
            if (code !== 0)
                console.warn("[AnoSpotStash] xdg-open exited", code);
        }
    }

    Process {
        id: wlCopyProc
        onExited: (code, _) => {
            if (code !== 0)
                console.warn("[AnoSpotStash] wl-copy exited", code);
        }
    }

    Process {
        id: customProc
        onExited: (code, _) => {
            if (code !== 0)
                console.warn("[AnoSpotStash] custom command exited", code);
        }
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
