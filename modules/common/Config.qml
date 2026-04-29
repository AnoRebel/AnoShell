pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property string userOverridePath: Directories.userConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int readWriteDelay: 50 // milliseconds

    // The user's per-machine delta. Sparse JS object — only keys the user
    // has actually changed live here. Writes from setNestedValue land
    // here, then get serialized to userOverridePath. The bundled config
    // is never written to.
    property var _userDelta: ({})
    // Suppresses the file-changed echo when we're the one writing.
    property bool _writingUserDelta: false

    // Walk a dot-path on `obj`, creating empty objects as needed for
    // intermediate segments. Returns [parent, leafKey] so the caller can
    // assign or delete the leaf.
    function _walkPath(obj, dotPath, createMissing) {
        const keys = dotPath.split(".");
        let cur = obj;
        for (let i = 0; i < keys.length - 1; ++i) {
            if (cur[keys[i]] === undefined || cur[keys[i]] === null
                || typeof cur[keys[i]] !== "object" || Array.isArray(cur[keys[i]])) {
                if (!createMissing) return [null, null];
                cur[keys[i]] = {};
            }
            cur = cur[keys[i]];
        }
        return [cur, keys[keys.length - 1]];
    }

    // Set nested config value by dot-path (e.g., "bar.position").
    // Writes both to live in-memory state (so UI updates immediately) AND
    // to the user delta (so the change persists to ~/.config/anoshell/config.json).
    function setNestedValue(nestedKey, value) {
        // Auto-convert string booleans/numbers — keeps existing call sites working
        let convertedValue = value;
        if (typeof value === "string") {
            const trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try { convertedValue = JSON.parse(trimmed); } catch (e) { convertedValue = value; }
            }
        }

        // 1. Live in-memory mutation — UI sees the change this tick
        const [liveParent, liveLeaf] = root._walkPath(root.options, nestedKey, true);
        liveParent[liveLeaf] = convertedValue;

        // 2. User delta mutation — persists to disk
        const [deltaParent, deltaLeaf] = root._walkPath(root._userDelta, nestedKey, true);
        deltaParent[deltaLeaf] = convertedValue;

        userDeltaWriteTimer.restart();
    }

    // Reset a dot-path to its bundled default. Removes the key from the
    // user delta and restores the in-memory value from the freshly-loaded
    // bundle defaults. Empty intermediate objects in the delta are
    // pruned so the file stays tidy.
    function resetToDefault(nestedKey) {
        // Remove from delta and prune empty parents
        const segments = nestedKey.split(".");
        const trail = [root._userDelta];
        for (let i = 0; i < segments.length - 1; ++i) {
            const next = trail[trail.length - 1][segments[i]];
            if (!next || typeof next !== "object") return; // not in delta
            trail.push(next);
        }
        delete trail[trail.length - 1][segments[segments.length - 1]];
        for (let i = trail.length - 1; i > 0; --i) {
            if (Object.keys(trail[i]).length === 0) {
                delete trail[i - 1][segments[i - 1]];
            } else {
                break;
            }
        }

        // Restore live value from bundle defaults
        const [bundleParent, bundleLeaf] = root._walkPath(root._bundleDefaults, nestedKey, false);
        if (bundleParent !== null && bundleLeaf in bundleParent) {
            const [liveParent, liveLeaf] = root._walkPath(root.options, nestedKey, true);
            liveParent[liveLeaf] = bundleParent[bundleLeaf];
        }

        userDeltaWriteTimer.restart();
    }

    // Bundled-defaults snapshot — parsed once on bundle load, used by
    // resetToDefault to restore values without re-reading the file.
    property var _bundleDefaults: ({})

    // Recursively merge `override` into `target`. Plain objects are merged;
    // arrays and scalars replace target's value.
    function _deepMergeInto(target, override) {
        if (!override || typeof override !== "object" || Array.isArray(override))
            return;
        for (const key in override) {
            const value = override[key];
            const isPlainObject = value && typeof value === "object" && !Array.isArray(value);
            if (isPlainObject && target[key] && typeof target[key] === "object" && !Array.isArray(target[key])) {
                root._deepMergeInto(target[key], value);
            } else {
                target[key] = value;
            }
        }
    }

    // Deep-clone a plain JS structure. Used to snapshot the bundle so the
    // adapter's live mutations don't leak back into our defaults.
    function _deepClone(obj) {
        if (obj === null || obj === undefined) return obj;
        if (typeof obj !== "object") return obj;
        if (Array.isArray(obj)) return obj.map(v => root._deepClone(v));
        const out = {};
        for (const k in obj) out[k] = root._deepClone(obj[k]);
        return out;
    }

    // Snapshot the JsonAdapter's current state into a plain JS object.
    // Used to capture bundled defaults right after bundle load (before the
    // user delta is merged in).
    function _snapshotAdapter(adapter) {
        const out = {};
        for (const key in adapter) {
            // Skip QML internals / signals / functions
            if (key.startsWith("_") || key.startsWith("on")) continue;
            const v = adapter[key];
            if (typeof v === "function") continue;
            if (v && typeof v === "object" && typeof v.objectName === "string") {
                // Nested JsonObject
                out[key] = root._snapshotAdapter(v);
            } else {
                out[key] = root._deepClone(v);
            }
        }
        return out;
    }

    function _loadUserDelta() {
        const text = (userOverrideFileView.text() || "").trim();
        if (text.length === 0) {
            root._userDelta = {};
            return;
        }
        try {
            const parsed = JSON.parse(text);
            if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
                console.warn(`[Config] ${root.userOverridePath} must contain a JSON object`);
                root._userDelta = {};
                return;
            }
            root._userDelta = parsed;
        } catch (e) {
            console.warn(`[Config] failed to parse ${root.userOverridePath}: ${e.message}`);
            root._userDelta = {};
        }
    }

    function _applyUserDelta() {
        if (Object.keys(root._userDelta).length === 0) return;
        root._deepMergeInto(root.options, root._userDelta);
    }

    function _writeUserDelta() {
        root._writingUserDelta = true;
        const text = JSON.stringify(root._userDelta, null, 2) + "\n";
        userOverrideFileView.setText(text);
        // Clear the echo-suppress flag after the file-watcher has had a
        // chance to fire. The watcher will fire ~10ms after setText; we
        // wait one readWriteDelay to be safe.
        echoClearTimer.restart();
    }

    Timer {
        id: bundleReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: configFileView.reload()
    }

    // Debounced write of the user delta. Multiple setNestedValue calls
    // within readWriteDelay coalesce into one disk write.
    Timer {
        id: userDeltaWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: root._writeUserDelta()
    }

    // After a setText call, swallow exactly one onFileChanged echo so we
    // don't reload-loop on our own writes.
    Timer {
        id: echoClearTimer
        interval: root.readWriteDelay * 4
        repeat: false
        onTriggered: root._writingUserDelta = false
    }

    // One-shot migration of legacy config keys.
    // Idempotent: only acts when a legacy key is present. Migrated keys
    // land in the user delta (since the bundle is now read-only).
    function _migrateLegacyKeys() {
        const opts = root.options;
        if (!opts) return;
        let migrated = false;

        // activSpot -> anoSpot (module rename)
        if (opts.activSpot && !opts.anoSpot) {
            // Copy into delta so the migration persists
            root._userDelta.anoSpot = root._deepClone(opts.activSpot);
            opts.anoSpot = opts.activSpot;
            migrated = true;
        }
        if (opts.activSpot) {
            // Can't actually delete from the bundled JsonAdapter — that
            // would write back. The legacy key stays harmlessly in the
            // bundle; the new key wins on read.
        }

        if (migrated) userDeltaWriteTimer.restart();
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        // Bundle is read-only — settings UI writes to the user delta.
        // Setting blockWrites prevents the adapter from echoing changes
        // back into the file we just loaded from.
        blockWrites: true
        onFileChanged: bundleReloadTimer.restart()
        onLoaded: {
            // Bundle reload resets the adapter to bundle defaults. We
            // re-snapshot the defaults (in case the bundle itself changed,
            // e.g. shell upgrade), then request a user-delta reload —
            // the actual apply (and legacy-key migration) happens in
            // userOverrideFileView.onLoaded, after _userDelta is populated.
            root._bundleDefaults = root._snapshotAdapter(configOptionsJsonAdapter);
            userOverrideFileView.reload();
            // ready flips after the delta has been applied (in user-file
            // onLoaded / onLoadFailed handlers).
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                console.warn(`[Config] bundled config not found at ${root.filePath} — using built-in defaults`);
                root._bundleDefaults = root._snapshotAdapter(configOptionsJsonAdapter);
                userOverrideFileView.reload();
            }
        }

        JsonAdapter {
            id: configOptionsJsonAdapter

            // ═══════════════════════════════════════════════════════════════
            // Panel Families
            // ═══════════════════════════════════════════════════════════════
            property string panelFamily: "ano" // "ano" default, extensible
            property JsonArray enabledPanels: JsonArray {
                // Dynamic module loading — list of panel IDs to activate
                // Populated by family defaults on first run
            }
            property bool familyTransitionAnimation: true

            // ═══════════════════════════════════════════════════════════════
            // Compositor
            // ═══════════════════════════════════════════════════════════════
            property JsonObject compositor: JsonObject {
                property string defaultCompositor: "hyprland" // fallback when env detection fails
            }

            // ═══════════════════════════════════════════════════════════════
            // Display & Bezel
            // ═══════════════════════════════════════════════════════════════
            property JsonObject display: JsonObject {
                property string primaryMonitor: "" // empty = auto (focused screen)
                property int bezel: 5 // Global gap/margin from screen edges (pixels) for ALL elements
                property bool respectHyprlandGaps: true // sync bezel with Hyprland gaps_out
            }

            // ═══════════════════════════════════════════════════════════════
            // Appearance
            // ═══════════════════════════════════════════════════════════════
            property JsonObject appearance: JsonObject {
                property bool extraBackgroundTint: true
                property int fakeScreenRounding: 2 // 0: None | 1: Always | 2: When not fullscreen

                property JsonObject fonts: JsonObject {
                    property string main: "Google Sans Flex"
                    property string numbers: "Google Sans Flex"
                    property string title: "Google Sans Flex"
                    property string iconNerd: "JetBrains Mono NF"
                    property string monospace: "JetBrains Mono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Space Grotesk"
                }

                property JsonObject transparency: JsonObject {
                    property bool enable: true
                    property bool automatic: true // auto-adjust based on wallpaper vibrancy
                    property real backgroundTransparency: 0.15
                    property real contentTransparency: 0.9
                }

                property JsonObject colors: JsonObject {
                    property bool materialYou: true // derive colors from wallpaper
                    property string manualScheme: "" // manual hex override (empty = auto)
                    property bool darkMode: true
                }

                // Theme source selector. When source === "materialYou", the
                // existing wallpaper-driven pipeline owns Appearance.m3colors.
                // When source === "static", StaticThemeLoader writes
                // Appearance.m3colors from assets/themes/<static>.json (or
                // ~/.config/anoshell/themes/<static>.json — user dir takes
                // precedence on name collision).
                property JsonObject theme: JsonObject {
                    property string source: "materialYou"  // "materialYou" | "static"
                    property string static: ""              // theme name without .json suffix
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // Bar System
            // ═══════════════════════════════════════════════════════════════
            property JsonObject bar: JsonObject {
                property string position: "top" // top, bottom, left, right
                property int cornerStyle: 0 // 0: Normal | 1: Floating (adds gaps)
                property bool verbose: false // verbose mode shows more info in bar modules
                property bool autoHide: false
                property int autoHideDelay: 1000 // ms

                // Multi-bar: array of bar definitions per monitor
                // Each bar has: id, position (top/bottom/left/right), modules (left/center/right arrays)
                property JsonArray bars: JsonArray {
                    // Default: single top bar (populated on first run)
                }

                // Module arrangement — drag-and-drop ordering
                property JsonArray modulesLeft: JsonArray {}
                property JsonArray modulesCenter: JsonArray {}
                property JsonArray modulesRight: JsonArray {}
            }

            // ═══════════════════════════════════════════════════════════════
            // Wallpaper & Background
            // ═══════════════════════════════════════════════════════════════
            property JsonObject background: JsonObject {
                property string wallpaperPath: ""
                property string thumbnailPath: "" // for video wallpapers
                property string wallpaperDir: "~/Pictures/hyprwallpapers"

                property JsonObject rotation: JsonObject {
                    property bool enabled: true
                    property int intervalMinutes: 30 // wallpaper rotation interval
                    property bool shuffle: true // random order vs sequential
                    property bool applyTheme: true // re-derive Material You colors on change
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // Overview & Task View
            // ═══════════════════════════════════════════════════════════════
            property JsonObject overview: JsonObject {
                property string layout: "SmartGrid" // one of 10 hyprview layouts
                property int numWorkspaces: 10
                property bool showEmptyWorkspaces: true
                property int gapSize: 5
            }

            property JsonObject taskView: JsonObject {
                property bool useInsteadOfOverview: false
                property string layout: "Hero" // layout for task view (can differ from overview)
            }

            // ═══════════════════════════════════════════════════════════════
            // Settings UI
            // ═══════════════════════════════════════════════════════════════
            property JsonObject settingsUi: JsonObject {
                property bool overlayMode: false // true = overlay panel, false = separate window
            }

            // ═══════════════════════════════════════════════════════════════
            // Wallpaper Selector
            // ═══════════════════════════════════════════════════════════════
            property JsonObject wallpaperSelector: JsonObject {
                property string selectionTarget: "main" // "main", "backdrop"
                property string targetMonitor: ""
            }

            // ═══════════════════════════════════════════════════════════════
            // Notifications
            // ═══════════════════════════════════════════════════════════════
            property JsonObject notifications: JsonObject {
                property bool silent: false
                property int popupTimeout: 5000 // ms
                property int maxVisible: 5
            }

            // ═══════════════════════════════════════════════════════════════
            // Media
            // ═══════════════════════════════════════════════════════════════
            property JsonObject media: JsonObject {
                property bool showEqualizer: true
                property string preferredPlayer: "" // empty = auto
            }

            // ═══════════════════════════════════════════════════════════════
            // Weather
            // ═══════════════════════════════════════════════════════════════
            property JsonObject weather: JsonObject {
                property string location: "" // empty = auto-detect
                property string unit: "metric" // metric, imperial
                property string provider: "openmeteo" // openmeteo (free, no key needed)
            }

            // ═══════════════════════════════════════════════════════════════
            // Animations
            // ═══════════════════════════════════════════════════════════════
            property JsonObject animations: JsonObject {
                property bool enabled: true
                property real speedMultiplier: 1.0 // global speed factor
            }

            // ═══════════════════════════════════════════════════════════════
            // HUD
            // ═══════════════════════════════════════════════════════════════
            property JsonObject hud: JsonObject {
                property bool enabled: true
                property int timeout: 2000 // ms
            }

            // ═══════════════════════════════════════════════════════════════
            // Session
            // ═══════════════════════════════════════════════════════════════
            property JsonObject session: JsonObject {
                property bool confirmLogout: true
                property bool confirmShutdown: true
            }
        }
    }

    // User per-machine config delta at ~/.config/anoshell/config.json.
    // The Settings UI writes here (via setNestedValue → _writeUserDelta).
    // External edits (text editor, git pull, scp from another machine) are
    // picked up via watchChanges and trigger a bundle reload, which then
    // re-applies the delta on top of bundle defaults.
    //
    // Echo suppression: when WE write the file, the watcher would fire and
    // cause a reload loop. We set _writingUserDelta=true around our own
    // writes; the onFileChanged handler skips a reload while it's set,
    // and echoClearTimer clears the flag a few ms later.
    FileView {
        id: userOverrideFileView
        path: root.userOverridePath
        watchChanges: true
        // Writes go via setText() in _writeUserDelta — never via an adapter.
        onFileChanged: {
            // Echo from our own setText — already applied in memory.
            if (root._writingUserDelta) return;
            // External edit: reload bundle to reset adapter to defaults,
            // then this view's onLoaded re-applies the (possibly smaller)
            // delta on top.
            bundleReloadTimer.restart();
        }
        onLoaded: {
            root._loadUserDelta();
            root._applyUserDelta();
            root._migrateLegacyKeys();
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root._userDelta = {};
                root._migrateLegacyKeys();
                root.ready = true;
            }
        }
    }
}
