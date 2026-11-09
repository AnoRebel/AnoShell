pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

/**
 * Wallpapers: the wallpaper folder (background.wallpaperDir) as a list the
 * picker deals from, anod's palette for it (palette.scan: source colour, hue,
 * video stills), favourites, and applying a wallpaper. Compositor-agnostic —
 * wallpapers are applied by anod (wallpaper.set): awww, matugen colours and
 * the background.hooks.
 */
Singleton {
    id: root

    readonly property string effectiveDirectory: {
        const d = (Config.options?.background?.wallpaperDir ?? "").trim().replace(/\/+$/, "")
        if (d === "") return Directories.wallpaperDir
        return d === "~" || d.startsWith("~/") ? FileUtils.trimFileProtocol(Directories.home) + d.substring(1) : d
    }
    // Rotation's folder: its own, or the wallpaper folder.
    readonly property string rotationDirectory: {
        const d = (Config.options?.background?.randomize?.directory ?? "").trim()
        if (d === "") return root.effectiveDirectory
        return d === "~" || d.startsWith("~/") ? FileUtils.trimFileProtocol(Directories.home) + d.substring(1) : d
    }
    readonly property list<string> extensions: [
        "jpg", "jpeg", "png", "webp", "avif", "bmp", "gif", "svg", "mp4", "mkv", "webm", "avi", "mov", "m4v", "ogv"
    ]
    // Every wallpaper in the folder: [{ name, path, url, modified (ms), size }],
    // kept up to date so the picker opens on a ready list.
    property var entries: []
    // anod's palette for the folder: { path: { source, hue, luminance, still, video, … } }.
    property var palette: ({})
    property bool paletteScanning: false
    property bool _scanAgain: false
    // The picker's order, kept for the session: "name" | "hue" | "date".
    property string deckSort: "name"

    function load() {} // Force initialization

    property list<string> videoExtensions: ["mp4", "mkv", "webm", "avi", "mov", "m4v", "ogv"]
    // A file:// URL for a path (names may hold '#', '?' or spaces).
    function fileUrl(path) { return FileUtils.fileUrl(path) }
    function isVideoFile(name) { return videoExtensions.some(ext => name.endsWith("." + ext)) }

    Process { id: applyProc }

    // Redraw what each output shows now with a new resize mode (awww only
    // applies the mode when it draws; the shell engine follows the config).
    function reshow(resize) {
        if ((Config.options?.background?.engine ?? "awww") !== "awww") return
        reshowProc.resize = resize
        reshowProc.running = true
    }
    Process {
        id: reshowProc
        property string resize: "fit"
        command: ["awww", "query"]
        stdout: StdioCollector {
            onStreamFinished: {
                // ": eDP-1: 1280x800, scale: 1.5, currently displaying: image: /path"
                for (const line of text.split("\n")) {
                    const m = line.match(/([^\s:]+): \d+x\d+.*currently displaying: image: (.+)$/)
                    if (m) Quickshell.execDetached(["awww", "img", "--resize", reshowProc.resize,
                        "--transition-type", "none", "--outputs", m[1], "--", m[2]])
                }
            }
        }
    }

    // Random wallpaper rotation without anod (anod rotates when it runs, so
    // this would fight it otherwise).
    property list<string> randomWallpaperList: []

    Timer {
        id: randomWallpaperTimer
        interval: Config.options.background.randomize.interval * 1000
        running: !Anod.available && Config.options.background.randomize.enable && root.rotationDirectory.length > 0
        repeat: true // not on start: anod may still be connecting
        onTriggered: {
            if (root.randomWallpaperList.length === 0) {
                getRandomWallpapersProc.running = true
            } else {
                const randomIndex = Math.floor(Math.random() * root.randomWallpaperList.length)
                root.apply(root.randomWallpaperList[randomIndex])
            }
        }
    }

    Process {
        id: getRandomWallpapersProc
        property string expandedDir: root.rotationDirectory
        command: ["find", expandedDir, "-type", "f", "-regex", ".*\\.\\(jpg\\|jpeg\\|png\\|webp\\|avif\\|bmp\\|svg\\|gif\\)"]
        stdout: StdioCollector {
            id: randomWallpapersCollector
            onStreamFinished: {
                const output = randomWallpapersCollector.text.trim()
                if (output.length > 0) {
                    root.randomWallpaperList = output.split("\n")
                    const randomIndex = Math.floor(Math.random() * root.randomWallpaperList.length)
                    root.apply(root.randomWallpaperList[randomIndex])
                } else {
                    console.log("[Wallpapers] No wallpapers found in:", getRandomWallpapersProc.expandedDir)
                }
            }
        }
    }

    onRotationDirectoryChanged: {
        root.randomWallpaperList = []
        if (randomWallpaperTimer.running) getRandomWallpapersProc.running = true
    }

    // instant: no awww transition (the picker's card grows into the wallpaper itself).
    function apply(path, monitorName = "", instant = false) {
        if (!path || path.length === 0) return
        // anod applies (awww), colours (matugen, with the picks remembered
        // for this wallpaper) and runs the hooks (pywal, apps, cava …); its
        // announcement records the path (Anod.qml), so a failed apply doesn't
        // leave config pointing at something not shown.
        const req = { image: path }
        if (monitorName !== "") req.outputs = [monitorName]
        if (instant) req.transition = "none"
        const sent = Anod.call("wallpaper.set", req, (res, err) => {
            if (err) Quickshell.execDetached(["notify-send", "-a", "Ano Shell", "Wallpaper", `Couldn't apply: ${err.message}`])
        })
        // Without anod: just show it (no colours or hooks).
        if (!sent) Config.setNestedValue("background.wallpaperPath", path)
        if (!sent) applyProc.exec(["awww", "img", "--resize", Config.options?.background?.resize ?? "fit"]
            .concat(instant ? ["--transition-type", "none"] : []).concat(monitorName !== "" ? ["--outputs", monitorName] : []).concat(["--", path]))
    }

    // ── Colour picks (variant, source colour, light/dark) ───────────────────
    // What the current colours were made with: { schemeType, prefer, mode,
    // custom, image } — custom when the image has picks of its own; image is
    // the wallpaper they follow (appearance.colors.from).
    property var scheme: ({ schemeType: Config.options?.appearance?.colors?.schemeType ?? "tonal-spot",
        prefer: Config.options?.appearance?.colors?.prefer ?? "saturation",
        mode: (Config.options?.appearance?.colors?.darkMode ?? true) ? "dark" : "light", custom: false, image: "" })
    function _takeScheme(sch, custom, image) {
        if (sch && image) root.scheme = { schemeType: sch.schemeType, prefer: sch.prefer, mode: sch.mode, custom: !!custom, image: image }
    }
    // A pick from Settings or search, e.g. { schemeType: "vibrant" } or
    // { mode: "light" }: remembered for the wallpaper on screen
    // (appearance.colors.perWallpaper) and, with pickSetsDefault, the default
    // for the rest; then its colours are redone. Static themes only take the mode.
    function pickColors(pick) {
        const c = Config.options?.appearance?.colors
        const perWallpaper = c?.perWallpaper ?? true
        if (!perWallpaper || (c?.pickSetsDefault ?? true) || (Config.options?.appearance?.theme?.source ?? "materialYou") === "static")
            root.setDefaultColors(pick)
        if ((Config.options?.appearance?.theme?.source ?? "materialYou") === "static") return
        root._colors(Object.assign({ remember: perWallpaper }, pick))
    }
    // The GTK palette block now (written or removed per appearance.theme.gtk),
    // once the config is on disk (anod reads it from there).
    function refreshGtk() { gtkSoon.restart() }
    Timer {
        id: gtkSoon
        interval: 1000
        onTriggered: Anod.call("theme.gtk", {}, (res, err) => {
            if (err && err.code !== "unavailable") Quickshell.execDetached(["notify-send", "-a", "Ano Shell", "GTK colours", err.message])
        })
    }
    // Re-run the pipeline's app steps (Qt, terminals, …) for the current colours.
    function refreshApps() { root._colors({ recolor: true }) }
    // Forget the current wallpaper's picks (back to the defaults).
    function resetColors() { root._colors({ reset: true }) }
    function setDefaultColors(pick) {
        if (pick.schemeType) Config.setNestedValue("appearance.colors.schemeType", pick.schemeType)
        if (pick.prefer) Config.setNestedValue("appearance.colors.prefer", pick.prefer)
        if (pick.mode) Config.setNestedValue("appearance.colors.darkMode", pick.mode === "dark")
    }
    // anod works out the wallpaper the colours follow. quiet: a status check,
    // errors only logged (a notification is for picks the user made).
    function _colors(req, quiet = false) {
        Anod.call("wallpaper.colors", req, (res, err) => {
            if (err && quiet) console.warn("[Wallpapers] wallpaper.colors:", err.message)
            else if (err && err.code !== "unavailable") Quickshell.execDetached(["notify-send", "-a", "Ano Shell", "Colours", `Couldn't regenerate: ${err.message}`])
            if (!err) root._takeScheme(res.scheme, res.custom, res.image)
        })
    }
    Connections {
        target: Anod
        function onEvent(name, data) {
            if (name === "wallpaper_changed" || name === "wallpaper_colors") root._takeScheme(data?.scheme, data?.custom, data?.colorImage)
        }
        function onAvailableChanged() { if (Anod.available) { root._colors({}, true); root._reportFocus() } } // report only
    }
    // Colours from the focused monitor: anod hears where focus is.
    readonly property string colorsFrom: Config.options?.appearance?.colors?.from ?? "last"
    readonly property string _focusedOutput: CompositorService.focusedMonitorName
    function _reportFocus() {
        if (root.colorsFrom === "focused" && root._focusedOutput !== "") Anod.call("wallpaper.focus", { output: root._focusedOutput }, () => {})
    }
    on_FocusedOutputChanged: root._reportFocus()
    // Where colours come from changed: redo them from that wallpaper once
    // the config is on disk (anod reads it from there).
    onColorsFromChanged: if (Config.ready) recolorSoon.restart()
    readonly property string _colorMonitor: Config.options?.appearance?.colors?.monitor ?? ""
    on_ColorMonitorChanged: if (Config.ready && root.colorsFrom === "monitor") recolorSoon.restart()
    Timer {
        id: recolorSoon
        interval: 1000
        onTriggered: { root._reportFocus(); if (root.colorsFrom !== "focused") root._colors({ recolor: true }) }
    }
    Component.onCompleted: if (Anod.available) root._colors({}, true)

    // ── Favourites (background.favourites: absolute paths) ──────────────────
    readonly property var favourites: Array.from(Config.options?.background?.favourites ?? []) // a plain array (config lists are V4Sequences)
    function isFavourite(path) {
        for (let i = 0; i < root.favourites.length; i++) if (root.favourites[i] === path) return true
        return false
    }
    function toggleFavourite(path) {
        if (!path) return
        const next = []
        let removed = false
        for (let i = 0; i < root.favourites.length; i++) {
            if (root.favourites[i] === path) removed = true
            else next.push(root.favourites[i])
        }
        if (!removed) next.push(path)
        Config.setNestedValue("background.favourites", next)
    }

    // ── Palette (anod palette.scan; cached there by path + size + mtime) ────
    // Without anod there's no palette: the picker shows plain cards and the
    // hue sort falls back to name order for unread files.
    function scanPalette() {
        if (root.paletteScanning) { root._scanAgain = true; return }
        const dir = root.effectiveDirectory
        root.paletteScanning = Anod.call("palette.scan", { dir: dir }, (res, err) => {
            root.paletteScanning = false
            if (err) console.warn("[Wallpapers] palette.scan:", err.message)
            else if (dir === root.effectiveDirectory) {
                const map = {}
                for (const e of res ?? []) map[e.path] = e
                root.palette = map
            }
            if (root._scanAgain) { root._scanAgain = false; root.scanPalette() }
        })
    }
    onEffectiveDirectoryChanged: root.palette = ({})

    FolderListModel {
        id: folderModel
        folder: root.fileUrl(root.effectiveDirectory)
        caseSensitive: false
        // Videos only when the shell draws the wallpaper (awww can't play them).
        nameFilters: root.extensions.filter(ext => Config.options?.background?.engine === "shell" || !root.videoExtensions.includes(ext)).map(ext => `*.${ext}`)
        showDirs: false
        showOnlyReadable: true
        sortField: FolderListModel.Name
        onCountChanged: rebuild.restart()
        onStatusChanged: rebuild.restart()
    }
    // One rebuild per batch of changes (the model fills in steps).
    Timer {
        id: rebuild
        interval: 30
        onTriggered: {
            const arr = []
            // A folder that doesn't exist makes FolderListModel fall back to
            // the working directory (often $HOME): list nothing then.
            const shown = decodeURIComponent(String(folderModel.folder).replace(/^file:\/\//, "")).replace(/\/+$/, "")
            const ours = shown === root.effectiveDirectory.replace(/\/+$/, "")
            for (let i = 0; ours && i < folderModel.count; i++) {
                const path = folderModel.get(i, "filePath")
                if (!path) continue
                arr.push({ name: folderModel.get(i, "fileName"), path: path, url: String(folderModel.get(i, "fileUrl")),
                    modified: folderModel.get(i, "fileModified")?.getTime?.() ?? 0, size: folderModel.get(i, "fileSize") ?? 0 })
            }
            root.entries = arr
            if (ours && !root._missingChecked && folderModel.status === FolderListModel.Ready && Config.ready) {
                root._missingChecked = true
                const cur = Config.options?.background?.wallpaperPath ?? ""
                if (cur !== "") missingCheck.exec(["test", "-e", cur])
            }
        }
    }

    // Once at start: a wallpaper whose file is gone (moved, deleted, a folder
    // renamed) is replaced by the first image in the folder.
    property bool _missingChecked: false
    Connections { target: Config; function onReadyChanged() { if (Config.ready) rebuild.restart() } }
    Process {
        id: missingCheck
        onExited: code => {
            if (code === 0) return
            const first = root.entries.find(e => !root.isVideoFile(e.name.toLowerCase()))
            if (!first) return
            root.apply(first.path)
            Quickshell.execDetached(["notify-send", "-a", "Ano Shell", "Wallpaper",
                `The wallpaper file is gone; switched to ${first.name}.`])
        }
    }

    IpcHandler {
        target: "wallpapers"
        function apply(path: string): void { root.apply(path) }
    }
}
