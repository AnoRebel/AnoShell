pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Loads a static (non-Material-You) theme from a JSON file and writes
 * it into Appearance.m3colors using the same shape MaterialThemeLoader
 * uses (snake_case key in JSON → m3<camelCase> on m3colors). Glass
 * tokens (any key starting with "glass") populate Appearance.glassTokens.
 *
 * Resolution order for the theme file path:
 *   1. ~/.config/anoshell/themes/<name>.json   (user override, if present)
 *   2. <shell>/assets/themes/<name>.json  (bundled fallback)
 *
 * Active when Config.options.appearance.theme.source === "static" and
 * Config.options.appearance.theme.name is non-empty. When source is
 * "materialYou" or static is empty, this loader is dormant and
 * MaterialThemeLoader owns the m3colors writes.
 */
Singleton {
    id: root

    readonly property string source: Config.options?.appearance?.theme?.source ?? "materialYou"
    readonly property bool fixedMode: source !== "static" && (Config.options?.appearance?.theme?.colorMode ?? "") === "fixed"
    // Fixed colour mode is the brand palette, in the configured dark/light mode.
    readonly property string staticName: fixedMode
        ? ((Config.options?.appearance?.colors?.darkMode ?? true) ? "ano-dark" : "ano-light")
        : (Config.options?.appearance?.theme?.name ?? "")
    readonly property bool active: (source === "static" || fixedMode) && staticName.length > 0

    // Resolved on demand — checks user dir first, falls back to bundled.
    property string resolvedPath: ""

    function _resolve() {
        if (!active) {
            resolvedPath = ""
            return
        }
        const file = staticName + ".json"
        const userPath = Directories.userThemesPath + "/" + file
        const bundledPath = Directories.bundledThemesPath + "/" + file

        // The probe FileView below races to discover which exists.
        userProbe.path = ""
        userProbe.path = userPath
        // Set bundled fallback up-front; userProbe overrides on success.
        resolvedPath = bundledPath
    }

    // Synthetic loader that picks user override when it exists.
    FileView {
        id: userProbe
        watchChanges: false
        printErrors: false
        onLoaded: {
            // User file found — adopt its path as the resolved one.
            root.resolvedPath = path
        }
        // onLoadFailed silently leaves resolvedPath at the bundled fallback.
    }

    // Apply a parsed theme JSON object to Appearance. Pulled out of
    // applyTheme(string) so the preview-tokens path can call it without
    // re-parsing.
    function applyThemeJson(json) {
        if (!json || typeof json !== "object") return
        const m3 = Appearance.m3colors
        const glass = Appearance.glassTokens
        for (const key in json) {
            if (!json.hasOwnProperty(key)) continue
            // Skip metadata
            if (key === "_meta") continue

            // Glass tokens: any key starting with "glass" (e.g. glass_opacity,
            // glass_blur, glass_border_color) goes into Appearance.glassTokens.
            if (key.startsWith("glass") || key.startsWith("glass_")) {
                if (glass) {
                    const glassKey = key.replace(/^glass_?/, "")
                                        .replace(/_([a-z])/g, g => g[1].toUpperCase())
                    if (glassKey.length > 0) glass[glassKey] = json[key]
                }
                continue
            }

            // Regular m3 color keys: snake_case → m3<camelCase>
            const camelCaseKey = key.replace(/_([a-z])/g, g => g[1].toUpperCase())
            const m3Key = "m3" + camelCaseKey.charAt(0).toUpperCase() + camelCaseKey.slice(1)
            // Some MaterialYou JSONs use already-camelCased keys; preserve those too
            const directKey = "m3" + camelCaseKey
            if (m3.hasOwnProperty(m3Key)) m3[m3Key] = json[key]
            else if (m3.hasOwnProperty(directKey)) m3[directKey] = json[key]
        }
        // Mirror the darkmode-detection MaterialThemeLoader does.
        if (m3.m3background)
            m3.darkmode = (m3.m3background.hslLightness < 0.5)
    }

    function applyTheme(fileContent) {
        // Preview overlay wins regardless of source. AppearanceConfig
        // populates Appearance.previewTokens during hover so the user can
        // peek at static themes from Material You mode without
        // committing. When the preview clears, we fall through to the
        // active source's normal output.
        if (root._hasPreview()) {
            root.applyThemeJson(Appearance.previewTokens)
            return
        }
        if (!active) return
        let json
        try {
            json = JSON.parse(fileContent)
        } catch (e) {
            console.warn("[StaticThemeLoader] failed to parse theme JSON:", e)
            return
        }
        root.applyThemeJson(json)
    }

    function _hasPreview() {
        const p = Appearance.previewTokens
        if (!p || typeof p !== "object") return false
        // Empty-object preview clears (per Appearance.previewTokens contract)
        for (const _ in p) return true
        return false
    }

    function reapplyTheme() {
        // Preview wins.
        if (root._hasPreview()) {
            root.applyThemeJson(Appearance.previewTokens)
            return
        }
        if (root.active) {
            themeFileView.reload()
            return
        }
        // Source is Material You — restore by re-reading the generated
        // colors file.
        if (typeof MaterialThemeLoader !== "undefined")
            MaterialThemeLoader.reapplyTheme()
    }

    // ─── App colours (GTK, Qt, terminals) ───
    // A static theme's palette goes to the apps through anod (theme.apply:
    // colors.json, GTK, the colour hooks); leaving it for Material You
    // redoes the wallpaper's. Whoever changes the theme (this page, the
    // Atelier, search, a rice), this follows the config, not the caller.
    readonly property string _appsKey: source === "static" ? "static:" + staticName : source
    property string _appsApplied: ""
    function applyApps(name: string): void {
        _appsApplied = "static:" + name
        Anod.call("theme.apply", { name: name }, (r, e) => {
            if (e) console.warn("[StaticThemeLoader] theme.apply:", e.message)
        })
    }
    // Apps again for whatever owns the colours now (the GTK/Qt switches).
    function refreshApps(): void {
        if (source === "static" && staticName.length > 0) applyApps(staticName)
        else Wallpapers.refreshApps()
    }
    on_AppsKeyChanged: appsSoon.restart()
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) root._appsApplied = root._appsKey } // startup: already applied
    }
    Timer {
        id: appsSoon
        interval: 1000 // after the config is on disk: anod reads it from there
        onTriggered: {
            const key = root._appsKey, was = root._appsApplied
            if (!Config.ready || key === was) return
            if (key.startsWith("static:") && root.staticName.length > 0) root.applyApps(root.staticName)
            else {
                root._appsApplied = key
                if (was.startsWith("static:")) Wallpapers.refreshApps()
            }
        }
    }

    // React to config changes — re-resolve and reload when source/name flips.
    onSourceChanged: _resolve()
    onStaticNameChanged: _resolve()
    // staticName can change before `active` does, so resolve again here;
    // leaving fixed/static mode hands the colours back to Material You.
    onActiveChanged: active ? _resolve() : reapplyTheme()
    Component.onCompleted: {
        if (Config.ready) _appsApplied = _appsKey
        _resolve()
    }

    onResolvedPathChanged: {
        if (!active || resolvedPath.length === 0) return
        themeFileView.path = ""
        themeFileView.path = resolvedPath
    }

    // Track preview-overlay changes. When AppearanceConfig sets/clears
    // Appearance.previewTokens we re-render — set applies the preview,
    // clear falls through to the committed file.
    Connections {
        target: Appearance
        function onPreviewTokensChanged() {
            if (!root.active) return
            root.reapplyTheme()
        }
    }

    FileView {
        id: themeFileView
        watchChanges: true
        printErrors: false
        onFileChanged: this.reload()
        onLoadedChanged: {
            if (root.active) root.applyTheme(this.text())
        }
        onLoadFailed: error => {
            console.warn("[StaticThemeLoader] failed to load theme:", root.staticName, "from", path, "(error:", error, ")")
        }
    }
}
