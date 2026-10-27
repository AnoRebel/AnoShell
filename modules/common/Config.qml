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
    // Set by BarStyle (services can't be imported here): applies the pill/dock
    // edge swap rule for edges set over IPC.
    property var edgeMover: null
    // Bumped whenever the user delta changes, so origin bindings re-evaluate.
    property int deltaRevision: 0
    // Keys whose user value came from a legacy-key migration.
    property var _migratedKeys: ({})

    // Where a key's effective value comes from: "user" (your config file),
    // "migrated" (moved there from an old key) or "default" (bundled).
    function originOf(nestedKey) {
        void root.deltaRevision
        if (root._migratedKeys[nestedKey]) return "migrated"
        const [parent, leaf] = root._walkPath(root._userDelta, nestedKey, false)
        return (parent !== null && parent !== undefined && leaf in parent) ? "user" : "default"
    }
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
                || typeof cur[keys[i]] !== "object" || root._isArrayLike(cur[keys[i]])) {
                if (!createMissing) return [null, null];
                cur[keys[i]] = {};
            }
            cur = cur[keys[i]];
        }
        return [cur, keys[keys.length - 1]];
    }

    // Arrays read from a JsonAdapter list property are V4Sequence wrappers,
    // which Array.isArray rejects.
    function _isArrayLike(v) {
        return Array.isArray(v) || Object.prototype.toString.call(v) === "[object V4Sequence]"
    }

    // Walk keys inside an array/object value, stepping into arrays by index
    // and creating missing objects. Returns [parent, leafKey].
    function _walkArrayPath(obj, keys) {
        let cur = obj;
        for (let i = 0; i < keys.length - 1; ++i) {
            const k = Array.isArray(cur) ? Number(keys[i]) : keys[i];
            if (cur[k] === undefined || cur[k] === null || typeof cur[k] !== "object") cur[k] = {};
            cur = cur[k];
        }
        const last = keys[keys.length - 1];
        return [cur, Array.isArray(cur) ? Number(last) : last];
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

        // Paths into a top-level array (bars.0.groups) are copy-on-write: the
        // whole array is cloned, changed and assigned back, live and in the
        // delta. Assigning is what notifies bindings (reading a JsonAdapter
        // array gives a copy, so changing it in place is lost), and storing
        // the whole array keeps the delta an array, not {"0": …}.
        const keys = nestedKey.split(".");
        if (keys.length > 1 && root._isArrayLike(root.options[keys[0]])) {
            const arr = Array.from(JSON.parse(JSON.stringify(root.options[keys[0]])));
            const [p, leaf] = root._walkArrayPath(arr, keys.slice(1));
            if (JSON.stringify(p[leaf]) === JSON.stringify(convertedValue)) return;
            if (root.recordUndo)
                root.undoStack = root.undoStack.concat([{ key: nestedKey, mine: keys[0] in root._userDelta, old: p[leaf] === undefined ? null : JSON.parse(JSON.stringify(p[leaf])) }]);
            p[leaf] = convertedValue;
            root.options[keys[0]] = arr;
            root._userDelta[keys[0]] = JSON.parse(JSON.stringify(arr));
            userDeltaWriteTimer.restart();
            return;
        }

        // 1. Live in-memory mutation — UI sees the change this tick
        const [liveParent, liveLeaf] = root._walkPath(root.options, nestedKey, true);
        if (root.recordUndo && JSON.stringify(liveParent[liveLeaf]) !== JSON.stringify(convertedValue))
            root.undoStack = root.undoStack.concat([{ key: nestedKey, mine: root.originOf(nestedKey) === "user", old: liveParent[liveLeaf] === undefined ? null : JSON.parse(JSON.stringify(liveParent[liveLeaf])) }]);
        // No-op when nothing changes. Controls echo their initial value
        // through onValueChanged/onCheckedChanged at creation; without this
        // every such echo was persisted into the user delta (defaults written
        // into an untouched config on first start).
        if (JSON.stringify(liveParent[liveLeaf]) === JSON.stringify(convertedValue)) return;
        liveParent[liveLeaf] = convertedValue;

        // 2. User delta mutation — persists to disk
        const [deltaParent, deltaLeaf] = root._walkPath(root._userDelta, nestedKey, true);
        deltaParent[deltaLeaf] = convertedValue;

        userDeltaWriteTimer.restart();
    }

    // ── Undo (in-place Customize) ─────────────────────────────────────────
    // While recordUndo is on, every change pushes { key, old }; undo() puts
    // the last one back (written like any change).
    property bool recordUndo: false
    property var undoStack: []
    function undo() {
        if (root.undoStack.length === 0) return
        const last = root.undoStack[root.undoStack.length - 1]
        root.undoStack = root.undoStack.slice(0, -1)
        const was = root.recordUndo
        root.recordUndo = false
        // A key that was at its default goes back to the default (out of
        // your config file), not to a written copy of it.
        const top = last.key.split(".")[0]
        if (last.mine) root.setNestedValue(last.key, last.old)
        else root.resetToDefault(root._isArrayLike(root.options[top]) ? top : last.key)
        root.recordUndo = was
    }

    // ── Preview (presets) ─────────────────────────────────────────────────
    // preview({ "bar.style": "classic", … }) shows values live without
    // writing anything; cancelPreview() puts the previous ones back,
    // commitPreview() keeps them (written like any Settings change).
    property var _previewOld: null      // key → value before the preview
    property var _previewNew: null
    readonly property bool previewing: _previewOld !== null
    function preview(values) {
        if (root._previewOld !== null) root.cancelPreview()
        const old = {}
        for (const k of Object.keys(values)) {
            const keys = k.split(".")
            if (keys.length > 1 && root._isArrayLike(root.options[keys[0]])) {
                // Arrays (bars.0.edge): change a copy and assign it whole, as setNestedValue does.
                const top = "\u0000" + keys[0]
                if (!(top in old)) old[top] = JSON.parse(JSON.stringify(root.options[keys[0]]))
                const arr = Array.from(JSON.parse(JSON.stringify(root.options[keys[0]])))
                const [p, leaf] = root._walkArrayPath(arr, keys.slice(1))
                p[leaf] = values[k]
                root.options[keys[0]] = arr
                continue
            }
            const [p, leaf] = root._walkPath(root.options, k, true)
            old[k] = p[leaf] === undefined ? null : JSON.parse(JSON.stringify(p[leaf]))
            p[leaf] = values[k]
        }
        root._previewOld = old
        root._previewNew = values
    }
    function cancelPreview() {
        if (root._previewOld === null) return
        for (const k of Object.keys(root._previewOld)) {
            if (k.startsWith("\u0000")) { root.options[k.slice(1)] = root._previewOld[k]; continue }
            const [p, leaf] = root._walkPath(root.options, k, true)
            p[leaf] = root._previewOld[k]
        }
        root._previewOld = null
        root._previewNew = null
    }
    function commitPreview() {
        if (root._previewOld === null) return
        const vals = root._previewNew
        root.cancelPreview() // back to the stored values, so setNestedValue sees a change
        for (const k of Object.keys(vals)) root.setNestedValue(k, vals[k])
    }
    // The user's settings as a preset: every key they changed (dotted), minus
    // anything that looks like a credential (keys live in secrets/, but be sure).
    function exportValues() {
        const out = {}
        const walk = (obj, prefix) => {
            for (const k of Object.keys(obj)) {
                const path = prefix ? `${prefix}.${k}` : k
                const v = obj[k]
                if (/key|token|secret|password|passwd|cookie/i.test(k)) continue
                if (v && typeof v === "object" && !Array.isArray(v)) walk(v, path)
                else out[path] = v
            }
        }
        walk(root._userDelta, "")
        return out
    }

    // True when at least one key has been overridden by the user.
    readonly property bool hasUserOverrides: {
        // Re-evaluate when _userDelta changes
        const d = root._userDelta;
        if (!d) return false;
        for (const _ in d) return true;
        return false;
    }

    // True when any of the given top-level config keys is in the user
    // delta. Used by per-page Settings headers to show/hide their reset
    // affordance based on whether that page has any overridden values.
    function hasOverridesForRoots(roots) {
        const d = root._userDelta;
        if (!d || !roots) return false;
        for (const r of roots)
            if (d[r] !== undefined) return true;
        return false;
    }

    // Wipe the entire user delta and restore every value to the bundle
    // default. Triggers one disk write; the user file becomes "{}\n".
    function resetAllToDefaults() {
        root._userDelta = {};
        root._migratedKeys = {};
        // Adapter is currently the merged state. Force a bundle reload
        // to re-baseline cleanly — this re-snapshots defaults, then
        // applies the (now empty) delta, which is a no-op.
        configFileView.reload();
        userDeltaWriteTimer.restart();
    }

    // Reset multiple dot-paths (or top-level keys) in one shot. Useful
    // for "Reset this page" buttons in the Settings UI — pass the page's
    // configRoots and every key under those subtrees clears.
    function resetPaths(paths) {
        if (!paths || paths.length === 0) return;
        let touched = false;
        for (const p of paths) {
            if (typeof p !== "string" || p.length === 0) continue;
            // Top-level shortcut: delete the whole subtree at once
            if (!p.includes(".")) {
                if (root._userDelta[p] !== undefined) {
                    delete root._userDelta[p];
                    touched = true;
                }
                for (const k of Object.keys(root._migratedKeys))
                    if (k === p || k.startsWith(p + ".")) delete root._migratedKeys[k];
            } else {
                root.resetToDefault(p);
                touched = true;
                continue; // resetToDefault already restores live + schedules write
            }
        }
        if (touched) {
            // Force a bundle reload to re-baseline any top-level subtrees
            // we just cleared (they need to revert from the merged value
            // back to the bundle default).
            configFileView.reload();
            userDeltaWriteTimer.restart();
        }
    }

    // Reset a dot-path to its bundled default. Removes the key from the
    // user delta and restores the in-memory value from the freshly-loaded
    // bundle defaults. Empty intermediate objects in the delta are
    // pruned so the file stays tidy.
    function resetToDefault(nestedKey) {
        delete root._migratedKeys[nestedKey];
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
    // A key the schema doesn't have (typo, old or newer key) or a value of the
    // wrong type is skipped with a warning; before, the throw aborted the merge
    // and every later user setting was silently lost. `ano config validate`
    // lists such keys.
    function _deepMergeInto(target, override, prefix) {
        if (!override || typeof override !== "object" || Array.isArray(override))
            return;
        for (const key in override) {
            const value = override[key];
            const path = prefix ? `${prefix}.${key}` : key;
            const isPlainObject = value && typeof value === "object" && !Array.isArray(value);
            if (isPlainObject && root._isArrayLike(target[key]) && Object.keys(value).every(k => /^\d+$/.test(k))) {
                // Older deltas saved array edits as {"0": {…}}: merge per index.
                const arr = JSON.parse(JSON.stringify(target[key]));
                for (const k in value) {
                    const i = Number(k);
                    if (arr[i] && typeof arr[i] === "object" && value[k] && typeof value[k] === "object") root._deepMergeInto(arr[i], value[k], `${path}.${k}`);
                    else arr[i] = value[k];
                }
                target[key] = arr;
            } else if (isPlainObject && target[key] && typeof target[key] === "object" && !root._isArrayLike(target[key])) {
                root._deepMergeInto(target[key], value, path);
            } else {
                try {
                    target[key] = value;
                } catch (e) {
                    console.warn(`[Config] ignoring ${path}: ${e.message ?? e}`);
                }
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

    // Fire a desktop notification about a config error. Critical urgency
    // so the user sees it even if DND is on. App name "Ano Shell" so it's
    // grouped with other shell-originated notifications.
    function _notifyConfigError(summary, body) {
        Quickshell.execDetached([
            "notify-send",
            "-u", "critical",
            "-a", "Ano Shell",
            "-i", "dialog-error",
            summary,
            body
        ]);
    }

    // Pull a human-readable position string out of a SyntaxError. JS engines
    // report line/column inconsistently — try to find any of the common
    // patterns and fall back to the raw message.
    function _formatJsonErrorLocation(rawMessage, text) {
        const m = String(rawMessage || "");
        // Pattern: "at line 5 column 12" or "line 5 column 12"
        const lineCol = m.match(/line\s+(\d+)\s+column\s+(\d+)/i);
        if (lineCol) return `line ${lineCol[1]}, column ${lineCol[2]}`;
        // Pattern: "at position 42"
        const pos = m.match(/position\s+(\d+)/i);
        if (pos) {
            const idx = parseInt(pos[1], 10);
            const before = text.slice(0, idx);
            const line = before.split("\n").length;
            const lastNl = before.lastIndexOf("\n");
            const col = lastNl < 0 ? idx + 1 : idx - lastNl;
            return `line ${line}, column ${col}`;
        }
        return null;
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
                const msg = `${root.userOverridePath} must contain a JSON object (got ${Array.isArray(parsed) ? "array" : typeof parsed}). Last-known config kept.`;
                console.warn(`[Config] ${msg}`);
                root._notifyConfigError("Config error", msg);
                // Don't clobber _userDelta — keep the last good state in memory
                return;
            }
            root._userDelta = parsed;
            root.deltaRevision++;
        } catch (e) {
            const where = root._formatJsonErrorLocation(e.message, text);
            const detail = where ? `${e.message} (${where})` : e.message;
            const msg = `Could not parse ${root.userOverridePath}: ${detail}. Last-known config kept.`;
            console.warn(`[Config] ${msg}`);
            root._notifyConfigError("Config parse error", msg);
            // Keep prior _userDelta — better than nuking the user's settings
            // because of a stray comma
        }
    }

    function _applyUserDelta() {
        if (Object.keys(root._userDelta).length === 0) return;
        root._deepMergeInto(root.options, root._userDelta);
    }

    function _writeUserDelta() {
        root.deltaRevision++;
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

        // bar.weather.enableGPS and nightLight.latitude/longitude moved to
        // location (mode auto, or manual coordinates).
        const wBlock = root._userDelta?.bar?.weather;
        if (wBlock && wBlock.enableGPS !== undefined) { delete wBlock.enableGPS; migrated = true; }
        const nlOld = root._userDelta?.nightLight;
        if (nlOld && (nlOld.latitude !== undefined || nlOld.longitude !== undefined)) {
            if ((nlOld.latitude || nlOld.longitude) && root._userDelta?.location?.mode === undefined) {
                root._userDelta.location = Object.assign(root._userDelta.location ?? {}, { mode: "manual", latitude: nlOld.latitude ?? 0, longitude: nlOld.longitude ?? 0 });
                opts.location.mode = "manual"; opts.location.latitude = nlOld.latitude ?? 0; opts.location.longitude = nlOld.longitude ?? 0;
                root._migratedKeys["location.mode"] = true;
            }
            delete nlOld.latitude; delete nlOld.longitude;
            migrated = true;
        }

        // nightLight.mode "schedule" (enable + sun times) -> nightLight.schedule "sun";
        // enable is now the "warm now" toggle.
        const nlBlock = root._userDelta?.nightLight;
        if (nlBlock && nlBlock.mode !== undefined) {
            if (nlBlock.mode === "schedule" && nlBlock.schedule === undefined) {
                nlBlock.schedule = "sun";
                nlBlock.enable = false;
                opts.nightLight.schedule = "sun";
                opts.nightLight.enable = false;
                root._migratedKeys["nightLight.schedule"] = true;
            }
            delete nlBlock.mode;
            migrated = true;
        }

        // hud.enabled -> hud.enable (the HUD always read `enable`).
        const hudBlock = root._userDelta?.hud;
        if (hudBlock && hudBlock.enabled !== undefined) {
            if (hudBlock.enable === undefined) hudBlock.enable = hudBlock.enabled;
            root._migratedKeys["hud.enable"] = true;
            delete hudBlock.enabled;
            opts.hud.enable = hudBlock.enable;
            migrated = true;
        }

        // appearance.theme.static -> appearance.theme.name. The previous
        // property name `static` is a QML reserved word and broke shell
        // load; rename for the schema, migrate any user-delta value over.
        const themeBlock = root._userDelta?.appearance?.theme;
        if (themeBlock && typeof themeBlock === "object") {
            // The migrated leaf may be the literal "static" key in JS-object
            // form because the file was edited externally before the rename.
            if (typeof themeBlock["static"] === "string"
                && themeBlock["static"].length > 0
                && (!themeBlock.name || themeBlock.name.length === 0)) {
                themeBlock.name = themeBlock["static"];
                delete themeBlock["static"];
                migrated = true;
            } else if (themeBlock["static"] !== undefined) {
                // Stale empty value — drop it.
                delete themeBlock["static"];
                migrated = true;
            }
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
            // Dynamic module loading — list of panel IDs to activate.
            // Populated by family defaults on first run. Empty array means
            // "all modules enabled" (see ModulesConfig for the convention).
            property var enabledPanels: []
            // Modules switched off in Settings → Modules (empty = none). Supersedes
            // enabledPanels, which is only read for configs that still have it.
            property var disabledPanels: []
            property bool familyTransitionAnimation: true

            // ═══════════════════════════════════════════════════════════════
            // Compositor
            // ═══════════════════════════════════════════════════════════════
            property JsonObject compositor: JsonObject {
                // "auto" = detect from the session environment; otherwise force a
                // backend: "hyprland" | "niri" | "sway" | "mango" | "labwc" | "generic"
                // (sway, mango and labwc are experimental).
                property string backend: "auto"
            }

            // ═══════════════════════════════════════════════════════════════
            // Display & Bezel
            // ═══════════════════════════════════════════════════════════════
            property JsonObject display: JsonObject {
                property string primaryMonitor: "" // empty = auto (focused screen)
            }

            // ═══════════════════════════════════════════════════════════════
            // Appearance
            // ═══════════════════════════════════════════════════════════════
            property JsonObject appearance: JsonObject {
                // Look (looks/*.json or ~/.config/anoshell/looks/): "" follows the
                // panel family's default; familyLooks sets one per family.
                property string look: ""
                property var familyLooks: ({})
                // The look's surface texture (caustics, grain, grid, clay light).
                property bool lookTextures: true
                // Glass material on panels and cards, with any look: a tint over
                // the compositor's blur, wallpaper refraction at the edges and an
                // edge light. The tint thickens over bright wallpaper for contrast.
                property JsonObject glass: JsonObject {
                    property bool enable: false
                    property real tint: 0.55
                    property real edgeLight: 0.6
                    property real refraction: 0.5
                }
                property int bezel: 0 // Global gap from screen edges (px) for ALL elements
                property bool extraBackgroundTint: true

                // Defaults use free/libre, widely-available families so a fresh
                // install renders correctly without proprietary fonts. Geist
                // (OFL, Vercel) for UI; JetBrainsMono Nerd Font for mono/icons
                // (the exact installed family name is "JetBrainsMono NF", NOT
                // "JetBrains Mono NF"). Users can override per-machine in
                // ~/.config/anoshell/config.json (e.g. Google Sans).
                property JsonObject fonts: JsonObject {
                    property string main: "Geist"
                    property string numbers: "Geist"
                    property string title: "Geist"
                    property string iconNerd: "JetBrainsMono NF"
                    property string monospace: "JetBrainsMono NF"
                    property string reading: "Readex Pro"
                    property string expressive: "Geist"
                }

                // Connected shell mode: one SDF pass draws the rounded screen
                // frame with the bar/sidebars/popouts fused into it by concave
                // junction arcs, so the shell reads as a single surface. Opt-in;
                // when disabled every surface draws its own floating background.
                property JsonObject connectedCorners: JsonObject {
                    property bool enable: false
                    // Screen-corner rounding.
                    property real radius: 18
                    // Width of the painted frame band on each screen edge. This is
                    // the visible bezel the desktop sits inside. It must be > 0 for
                    // the frame's elevation shadow to have somewhere to fall —
                    // at 0 the shadow would bleed inward over your windows, so it
                    // is suppressed entirely.
                    property real thickness: 7
                    // Drop the compositor's OUTER gap while connected mode is on,
                    // so windows sit flush against the painted frame instead of
                    // being inset by a second, unpainted gap. Inner gaps (between
                    // windows) are left alone.
                    property bool manageGaps: true
                    // The outer gap to restore when connected mode turns off (or
                    // manageGaps is disabled). Should match the compositor config's
                    // floating-mode gaps_out.
                    property int floatingGapsOut: 5
                    // Opacity of the painted frame surface. Below 1.0 the frame
                    // becomes translucent; pair with `blur` so what shows through is
                    // the blurred desktop rather than a raw see-through panel.
                    property real opacity: 1.0
                    // Ask the compositor to blur behind the frame surface. Only has
                    // a visible effect when opacity < 1.0 (a fully opaque frame has
                    // nothing to see through to).
                    property bool blur: false
                }

                // Material 3 elevation shadows (SDF shader). Default off — when
                // disabled the shader zeroes both shadow terms and the padding
                // collapses, so it costs nearly nothing.
                property JsonObject shadows: JsonObject {
                    property bool enable: false
                    property real intensity: 1.0   // scales blur radius
                    property real opacity: 1.0     // scales shadow alpha
                }

                property JsonObject transparency: JsonObject {
                    property bool enable: true
                    // Automatic (wallpaper-vibrancy) mode pushed background up to
                    // ~0.22 and content to 0.9, which made surfaces unreadable.
                    // Use fixed, modest values — a subtle see-through that reads
                    // well over the compositor blur, with fully opaque content.
                    property bool automatic: false
                    property real backgroundTransparency: 0.08
                    property real contentTransparency: 0.0
                }

                property JsonObject colors: JsonObject {
                    property bool darkMode: true
                    // Material You variant matugen generates (anod): tonal-spot, content,
                    // expressive, fidelity, fruit-salad, monochrome, neutral, rainbow, vibrant.
                    property string schemeType: "tonal-spot"
                    // Which of the wallpaper's colours seeds the palette (matugen --prefer):
                    // saturation, less-saturation, darkness, lightness, value.
                    property string prefer: "saturation"
                    // Picks (variant, source colour, light/dark) remembered per wallpaper
                    // by anod and restored when it comes back; the three above are the
                    // defaults for wallpapers without picks of their own.
                    property bool perWallpaper: true
                    // A pick also becomes that default. Off: defaults are set on their own.
                    property bool pickSetsDefault: true
                    // Which wallpaper sets the colours when each monitor has its own:
                    // "last" (the last one set), "monitor" (colors.monitor's) or
                    // "focused" (the focused monitor's; recoloured as focus moves).
                    property string from: "last"
                    property string monitor: ""
                }

                // Theme source selector. When source === "materialYou", the
                // existing wallpaper-driven pipeline owns Appearance.m3colors.
                // When source === "static", StaticThemeLoader writes
                // Appearance.m3colors from assets/themes/<name>.json (or
                // ~/.config/anoshell/themes/<name>.json — user dir takes
                // precedence on name collision).
                //
                // Property is `name` (not `static`) because `static` is a
                // reserved word in QML's QtQml parser and using it as a
                // property identifier fails to load.
                property JsonObject theme: JsonObject {
                    property string source: "materialYou"  // "materialYou" | "static"
                    property string name: ""                // theme name without .json suffix
                    // dynamicAccent: wallpaper palette + the fixed AnoShell accent for brand
                    // moments | dynamic: wallpaper palette everywhere | fixed: the AnoShell
                    // palette (ano-dark/light); wallpaper changes leave colours alone.
                    property string colorMode: "dynamicAccent"
                    // GTK 3/4 apps take the palette: anod keeps a marked block in
                    // ~/.config/gtk-{3,4}.0/gtk.css (libadwaita colours); off removes it.
                    property bool gtk: true
                    // Qt apps (scripts/colors/applycolor.sh, via qt5ct/qt6ct): "palette"
                    // (Breeze, else Fusion, on qt6ct's palette: running apps follow live), "kvantum"
                    // (a recoloured Kvantum theme, read when an app starts) or "off".
                    property string qt: "palette"
                    // Light/dark for your apps (GTK color-scheme, portal-aware Qt apps):
                    // "follow" the shell, or always "light" / "dark".
                    property string appColorScheme: "follow"
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // Bar System
            // ═══════════════════════════════════════════════════════════════
            property JsonObject bar: JsonObject {
                // Ano family: "pill" makes the pill (AnoSpot) the bar; "classic" the
                // full bar. Other families always use the classic bar.
                property string style: "pill"
                property int cornerStyle: 0 // 0: Normal | 1: Floating (adds gaps)
                property bool verbose: false // verbose mode shows more info in bar modules
                property bool morphingPanels: false
                property bool showBackground: true
                // Slide the bar out (and release its exclusive zone) while a window
                // is fullscreen on the same screen; reveal on hovering the edge.
                property bool hideOnFullscreen: true
                property var screenList: []
                // autoHide block matches the bundled config shape. Per-bar
                // `bars[].autoHide` (a plain bool in bars[]) overrides this.
                property JsonObject autoHide: JsonObject {
                    property bool enable: false
                    property int delay: 1000 // ms
                }

                property JsonObject workspaces: JsonObject {
                    property int shown: 10
                    // When false (default) only occupied + current workspaces
                    // show, with a ••• button to expand; true shows all `shown`.
                    property bool alwaysShowAll: false
                    // Hovering a workspace button shows its windows; click one to go there.
                    property bool hoverWindows: false
                }

                // Global layout defaults; per-bar bars[].* override these.
                property JsonObject layout: JsonObject {
                    property int height: 42
                    property int radius: 12
                    property int leftSpacing: 8
                    property int centerSpacing: 4
                    property int rightSpacing: 8
                    property int edgePadding: 8
                    property int centerGroupPadding: 5
                    property int centerGroupRadius: 8
                    property bool showCenterBackground: true
                    property bool showSeparators: false
                    // Gap a detached group opens on each side, and the inset of
                    // the floating forms (fit, islands) from the screen edge.
                    property int groupGap: 10
                    property int groupSpacing: 8   // between attached groups
                    property int formMargin: 6
                }
                // Bar form: full (edge to edge) | fit (inset, floating) |
                // islands (every group its own pill) | notch (hugs its content).
                // Per bar: bars[].form; groups and attach state: bars[].groups.
                property string form: "full"

                // Default click/scroll actions per section.
                property JsonObject actions: JsonObject {
                    property string leftClick: "none"
                    property string rightClick: "none"
                    property string centerClick: "overview"
                    property string scrollLeft: "brightness"
                    property string scrollRight: "volume"
                    property string scrollCenter: "workspace"
                }

                // Weather widget shown in the bar / popout.
                property JsonObject weather: JsonObject {
                    property bool enable: false
                    property string city: ""
                    property bool useUSCS: false
                    property int fetchInterval: 15
                }
            }

            // Eye-care screen filter (ScreenFilters): none | grayscale | sepia |
            // high-contrast | protan | deutan | tritan.
            property JsonObject screenFilter: JsonObject {
                property string mode: "none"
                property string last: "grayscale"
            }

            // Productivity (right sidebar cards + a desktop note); all off by default.
            property JsonObject notepad: JsonObject {
                property bool enable: false // tabs kept in ~/.local/share/anoshell/notepad.json
            }
            property JsonObject todo: JsonObject {
                property bool enable: false
                property string file: "" // todo.txt to keep in sync; "" = ~/.local/share/anoshell/todo.txt
            }
            // Screenshots (services/Screenshot.qml) and the card shown after one.
            property JsonObject screenshot: JsonObject {
                property bool copyOnCapture: true      // the image goes on the clipboard at once
                property string previewEdge: "bottomRight" // bottomRight | bottomLeft | topRight | topLeft
                property int previewSeconds: 6         // 0 = the card stays until closed
                property string onTimeout: "keep"      // keep (temp file) | save | delete
                property string saveDir: ""            // "" = ~/Pictures/Screenshots
            }
            // Screen time (services/ScreenTime.qml → anod screentime.*): local only.
            property JsonObject screenTime: JsonObject {
                property bool enable: false
                property int keepDays: 30      // older days are deleted
                property int idleSeconds: 120  // no input this long = not counted
            }
            property JsonObject pomodoro: JsonObject {
                property bool enable: false
                property int focusMinutes: 25
                property int breakMinutes: 5
                property int longBreakMinutes: 15
                property int cyclesBeforeLongBreak: 4
            }
            property JsonObject stickyNotes: JsonObject {
                property bool enable: false
                property bool clickThrough: false // clicks pass through to the windows below
                property int x: 40
                property int y: 80
                property int width: 280
                property int height: 220
            }

            // Settings itself: show the advanced options (search always finds them).
            property JsonObject settings: JsonObject {
                property bool showAdvanced: false
            }

            // First-run welcome: shown once on a fresh config (Settings → About runs it again).
            property JsonObject onboarding: JsonObject {
                property bool seen: false
            }

            // Pointer theme and size, applied by anod (Settings → Modules → Cursor).
            // theme "" leaves the cursor to your compositor config.
            property JsonObject cursor: JsonObject {
                property string theme: ""
                property int size: 24
                property bool adopted: false // the AnoShell cursor went on at first start
            }
            // Where you are (services/Location.qml), for the weather, night light's
            // sunset-to-sunrise schedule and the sun/moon widgets. mode "auto":
            // GeoClue, else the IP address; "manual": the values below.
            property JsonObject location: JsonObject {
                property bool enable: true
                property string mode: "auto"
                property string city: ""
                property real latitude: 0
                property real longitude: 0
            }

            // Desktop widgets (modules/widgets, services/Widgets.qml): cards on a
            // Bottom-layer surface under windows, on a snapping grid, in pages.
            // Off by default: no surface and no widget code until enabled.
            property JsonObject widgets: JsonObject {
                property bool enable: false
                property int cell: 96   // grid cell, logical px
                property int gap: 12    // between cells
                property int fps: 10    // animated widgets (Bioma organisms): frames a second
                // Per screen name: { "page": index, "pages": [[{ uid, id, x, y, w, h, settings }]] }
                // (x/y/w/h in cells). Written by the widget picker and edit mode.
                property var screens: ({})
            }
            // Keyboard layouts in order, [{ layout, variant }] from the XKB catalogue
            // (Settings → Keybinds). anod applies them live and in the managed
            // compositor file; empty leaves your compositor config's layouts.
            property JsonObject keyboard: JsonObject {
                property var layouts: []
            }
            // Desktop icon theme (GTK + qt5ct/qt6ct): "" leaves it alone. The
            // palette ones (anoshell-icons, anoshell-icons-primary) draw folders
            // and file types in the wallpaper's colours and inherit the rest
            // from `base` (services/PaletteThemes.qml). On the first start
            // the desktop's theme becomes `base` and anoshell-icons-tint goes
            // on; `adopted` records that it happened, once.
            property JsonObject icons: JsonObject {
                property string theme: ""
                property string base: "Papirus-Dark"
                property bool adopted: false
            }

            // ═══════════════════════════════════════════════════════════════
            // Reader — novel, manga and anime panels (backend: anod's reader)
            // ═══════════════════════════════════════════════════════════════
            property JsonObject reader: JsonObject {
                property bool enable: false
                // Seconds the backend stays up after the last panel closes.
                property int idleTimeout: 120
                // Image cache (decoded pages and covers) in MB.
                property int cacheMB: 64
                // Lists, details and chapter texts kept in memory (entries).
                property int metaCacheEntries: 512
                // Interpreter for providers set to the python backend.
                property string python: "python3"
                property JsonObject novel: JsonObject {
                    property bool enable: true
                    property string edge: "right" // left | right
                }
                property JsonObject manga: JsonObject {
                    property bool enable: true
                    property string edge: "left"
                }
                property JsonObject anime: JsonObject {
                    property bool enable: true
                    property string edge: "left"
                    // anod saves mpv's position per episode (progress.go)
                    property bool resume: true
                    property bool skipIntro: false        // AniSkip
                    property real finishedRatio: 0.9      // watched past this fraction
                    property bool airing: true            // Airing tab + new-episode badges (AniList)
                }
                // Per source: "go" (anod) or "python" (the legacy servers in scripts/reader).
                property JsonObject providers: JsonObject {
                    property JsonObject freewebnovel: JsonObject { property string backend: "go" }
                    property JsonObject weebcentral: JsonObject { property string backend: "go" }
                    property JsonObject allanime: JsonObject { property string backend: "go" }
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // Wallpaper & Background
            // ═══════════════════════════════════════════════════════════════
            property JsonObject background: JsonObject {
                property string wallpaperPath: ""
                // The wallpaper folder: the picker deals from it, Wallhaven saves
                // into it, rotation uses it unless randomize.directory is set.
                // "" = <XDG Pictures folder>/Wallpapers.
                property string wallpaperDir: ""
                // Favourite wallpapers (absolute paths), hearted in the picker.
                property var favourites: []
                // The card-deck picker (modules/wallpaperSelector).
                property JsonObject picker: JsonObject {
                    property bool livePreview: true // videos and animated images play in the preview
                }
                // Wallhaven search filters. The API key is NOT here: it lives in
                // $XDG_DATA_HOME/anoshell/secrets/wallhaven (0600), set via anod.
                property JsonObject wallhaven: JsonObject {
                    property string categories: "111" // general, anime, people
                    property string purity: "100"     // sfw, sketchy, nsfw (nsfw needs the key)
                    property string sorting: "date_added" // date_added | toplist | views | favorites | random | relevance
                    property string order: "desc"
                    property string topRange: "1M"    // for toplist: 1d 3d 1w 1M 3M 6M 1y
                }
                // How awww fits images (crop | fit | stretch | no); recorded so glass
                // lines up with what's on screen.
                property string resize: "fit"
                // Who draws it: "awww" (default), or "shell" (experimental: transitions,
                // GIF and video drawn by the shell; video pauses when covered).
                property string engine: "awww"
                property JsonObject video: JsonObject {
                    // Decode a video wallpaper on every screen (N× the cost) instead of
                    // only the focused one (the others show a still).
                    property bool allScreens: false
                }
                // Run in order after each wallpaper change (by anod): argv with
                // {image} {mode} {colors}; builtin "cava" recolours cava from pywal.
                // Skipped when not installed, disabled, or in fixed colour mode.
                property var hooks: [
                    { "name": "pywal", "enable": true, "command": ["wal", "-i", "{image}", "-n", "-q"], "timeoutSeconds": 30 },
                    { "name": "swaync", "enable": true, "command": ["swaync-client", "--reload-css"] },
                    { "name": "apps", "enable": true, "command": ["~/.config/quickshell/ano/scripts/colors/applycolor.sh", "--mode", "{mode}"], "timeoutSeconds": 30 },
                    { "name": "cava", "enable": true, "builtin": "cava" },
                    { "name": "themes", "enable": true, "command": ["~/.config/awww/scripts/awww_generate_themes.sh"], "timeoutSeconds": 30 }
                ]

                // Wallpaper rotation. Property name matches the bundled
                // config.json (`background.randomize.*`) and Wallpapers.qml's
                // readers. Interval is in seconds (not minutes) to match the
                // existing AppearanceConfig slider and bundled defaults.
                property JsonObject randomize: JsonObject {
                    property bool enable: false
                    property string directory: "" // "" = background.wallpaperDir
                    property int interval: 300
                }
                // Wallpaper transition (cross-fade / slide). Read by the
                // wallpaper renderer for the swap animation.
                property JsonObject transition: JsonObject {
                    property bool enable: true
                    property string type: "crossfade"
                    property int duration: 800
                    property string direction: "right"
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // Overview & Task View
            // ═══════════════════════════════════════════════════════════════
            property JsonObject overview: JsonObject {
                property string layout: "SmartGrid" // one of 10 hyprview layouts
            }

            property JsonObject taskView: JsonObject {
                property string layout: "Hero" // layout for task view (can differ from overview)
            }

            // ═══════════════════════════════════════════════════════════════
            // Notifications
            // ═══════════════════════════════════════════════════════════════
            property JsonObject notifications: JsonObject {
                property int timeout: 7000  // ms — bundled `notifications.timeout` (NotificationPopup reads this)
                property string position: "topRight" // top|bottom + Left|Center|Right
                property int edgeMargin: 8
                property bool expressiveAnimations: true
                property bool silent: false // no popups; notifications still reach the history
                property int maxVisible: 5 // popups on screen at once
            }

            // ═══════════════════════════════════════════════════════════════
            // Media
            // ═══════════════════════════════════════════════════════════════
            property JsonObject media: JsonObject {
                property string preferredPlayer: "" // MPRIS identity substring tracked first; empty = auto
                property bool filterDuplicatePlayers: true
            }

            // ═══════════════════════════════════════════════════════════════
            // Time / Clock / Date
            // ═══════════════════════════════════════════════════════════════
            property JsonObject time: JsonObject {
                property string format: "hh:mm"
                property bool secondPrecision: false
                property string shortDateFormat: "dd/MM"
                property string dateFormat: "dddd, dd/MM"
                property string dateWithYearFormat: "dd/MM/yyyy"
            }

            // ═══════════════════════════════════════════════════════════════
            // Battery thresholds
            // ═══════════════════════════════════════════════════════════════
            property JsonObject battery: JsonObject {
                property int low: 20
                property int critical: 10
                property int suspend: 5
                property int full: 100
                property bool automaticSuspend: false
            }

            // ═══════════════════════════════════════════════════════════════
            // Resources monitor
            // ═══════════════════════════════════════════════════════════════
            property JsonObject resources: JsonObject {
                property int updateInterval: 3000
                property int historyLength: 60
            }

            // ═══════════════════════════════════════════════════════════════
            // Animations
            // ═══════════════════════════════════════════════════════════════
            property JsonObject animations: JsonObject {
                property bool enable: true
                property real speed: 1.0 // global speed factor
                property bool reducedMotion: false // no looping/ambient motion; transitions stay
                property bool batterySaver: false  // no looping/ambient motion while on battery
            }

            // ═══════════════════════════════════════════════════════════════
            // HUD
            // ═══════════════════════════════════════════════════════════════
            property JsonObject hud: JsonObject {
                property bool enable: true
            }

            // Launcher state
            property JsonObject search: JsonObject {
                property var recentApps: [] // app ids, most recent first
                // Launcher result providers (modules/search/Providers.qml); off = nothing runs.
                property JsonObject plugins: JsonObject {
                    property JsonObject calculator: JsonObject { property bool enable: false }
                    property JsonObject emoji: JsonObject { property bool enable: false }
                    property JsonObject packages: JsonObject {
                        property bool enable: false
                        property string helper: "" // "" = paru, else yay
                    }
                    property JsonObject actions: JsonObject {
                        property bool enable: false
                        property bool enableDangerous: false
                        // { name, icon, command: [argv], dangerous }
                        property var items: [
                            { "name": "Lock screen", "icon": "lock", "command": ["loginctl", "lock-session"], "dangerous": false },
                            { "name": "Suspend", "icon": "bedtime", "command": ["systemctl", "suspend"], "dangerous": false },
                            { "name": "Reboot", "icon": "restart_alt", "command": ["systemctl", "reboot"], "dangerous": true },
                            { "name": "Power off", "icon": "power_settings_new", "command": ["systemctl", "poweroff"], "dangerous": true }
                        ]
                    }
                    property JsonObject schemes: JsonObject { property bool enable: false }
                    property JsonObject looks: JsonObject { property bool enable: false }
                }
            }

            // Translator (left sidebar) language pair
            property JsonObject language: JsonObject {
                property JsonObject translator: JsonObject {
                    property string sourceLanguage: "auto"
                    property string targetLanguage: "en"
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // Session
            // ═══════════════════════════════════════════════════════════════
            property JsonObject session: JsonObject {
                property bool confirmLogout: true
                property bool confirmShutdown: true
            }

            // Removable drives (services/Drives.qml, bar module "drives").
            property JsonObject drives: JsonObject {
                property bool notify: true   // a notification when a drive is plugged in
            }

            // Built-in polkit agent (services/PolkitAuth.qml). polkit takes one
            // agent per session: one already running keeps it.
            property JsonObject polkit: JsonObject {
                property bool enable: true
                // Blur behind the prompt (off: namespace quickshell:polkitPlain,
                // which the bundled compositor configs leave unblurred).
                property bool blur: false
            }

            // ═══════════════════════════════════════════════════════════════
            // Audio protection
            // ═══════════════════════════════════════════════════════════════
            property JsonObject audio: JsonObject {
                property JsonObject protection: JsonObject {
                    property bool enable: true
                    property int maxAllowedIncrease: 10
                    property int maxAllowed: 100
                }
                // cava-backed spectrum (SpectrumService)
                property JsonObject spectrum: JsonObject {
                    property int bars: 32
                    property int frameRate: 60
                }
                // EasyEffects quick toggle + presets (services/EasyEffects.qml)
                property JsonObject easyEffects: JsonObject {
                    property bool enable: false
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // Brightness device override
            // ═══════════════════════════════════════════════════════════════
            property JsonObject light: JsonObject {
                property string device: ""
            }

            // ═══════════════════════════════════════════════════════════════
            // Night light (colour temperature) — consumed by services/NightLight
            // ═══════════════════════════════════════════════════════════════
            property JsonObject nightLight: JsonObject {
                property bool enable: false // the quick toggle: warm now
                property string schedule: "off" // "off" | "sun" (latitude/longitude) | "times" (start–end)
                property int dayTemp: 6500
                property int nightTemp: 4000
                property string start: "20:00"
                property string end: "07:00"
                property int fade: 30 // minutes
                property real gamma: 1.0 // wlsunset -g
                property var outputs: [] // monitor names; empty = all (wlsunset -o)
            }

            // ═══════════════════════════════════════════════════════════════
            // Sounds
            // ═══════════════════════════════════════════════════════════════
            property JsonObject sounds: JsonObject {
                property bool battery: true
                property string theme: "freedesktop"
            }

            // ═══════════════════════════════════════════════════════════════
            // Hacks — debug/workaround knobs
            // ═══════════════════════════════════════════════════════════════
            property JsonObject hacks: JsonObject {
                property int arbitraryRaceConditionDelay: 100
            }

            // ═══════════════════════════════════════════════════════════════
            // Interactions (scrolling tuning)
            // ═══════════════════════════════════════════════════════════════
            property JsonObject interactions: JsonObject {
                property JsonObject scrolling: JsonObject {
                    property bool fasterTouchpadScroll: false
                    property int touchpadScrollFactor: 100
                    property int mouseScrollFactor: 50
                    property int mouseScrollDeltaThreshold: 120
                }
            }

            // ═══════════════════════════════════════════════════════════════
            // The following top-level objects mirror keys already present in
            // config.json. Without a matching schema entry the JsonAdapter
            // rejects them ("Cannot assign to non-existent property …"), so the
            // settings pages that read them throw and the features never apply.
            // ═══════════════════════════════════════════════════════════════

            // Default apps
            property JsonObject apps: JsonObject {
                property string terminal: "kitty"
                property string fileManager: "nemo"
                property string browser: "zen-browser"
            }

            // Logged-in user presentation
            property JsonObject user: JsonObject {
                property string avatarPath: ""
            }

            // Preferred shell selector
            property JsonObject shell: JsonObject {
                property string preferred: ""
                // Transparent huge pages for a qs that anod --supervise starts
                // (off: ~100 MB less RSS, no CPU cost; read by anod at start).
                property bool hugePages: false
            }

            // Multi-bar definitions (array of bar configs). Free-form — consumed
            // by BarManager; keep as a plain list so per-bar keys stay flexible.
            property var bars: []

            // System tray
            property JsonObject tray: JsonObject {
                property bool filterPassive: false
                property bool invertPinnedItems: false
                property var pinnedItems: []
                property bool showItemId: false
            }

            // Sidebars
            property JsonObject sidebar: JsonObject {
                property bool instantOpen: false
                property bool keepLeftSidebarLoaded: true
                property bool keepRightSidebarLoaded: true
                // When true (default), a sidebar opens only on the focused
                // monitor; false opens it on every monitor at once.
                property bool onlyOnFocusedMonitor: true
                property JsonObject translator: JsonObject {
                    property int delay: 600 // ms of typing pause before translating
                }
                property JsonObject quickSliders: JsonObject {
                    property bool showBrightness: true
                    property bool showVolume: true
                    property bool showMic: false
                }
                property JsonObject right: JsonObject {
                    property var enabledWidgets: [
                        "systemButtons", "quickSliders", "quickToggles",
                        "networkDetail", "media", "notifications", "calendar", "systemInfo"
                    ]
                }
            }

            // Dock
            property JsonObject dock: JsonObject {
                property bool enable: true
                property string style: "pill"
                // top/bottom/left/right, or "auto": opposite the pill-bar
                // (bar.style pill), bottom otherwise.
                property string position: "auto"
                property int height: 56
                property int iconSize: 40
                property bool pinnedOnStartup: false
                property bool hoverToReveal: true
                property bool showOnDesktop: true
                property var screenList: []
                property var pinnedApps: ["kitty", "nemo", "zen-browser", "brave-browser"]
            }

            // On-screen display
            property JsonObject osd: JsonObject {
                property int timeout: 1500
                property string position: "bottom"
                property JsonObject indicators: JsonObject {
                    property bool volume: true
                    property bool brightness: true
                    property bool mic: true
                    property bool media: true
                    property bool keyboard: true
                    property bool network: true
                    property bool lockKeys: true
                    property bool micVolume: false
                }
            }

            // Lock screen
            property JsonObject lock: JsonObject {
                property bool enable: true
                property JsonObject notifications: JsonObject {
                    property bool enable: false
                    property int maxItems: 5
                }
                property JsonObject osk: JsonObject {
                    property bool enable: false
                }
                property JsonObject statusRow: JsonObject {
                    property bool enable: false
                }
                property JsonObject dim: JsonObject {
                    property bool enable: true
                    property int idleMs: 30000
                    property real opacity: 0.6
                }
                property JsonObject passwordInput: JsonObject {
                    property bool expandOnFocus: true
                }
            }

            // Screen corners (hot corners)
            property JsonObject screenCorners: JsonObject {
                property bool enable: false
                property int dwellMs: 300
                property int hitSize: 2
                property JsonObject actions: JsonObject {
                    property string topLeft: "sidebarLeftOpen"
                    property string topRight: "sidebarRightOpen"
                    property string bottomLeft: "overviewOpen"
                    property string bottomRight: "settingsOpen"
                }
            }

            // Calendar + external sync
            property JsonObject calendar: JsonObject {
                property int upcomingDays: 7
                property JsonObject externalSync: JsonObject {
                    property bool enable: false
                    property int refreshMinutes: 15
                    property var sources: []
                }
                // User-created calendar events (add/edit, recurring, reminders).
                property JsonObject events: JsonObject {
                    property bool enable: true
                }
                // Public holidays shown in the calendar (dots + labels), fetched
                // per country+year and cached. Primary source Nager.Date (no key);
                // AbstractAPI is an optional fallback when an API key is set.
                property JsonObject holidays: JsonObject {
                    property bool enable: false
                    // ISO-3166 alpha-2 country. Empty + auto ⇒ detect by IP.
                    property string country: ""
                    // Auto-detect the country via IP geolocation (ip-api.com, no
                    // key). When false, `country` is used verbatim. Falls back to
                    // `fallbackCountry` if detection fails.
                    property bool autoDetect: true
                    property string fallbackCountry: "TZ"
                    // Optional AbstractAPI key; enables the fallback provider used
                    // when Nager.Date has no data / errors for a country.
                    property string abstractApiKey: ""
                    // Dot/label colour for holiday entries in the calendar.
                    property string color: "#E06C75"
                }
            }

            // Network usage + hotspot
            property JsonObject network: JsonObject {
                // Which panel the network/Bluetooth entry points open:
                // "classic" (inline pickers) or "orbit" (the NetworkOrbit panel).
                property string panelStyle: "classic"
                property JsonObject usage: JsonObject {
                    property bool enable: false
                    property int intervalMs: 1000
                    property int historyLength: 30
                }
                property JsonObject hotspot: JsonObject {
                    property string ssid: "AnoHotspot"
                    property string password: ""
                }
            }

            // VPN
            property JsonObject vpn: JsonObject {
                property bool enable: true
                property bool notifyOnChange: true
                property var providers: []
            }

            // Power profiles
            property JsonObject powerProfiles: JsonObject {
                property bool restoreOnStart: true
                property string preferredProfile: ""
            }

            // Game mode
            // Game mode: enable shows the bar indicator; gamemoded is
            // watched over D-Bus (no polling).
            property JsonObject gameMode: JsonObject {
                property bool enable: false
            }

            // "What's playing?" via songrec (services/MusicRecognition.qml)
            // Hub (Settings → Hub, services/Hub.qml, anod hub.*): online
            // catalogs (https index.json URLs). The community catalog is added
            // here once it exists.
            property JsonObject hub: JsonObject {
                property var catalogs: []
            }

            property JsonObject musicRecognition: JsonObject {
                property bool enable: false
                property int seconds: 8
                property string source: "output"   // output | mic
            }

            // Device event pills (services/DeviceEvents.qml)
            property JsonObject deviceEvents: JsonObject {
                property bool enable: true
                property bool bluetooth: true
                property bool usb: true
                property bool audio: true
                property bool displays: true
            }

            // Pending package updates (services/Updates.qml, bar module "updates")
            property JsonObject updates: JsonObject {
                property bool enable: false
                property int intervalMin: 120
                property string command: ""      // "" = AUR helper -Syu, else sudo pacman -Syu
            }

            // Performance mode (services/GameMode.qml): what turns it on and
            // what it stops while it lasts.
            property JsonObject performance: JsonObject {
                property bool onGameMode: true
                property bool onFullscreen: false
                property bool stopAnimations: true
                property bool stopBlur: true
                property bool stopVisualizers: true
                property bool holdPopups: true
            }

            // Focus time tracker
            property JsonObject focusTime: JsonObject {
                property bool enable: true
                property var excludeApps: ["Quickshell", "Locked", "Desktop", "Unknown"]
            }

            // anod event hooks: a shell command per event, run by anod with
            // ANO_EVENT and ANO_<KEY> data in the environment (docs/anod.md).
            property JsonObject hooks: JsonObject {
                property bool enable: true
                property int timeoutSeconds: 10
                property int batteryThreshold: 20 // battery_changed also fires when crossing this %
                property string started: ""
                property string wallpaperChanged: ""
                property string themeModeChanged: ""
                property string sessionLocked: ""
                property string sessionUnlocked: ""
                property string loggingOut: ""
                property string rebooting: ""
                property string shuttingDown: ""
                property string wifiChanged: ""
                property string bluetoothChanged: ""
                property string batteryChanged: ""
                property string powerProfileChanged: ""
            }

            // Display manager
            property JsonObject displayManager: JsonObject {
                property bool enable: true
            }

            // Alt-tab window switcher
            property JsonObject altSwitcher: JsonObject {
                // fan: cards on an arc from the pill's edge | list | fullscreen (overview)
                property string style: "fan"
                property bool enableAnimation: true
                property int animationDurationMs: 200
                property bool useMostRecentFirst: true
                property bool compactStyle: false
                property real backgroundOpacity: 0.85
                property int maxVisible: 7
                property real scrimDim: 0 // % dim behind the switcher; 0 = none
            }

            // Lyrics
            property JsonObject lyrics: JsonObject {
                property bool enable: false
                property bool visible: true
                property string backend: "Auto"
                property string dir: "~/.config/anoshell/lyrics"
            }

            // AI assistant
            property JsonObject ai: JsonObject {
                property string defaultModel: "gemini-2.5-flash"
                property real temperature: 0.5
                property string systemPrompt: "You are a helpful assistant integrated into a Linux desktop shell called Ano. Be concise and use markdown formatting."
                property var models: ({})
                property var extraModels: [] // user-added model entries
            }

            // AnoSpot floating media/status pill
            // Screen recording: which installed recorder to use ("auto" picks the
            // first of gpu-screen-recorder, wl-screenrec, wf-recorder), where
            // files go (empty: ~/Videos), and whether to record desktop audio.
            property JsonObject recording: JsonObject {
                property string backend: "auto"
                property string dir: ""
                property bool audio: false
            }

            property JsonObject anoSpot: JsonObject {
                property bool enable: false
                property string position: "bottom"
                property int widthPx: 420
                property int heightPx: 36
                // Slide into the edge while a window is fullscreen on that
                // screen; hovering the edge brings it back.
                property bool hideOnFullscreen: true
                // Float as its own rounded pill with a gap, even when the
                // connected frame is on (otherwise it fuses into the frame).
                property bool floating: false
                // On a bar's edge: nest inside the bar's band instead of beside it.
                property bool inBar: false
                // Tucked into its edge until the pointer reaches it.
                property bool autoHide: false
                // Pill only: no bar and no dock; the pill is the whole shell chrome.
                property bool pillOnly: false
                property bool showMpris: true
                property bool showNotification: true
                property bool showRecording: true
                property bool showClockWeather: true
                property bool showBattery: true
                property bool showWorkspace: true
                property int notificationTimeoutMs: 4000
                property JsonObject actions: JsonObject {
                    property string leftClick: "mediaControls"
                    property string rightClick: "controlPanel"
                    property string middleClick: "anoview"
                    property string scrollOnMpris: "audio"
                }
                property JsonObject eventBorder: JsonObject {
                    property bool enable: true
                    property int holdMs: 1500
                    property var events: ["notification", "track", "recording", "workspace"]
                }
                property bool draggable: true
                property bool acceptDrops: true
                property string stashDir: ""
                property var dropTargets: []
                property bool showLyrics: false
                // Status zones (track, notification, battery) collapse to their icon
                // and open on hover.
                property bool accordion: true
                // Bar modules (BarModuleLoader ids: "drives", "privacy", …) shown
                // on the status face after the built-in zones.
                property var modules: []
                // Resting faces, switched by horizontal swipe / shift-wheel. Status
                // is always first; media/spectrum need a player, lyrics the
                // lyrics service.
                property JsonObject faces: JsonObject {
                    property bool media: true
                    property bool spectrum: false
                    property bool lyrics: false
                }
                // Clicking grows the pill into these surfaces (same component as
                // the standalone panel) instead of opening the panel.
                // States the pill morphs into for a moment; the ones it takes the
                // standalone OSD doesn't show.
                property JsonObject transients: JsonObject {
                    property bool volume: true
                    property bool brightness: true
                    property bool mic: true
                    property bool keyboard: true
                    property bool notification: true
                    property bool charging: true
                    property bool recording: true
                    property bool device: true
                }
                property JsonObject growInto: JsonObject {
                    property bool mediaControls: false
                    property bool controlPanel: false
                    property bool calendar: false
                }
                property JsonObject workspaceHoverPreview: JsonObject {
                    property bool enable: true
                    property int openDelayMs: 200
                    property int closeDelayMs: 300
                    // Every workspace's windows instead of this screen's current one.
                    property bool allWorkspaces: false
                    property int thumbnailWidth: 180
                    property int thumbnailHeight: 110
                }
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
        // Missing file is the expected state for users who haven't
        // customised anything yet — suppress the read-error noise.
        printErrors: false
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

    // Read and change settings from scripts (and the ano CLI) in-process, as
    // Settings does. Values are JSON:
    //   qs -c ano ipc call config get dock.position        -> "auto"
    //   qs -c ano ipc call config set dock.position '"top"'
    IpcHandler {
        target: "config"
        function get(key: string): string {
            let v = root.options
            for (const k of key.split(".")) { if (v === undefined || v === null) break; v = v[k] }
            try { return JSON.stringify(v ?? null) } catch (e) { return "null" }
        }
        function set(key: string, json: string): string {
            let v
            try { v = JSON.parse(json) } catch (e) { return `error: value is not JSON (${e})` }
            // Edges go through the swap rule (pill and dock never share one).
            if ((key === "anoSpot.position" || key === "dock.position") && root.edgeMover) root.edgeMover(key === "dock.position" ? "dock" : "pill", v)
            else root.setNestedValue(key, v)
            return "ok"
        }
    }
}
