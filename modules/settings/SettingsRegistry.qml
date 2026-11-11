pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "."

/**
 * Registry powering the Settings command palette.
 *
 * Builds a search index dynamically from two live sources:
 *
 *   1. Config.options — every leaf and intermediate key in the user's
 *      JSON config becomes a search entry. New keys added to the schema
 *      automatically appear in search; no static list to keep in sync.
 *
 *   2. The per-page configRoots declared on each SettingsPageHeader —
 *      maps top-level config roots to the Settings page that owns them.
 *
 * Entry shape (per leaf):
 *
 *   {
 *     key: "anoSpot.eventBorder.holdMs",
 *     pageIndex: 6,             // index into SettingsOverlay.pages
 *     pageName: "AnoSpot",      // human-readable
 *     pageIcon: "view_compact_alt",
 *     haystack: "anoSpot.eventBorder.holdMs anoSpot AnoSpot eventBorder holdMs",
 *   }
 *
 * Card-level resolution (for scroll-to-card) is performed at click time
 * by SettingsCommandPalette, which walks the loaded page's children for
 * a SettingsCard whose configKeys list covers the entry's key — that
 * avoids needing a parallel static map of cards.
 *
 * The canonical page list (index → name + icon + roots) lives here as
 * `pages`; the overlay and the standalone settings window both read it.
 */
