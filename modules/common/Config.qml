pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common.functions

Singleton {
    id: root
    property string filePath: Directories.shellConfigPath
    property alias options: configOptionsJsonAdapter
    property bool ready: false
    property int readWriteDelay: 50 // milliseconds
    property bool blockWrites: false

    // Set nested config value by dot-path (e.g., "bar.position")
    function setNestedValue(nestedKey, value) {
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
                // ~/.config/ano/themes/<static>.json — user dir takes
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
}
