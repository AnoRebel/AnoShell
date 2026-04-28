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
    property bool blockWrites: false

    // Dot-paths that are sourced from the user override file. Writes to
    // these via setNestedValue still happen but emit a console warning
    // because the next reload will overwrite the change with the user's
    // override value.
    property var _shadowedPaths: ({})

    // Set nested config value by dot-path (e.g., "bar.position")
    function setNestedValue(nestedKey, value) {
        if (root._shadowedPaths[nestedKey]) {
            console.warn(`[Config] "${nestedKey}" is set by ${root.userOverridePath}; this write will be reverted on next reload`);
        }
        let keys = nestedKey.split(".");
        let obj = root.options;
        let parents = [obj];
        for (let i = 0; i < keys.length - 1; ++i) {
            if (!obj[keys[i]] || typeof obj[keys[i]] !== "object") {
                obj[keys[i]] = {};
            }
            obj = obj[keys[i]];
            parents.push(obj);
        }
        // Auto-convert string booleans/numbers
        let convertedValue = value;
        if (typeof value === "string") {
            let trimmed = value.trim();
            if (trimmed === "true" || trimmed === "false" || !isNaN(Number(trimmed))) {
                try { convertedValue = JSON.parse(trimmed); } catch (e) { convertedValue = value; }
            }
        }
        obj[keys[keys.length - 1]] = convertedValue;
    }

    // Recursively merge `override` into `target`. Plain objects are merged;
    // arrays and scalars replace target's value. Returns the list of
    // dot-paths that were shadowed by the override.
    function _deepMergeInto(target, override, prefix) {
        const shadowed = [];
        if (!override || typeof override !== "object" || Array.isArray(override))
            return shadowed;
        for (const key in override) {
            const value = override[key];
            const path = prefix ? `${prefix}.${key}` : key;
            const isPlainObject = value && typeof value === "object" && !Array.isArray(value);
            if (isPlainObject && target[key] && typeof target[key] === "object" && !Array.isArray(target[key])) {
                shadowed.push(...root._deepMergeInto(target[key], value, path));
            } else {
                target[key] = value;
                shadowed.push(path);
            }
        }
        return shadowed;
    }

    function _applyUserOverrides() {
        const text = (userOverrideFileView.text() || "").trim();
        root._shadowedPaths = {};
        if (text.length === 0) return;
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            console.warn(`[Config] failed to parse ${root.userOverridePath}: ${e.message}`);
            return;
        }
        if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
            console.warn(`[Config] ${root.userOverridePath} must contain a JSON object`);
            return;
        }
        const shadowed = root._deepMergeInto(root.options, parsed, "");
        const map = {};
        for (const p of shadowed) map[p] = true;
        root._shadowedPaths = map;
        if (shadowed.length > 0) {
            console.log(`[Config] applied ${shadowed.length} key(s) from ${root.userOverridePath}`);
        }
    }

    Timer {
        id: fileReloadTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: configFileView.reload()
    }

    // One-shot migration of legacy config keys.
    // Idempotent: only acts when a legacy key is present.
    function _migrateLegacyKeys() {
        const opts = root.options;
        if (!opts) return;
        let changed = false;

        // activSpot -> anoSpot (module rename)
        if (opts.activSpot && !opts.anoSpot) {
            opts.anoSpot = opts.activSpot;
            changed = true;
        }
        if (opts.activSpot) {
            delete opts.activSpot;
            changed = true;
        }

        if (changed) fileWriteTimer.restart();
    }

    Timer {
        id: fileWriteTimer
        interval: root.readWriteDelay
        repeat: false
        onTriggered: configFileView.writeAdapter()
    }

    FileView {
        id: configFileView
        path: root.filePath
        watchChanges: true
        blockWrites: root.blockWrites
        onFileChanged: fileReloadTimer.restart()
        onAdapterUpdated: fileWriteTimer.restart()
        onLoaded: {
            root._migrateLegacyKeys();
            // Re-read the override file each time the bundle reloads, so
            // override edits made via an external editor are picked up too.
            userOverrideFileView.reload();
            root._applyUserOverrides();
            root.ready = true;
        }
        onLoadFailed: error => {
            if (error == FileViewError.FileNotFound) {
                writeAdapter();
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

    // User overrides — optional ~/.config/anoshell/config.json that's
    // deep-merged on top of the bundled config. Read-only at runtime: any
    // key set here wins over Settings-page edits, which will be reverted
    // on the next reload (with a console warning at write time).
    FileView {
        id: userOverrideFileView
        path: root.userOverridePath
        watchChanges: true
        blockWrites: true
        onFileChanged: configFileView.reload()
        // Missing file is fine — the override layer is opt-in.
    }
}