Singleton {
    id: root

    // The one Settings page list, shared by the overlay and the standalone
    // window: name + icon for the rail, plus the configRoots each page owns
    // (top-level keys + dotted-path overrides) so the palette can resolve a
    // typed key to its page.
    readonly property var pages: [
        { name: "About",      icon: "info",            configRoots: ["user"] },
        { name: "General",    icon: "tune",            configRoots: ["audio", "battery", "time", "notifications", "interactions", "sounds.battery", "session", "polkit"] },
        { name: "Modules",    icon: "extension",       configRoots: ["disabledPanels", "enabledPanels", "panelFamily", "familyTransitionAnimation", "osd", "deviceEvents", "screenCorners", "altSwitcher", "apps", "focusTime", "taskView", "media", "compositor", "hacks", "displayManager", "display.primaryMonitor", "sounds.theme", "bar.morphingPanels", "reader", "search", "livePins", "widgets"] },
        { name: "Bar",        icon: "dock_to_bottom",  configRoots: ["bar", "bars", "tray"] },
        { name: "Dock",       icon: "space_dashboard", configRoots: ["dock"] },
        { name: "Sidebars",   icon: "view_sidebar",    configRoots: ["sidebar", "notepad", "todo", "pomodoro", "stickyNotes", "clock"] },
        { name: "AnoSpot",    icon: "view_compact_alt",configRoots: ["anoSpot"] },
        { name: "Appearance", icon: "palette",         configRoots: ["appearance", "background", "animations", "settings.softenWallpaper"] },
        { name: "Overview",   icon: "overview",        configRoots: ["overview"] },
        { name: "Services",   icon: "cloud",           configRoots: ["ai", "gameMode", "performance", "updates", "musicRecognition", "powerProfiles", "network", "vpn", "kdeConnect", "nightLight", "location", "lyrics", "calendar", "resources", "light", "shell", "weather", "recording", "screenFilter", "drives"] },
        { name: "Displays",   icon: "desktop_windows", configRoots: ["cursor", "icons"] },
        { name: "Keybinds",   icon: "keyboard",        configRoots: ["keyboard"] },
        { name: "Atelier",    icon: "design_services", configRoots: ["atelier"] },
        { name: "Actions",    icon: "bolt",            configRoots: ["actions"] },
    ]

    // Cached search index — recomputed when pages or config schema changes.
    property var entries: []

    // Token-set tokens of the current query, lower-cased and trimmed.
    // Empty array means "show everything"; otherwise every token must
    // appear in an entry's haystack.
    property var _queryTokens: []
    property string query: ""

    // Filtered + ranked subset of `entries` matching the current query.
    property var results: []

    onQueryChanged: {
        const q = (root.query || "").trim().toLowerCase();
        root._queryTokens = q.length === 0 ? [] : q.split(/\s+/).filter(t => t.length > 0);
        root._refilter();
    }

    // The index walks every config key (~0.5 s), so it is built lazily the
    // first time the palette opens rather than at shell startup.
    property bool _indexDirty: true
    function ensureIndex() {
        if (root._indexDirty) { root._indexDirty = false; root._rebuildIndex(); }
    }

    // Rebuild on demand if the host shell wants to refresh after config
    // reloads (Config emits readyChanged once the bundle + delta apply).
    function rebuild() { root._rebuildIndex(); }

    // ── Index build ────────────────────────────────────────────────────

    function _rebuildIndex() {
        const opts = Config.options;
        if (!opts) {
            root.entries = [];
            root.results = [];
            return;
        }
        const out = [];
        // Walk every key path in Config.options. Both leaves and
        // intermediate objects emit entries — searching "anoSpot" should
        // match both a top-level subtree and individual leaves.
        root._walk(opts, "", out);
        root._addControlLabels(out);
        root.entries = out;
        root._refilter();
    }

    // Generated by scripts/dev/settings-index.py: card titles/subtitles and
    // control labels/sublabels with the keys they write. Their words join the
    // matching key's haystack so controls are found by what the user reads.
    FileView {
        id: labelIndexFile
        path: Qt.resolvedUrl("settings-index.json")
        blockLoading: true // tiny file, read once on first palette open
    }

    function _addControlLabels(out) {
        let index = [];
        try { index = JSON.parse(labelIndexFile.text() || "[]"); } catch (e) { return; }
        const byKey = {};
        for (const entry of out) byKey[entry.key] = entry;
        for (const item of index) {
            const words = [item.card, item.label, item.sublabel].join(" ").toLowerCase();
            // A card that writes no setting (Backup, Presets) is found by its title.
            if (!(item.keys || []).length && item.card && item.label === item.card) {
                const page = root.pages[item.page];
                if (page) out.push({ key: "card:" + item.card, label: item.card, card: true, pageIndex: item.page,
                                     pageName: page.name, pageIcon: page.icon, haystack: words + " " + page.name.toLowerCase() });
                continue;
            }
            for (const key of (item.keys || [])) {
                let entry = byKey[key];
                if (!entry) {
                    const page = root.pages[item.page];
                    if (!page) continue;
                    entry = { key: key, pageIndex: item.page, pageName: page.name, pageIcon: page.icon,
                              haystack: root._buildHaystack(key, page.name) };
                    byKey[key] = entry;
                    out.push(entry);
                }
                entry.haystack += " " + words;
                if (item.advanced) entry.advanced = true;
                if (!entry.label && !item.card) entry.label = item.label; // shown in the palette row
            }
        }
    }

    function _walk(obj, prefix, out) {
        if (!obj || typeof obj !== "object") return;
        // QML JsonAdapter properties enumerate as plain JS-object keys.
        for (const key in obj) {
            if (key.startsWith("_") || key.startsWith("on") || key === "objectName") continue;
            const value = obj[key];
            if (typeof value === "function") continue;
            const path = prefix.length === 0 ? key : `${prefix}.${key}`;

            const pageInfo = root._resolvePage(path);
            // Every path that resolves to a known page becomes an entry.
            if (pageInfo) {
                out.push({
                    key: path,
                    pageIndex: pageInfo.index,
                    pageName: pageInfo.name,
                    pageIcon: pageInfo.icon,
                    haystack: root._buildHaystack(path, pageInfo.name)
                });
            }
            // Recurse into plain objects (skip arrays — they're values, not subtrees).
            const isPlainObject = value && typeof value === "object"
                && !Array.isArray(value) && !(value instanceof Date);
            if (isPlainObject) {
                root._walk(value, path, out);
            }
        }
    }

    // Find the page whose configRoots cover this dotted path.
    // Matches in priority order: exact dotted path > top-level root.
    function _resolvePage(path) {
        const top = path.split(".")[0];
        let topMatch = null;
        for (let i = 0; i < root.pages.length; ++i) {
            const page = root.pages[i];
            const roots = page.configRoots || [];
            // Exact dotted-path hit beats top-level
            for (const r of roots) {
                if (r === path) {
                    return { index: i, name: page.name, icon: page.icon };
                }
            }
            for (const r of roots) {
                if (r === top && !topMatch) {
                    topMatch = { index: i, name: page.name, icon: page.icon };
                }
            }
        }
        return topMatch;
    }

    // The haystack a query is matched against. Includes the dotted path,
    // its individual segments (so "holdMs" matches "anoSpot.eventBorder.holdMs"
    // typed as just "holdms"), and the page name.
    function _buildHaystack(path, pageName) {
        const segments = path.split(".");
        // Also produce camel-case-split tokens, so "hold ms" and "event border"
        // match the run-on identifiers. QtJS doesn't always have flatMap,
        // so concat manually.
        const camelSplit = [];
        for (const s of segments) {
            const parts = s.replace(/([a-z])([A-Z])/g, "$1 $2").split(/\s+/);
            for (const p of parts) camelSplit.push(p);
        }
        return [path, pageName].concat(segments).concat(camelSplit).join(" ").toLowerCase();
    }

    // ── Filter / rank ──────────────────────────────────────────────────

    function _refilter() {
        const tokens = root._queryTokens;
        if (tokens.length === 0) {
            // No query — show top entries by some sensible default. Use
            // page index ascending so users see the natural Settings order.
            root.results = root.entries.slice(0, 50).sort((a, b) => {
                if (a.pageIndex !== b.pageIndex) return a.pageIndex - b.pageIndex;
                return a.key.localeCompare(b.key);
            });
            return;
        }
        // Every token must appear somewhere in the haystack (AND across tokens,
        // case-insensitive substring match — already lower-cased on store).
        // Punctuation and spacing don't count either: "wifi" finds "Wi-Fi",
        // "hotcorner" finds "hot corners" (both sides squashed to [a-z0-9]).
        const squash = t => t.replace(/[^a-z0-9]+/g, "");
        const sq = tokens.map(squash);
        const matches = root.entries.filter(e => {
            if (e._squashed === undefined) e._squashed = squash(e.haystack);
            for (let i = 0; i < tokens.length; i++)
                if (e.haystack.indexOf(tokens[i]) < 0 && (sq[i].length === 0 || e._squashed.indexOf(sq[i]) < 0)) return false;
            return true;
        });
        // Rank: the label typed exactly, then a label holding every token, then
        // a key path holding every token; shorter key wins ties.
        const whole = sq.join("");
        const labelRank = e => {
            const l = squash(String(e.label ?? "").toLowerCase());
            return l.length === 0 ? 0 : l === whole ? 2 : sq.every(t => l.indexOf(t) >= 0) ? 1 : 0;
        };
        matches.sort((a, b) => {
            const lr = labelRank(b) - labelRank(a);
            if (lr !== 0) return lr;
            // Prefer entries whose key path itself contains all tokens
            const aKey = a.key.toLowerCase();
            const bKey = b.key.toLowerCase();
            const aHits = tokens.every(t => aKey.indexOf(t) >= 0) ? 1 : 0;
            const bHits = tokens.every(t => bKey.indexOf(t) >= 0) ? 1 : 0;
            if (aHits !== bHits) return bHits - aHits;
            return a.key.length - b.key.length;
        });
        root.results = matches.slice(0, 100);
    }

    // Refresh the index when the config becomes ready (initial load) or
    // reloads (user edited the file externally).
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) root._rebuildIndex(); }
    }
    Component.onCompleted: { if (Config.ready) root._rebuildIndex(); }
}
