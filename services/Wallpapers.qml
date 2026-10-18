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
                root.apply(root.randomWallpaperList[randomIndex], Appearance.m3colors.darkmode)
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
                    root.apply(root.randomWallpaperList[randomIndex], Appearance.m3colors.darkmode)
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
    function apply(path, darkMode = Appearance.m3colors.darkmode, monitorName = "", instant = false) {
        if (!path || path.length === 0) return
        // anod applies (awww), colours (matugen) and runs the hooks (pywal,
        // apps, cava …); its announcement records the path (Anod.qml), so a
        // failed apply doesn't leave config pointing at something not shown.
        const req = { image: path, mode: darkMode ? "dark" : "light" }
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

    // Light/dark switch: colours and hooks again for what's on screen (no
    // re-apply, so per-screen wallpapers stay). Needs anod.
    function recolor(path, darkMode) {
        if (!path) return
        Anod.call("wallpaper.set", { image: path, mode: darkMode ? "dark" : "light", colorsOnly: true }, (res, err) => {
            if (err && err.code !== "unavailable") Quickshell.execDetached(["notify-send", "-a", "Ano Shell", "Colours", `Couldn't regenerate: ${err.message}`])
        })
    }

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
            for (let i = 0; i < folderModel.count; i++) {
                const path = folderModel.get(i, "filePath")
                if (!path) continue
                arr.push({ name: folderModel.get(i, "fileName"), path: path, url: String(folderModel.get(i, "fileUrl")),
                    modified: folderModel.get(i, "fileModified")?.getTime?.() ?? 0, size: folderModel.get(i, "fileSize") ?? 0 })
            }
            root.entries = arr
        }
    }

    IpcHandler {
        target: "wallpapers"
        function apply(path: string): void { root.apply(path) }
    }
}
