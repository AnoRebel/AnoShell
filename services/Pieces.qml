pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import "undoLogic.js" as UndoLogic

/**
 * Pieces: the desktop widget registry (spec desktop-pieces). A piece is a
 * folder with a `piece.json` manifest and a QML entry file; the bundled ones
 * live in the shell's pieces/, yours in ~/.config/anoshell/pieces/, where
 * the same id overrides a bundled one (as Looks and ThemeRegistry do).
 * Folders are watched, so a package you drop in shows up without a restart.
 *
 * A package whose manifest is invalid, or whose QML doesn't compile, is
 * listed with its errors and can't be placed; the rest keep working. Each
 * manifest change bumps the entry's revision, which is part of its QML URL,
 * so an edited piece is compiled afresh.
 *
 * Manifest: { id, name, description, author, version, entry ("main.qml"),
 * size: { w, h } in grid cells, minSize?: { w, h }, frame (true: the host
 * draws the card), settings: [{ key, type: bool|int|real|string|choice,
 * label, default, options? }] }.
 *
 * The layout (which pieces sit where) is in pieces.screens; editing helpers
 * for it are here so the picker, edit mode and IPC share them.
 */
Singleton {
    id: root

    readonly property string bundledDir: Quickshell.shellPath("pieces")
    readonly property string userDir: `${Directories.userConfigDir}/pieces`

    // id -> { id, name, description, author, version, entry, size, minSize,
    //         frame, settings, source: "bundled"|"user", dir, url, errors[] }
    property var _bundled: ({})
    property var _user: ({})
    // id -> compile error ("" when it compiled), filled by check()
    property var qmlErrors: ({})
    readonly property var entries: Object.assign({}, root._bundled, root._user)
    readonly property var list: Object.values(root.entries).sort((a, b) => a.name.localeCompare(b.name))

    function errorsOf(id: string): var {
        const e = root.entries[id]
        if (!e) return [`no piece "${id}"`]
        return root.qmlErrors[id] ? e.errors.concat([root.qmlErrors[id]]) : e.errors
    }
    function usable(id: string): bool { return root.errorsOf(id).length === 0 }

    // ── Manifests ───────────────────────────────────────────────────────
    property int _rev: 0
    function _ingest(source: string, dir: string, text: string): void {
        if (!dir.startsWith((source === "user" ? root.userDir : root.bundledDir) + "/")) return
        // The Atelier installs code into a fresh <id>~<n> folder per version, so an
        // update never runs stale cached QML; the id is the part before "~".
        const dirId = dir.split("/").pop().replace(/~\d+$/, "")
        let m = null
        const errors = []
        try { m = JSON.parse(text) } catch (err) { errors.push(`piece.json: invalid JSON: ${err.message ?? err}`) }
        const str = v => typeof v === "string" && v.length > 0 ? v : ""
        const cells = (v, d) => ({ w: Math.max(1, Math.min(12, Math.round(v?.w ?? d.w))), h: Math.max(1, Math.min(12, Math.round(v?.h ?? d.h))) })
        if (m) {
            if (m.id !== undefined && m.id !== dirId) errors.push(`piece.json: id "${m.id}" doesn't match its folder "${dirId}"`)
            if (!str(m.name)) errors.push("piece.json: no name")
            const entryFile = str(m.entry) || "main.qml"
            if (!/^[A-Za-z0-9_.-]+\.qml$/.test(entryFile)) errors.push(`piece.json: entry "${entryFile}" must be a .qml file in the folder`)
            if (m.settings !== undefined && !Array.isArray(m.settings)) errors.push("piece.json: settings must be a list")
        }
        root._rev++
        const size = cells(m?.size, { w: 2, h: 2 })
        const e = {
            id: dirId, name: str(m?.name) || dirId, description: str(m?.description), author: str(m?.author),
            version: str(m?.version), entry: str(m?.entry) || "main.qml", size, minSize: cells(m?.minSize, { w: 1, h: 1 }),
            frame: m?.frame !== false, settings: Array.isArray(m?.settings) ? m.settings : [],
            source, dir, url: `file://${dir}/${str(m?.entry) || "main.qml"}?r=${root._rev}`, errors
        }
        const all = Object.assign({}, source === "user" ? root._user : root._bundled)
        all[dirId] = e
        if (source === "user") root._user = all; else root._bundled = all
        if (errors.length) console.warn(`[Pieces] ${dir}: ${errors.join("; ")}`)
        const q = Object.assign({}, root.qmlErrors); delete q[dirId]; root.qmlErrors = q
        if (root.checking) root._check(e)
    }
    function _drop(dir: string): void {
        const id = dir.split("/").pop().replace(/~\d+$/, "")
        const user = dir.startsWith(root.userDir + "/")
        const m = user ? root._user : root._bundled
        if (m[id]?.dir !== dir) return
        const e = Object.assign({}, m); delete e[id]
        if (user) root._user = e; else root._bundled = e
    }

    // ── Compile check ───────────────────────────────────────────────────
    // Only while something needs it (the picker, the layer): compiling a
    // piece is the first point where its code is touched.
    property int _holds: 0
    readonly property bool checking: root._holds > 0
    function hold(on: bool): void { root._holds = Math.max(0, root._holds + (on ? 1 : -1)) }
    onCheckingChanged: if (root.checking) for (const e of Object.values(root.entries)) root._check(e)
    function _check(e): void {
        if (e.errors.length) return
        const c = Qt.createComponent(e.url, Component.Asynchronous)
        const done = () => {
            if (c.status === Component.Loading) return
            // a newer manifest started a newer check: this result is stale
            if (root.entries[e.id]?.url !== e.url) { c.destroy(); return }
            const q = Object.assign({}, root.qmlErrors)
            // "file:///…/id/Main.qml?r=3:2:38: …" → "Main.qml:2:38: …"
            q[e.id] = c.status === Component.Error ? c.errorString().trim().split(`file://${e.dir}/`).join("").replace(/\?r=\d+/g, "") : ""
            if (q[e.id]) console.warn(`[Pieces] ${e.id}: ${q[e.id]}`)
            root.qmlErrors = q
            c.destroy()
        }
        if (c.status === Component.Loading) c.statusChanged.connect(done); else done()
    }

    FolderListModel { id: bundledFolder; folder: "file://" + root.bundledDir; showDirs: true; showFiles: false; showDotAndDotDot: false }
    // A FolderListModel on a missing folder lists the working directory, so
    // the user folder is created first.
    property bool _userReady: false
    Process {
        running: true
        command: ["mkdir", "-p", root.userDir]
        onExited: root._userReady = true
    }
    FolderListModel { id: userFolder; folder: root._userReady ? "file://" + root.userDir : ""; showDirs: true; showFiles: false; showDotAndDotDot: false }

    component Manifest: FileView {
        id: mf
        required property string filePath // the package folder
        required property string source
        property int _tries: 0
        // Only folders really inside the piece folders (a FolderListModel
        // lists the working directory until its folder is set).
        readonly property bool mine: filePath.startsWith((source === "user" ? root.userDir : root.bundledDir) + "/")
            && !/^[_.]/.test(filePath.split("/").pop()) // _shared folders (pieces/_bioma) aren't pieces
        path: mf.mine ? `${filePath}/piece.json` : ""
        watchChanges: mf.mine
        onFileChanged: reload()
        onLoaded: root._ingest(source, filePath, text())
        // A folder copied in may show up before its manifest: look again shortly.
        onLoadFailed: { root._drop(filePath); if (mf.mine && mf._tries++ < 5) retry.restart() }
        Component.onDestruction: root._drop(filePath)
        property Timer retry: Timer { interval: 1000; onTriggered: mf.reload() }
    }
    Instantiator { model: bundledFolder; delegate: Manifest { source: "bundled" } }
    Instantiator { model: root._userReady ? userFolder : null; delegate: Manifest { source: "user" } }

    // ── Layout (pieces.screens) ────────────────────────────────────────
    // The grid of whole cells that fits a free area of w × h: the layer's
    // window, or (Settings, while no layer runs) the screen's work area.
    readonly property int gridMargin: 24
    readonly property int pagerHeight: 28   // the page dots under the grid
    function gridSize(w: real, h: real): var {
        const cell = Math.max(32, Config.options?.pieces?.cell ?? 96), gap = Math.max(0, Config.options?.pieces?.gap ?? 12)
        return { cols: Math.max(1, Math.floor((w - 2 * root.gridMargin + gap) / (cell + gap))),
                 rows: Math.max(1, Math.floor((h - 2 * root.gridMargin - root.pagerHeight + gap) / (cell + gap))) }
    }
    // Each running layer's grid, by screen name: { cols, rows }.
    property var grids: ({})
    function setGrid(screenName: string, cols: int, rows: int): void {
        if (root.grids[screenName]?.cols === cols && root.grids[screenName]?.rows === rows) return
        const g = Object.assign({}, root.grids); g[screenName] = { cols, rows }; root.grids = g
    }
    readonly property var screens: Config.options?.pieces?.screens ?? ({})
    function layoutOf(screenName: string): var {
        const s = root.screens[screenName]
        const pages = Array.isArray(s?.pages) && s.pages.length ? s.pages : [[]]
        return { page: Math.max(0, Math.min(pages.length - 1, s?.page ?? 0)), pages }
    }
    function _save(screenName: string, layout): void {
        const all = JSON.parse(JSON.stringify(root.screens))
        all[screenName] = layout
        Config.setNestedValue("pieces.screens", all)
    }
    function setPage(screenName: string, page: int): void {
        const l = root.layoutOf(screenName)
        const p = Math.max(0, Math.min(l.pages.length - 1, page))
        if (p !== l.page) root._save(screenName, { page: p, pages: l.pages })
    }
    function addPage(screenName: string): void {
        const l = root.layoutOf(screenName)
        root._save(screenName, { page: l.pages.length, pages: l.pages.concat([[]]) })
    }
    function removePage(screenName: string, page: int): void {
        const l = root.layoutOf(screenName)
        const pages = l.pages.length <= 1 ? [[]] : l.pages.filter((_, i) => i !== page)
        root._removeWithUndo(screenName, l, { page: Math.min(l.page, pages.length - 1), pages }, "Removed a desktop page", page)
    }
    // Saves `after`; Undo puts `before`'s pages back, but only while the
    // layout is still exactly what the removal left (else it says it can't).
    function _removeWithUndo(screenName, before, after, label, page) {
        if (UndoLogic.same(before.pages, after.pages)) return
        root._save(screenName, after)
        Undo.push({ label, restore: () => {
            if (!UndoLogic.same(root.layoutOf(screenName).pages, after.pages)) return false
            root._save(screenName, { page: page ?? root.layoutOf(screenName).page, pages: before.pages })
        } })
    }
    // Places a piece on the shown page at the first free spot of a grid of
    // cols × rows cells; false when it doesn't fit.
    function add(screenName: string, id: string, cols: int, rows: int): bool {
        const e = root.entries[id]
        if (!e || !root.usable(id)) return false
        const l = root.layoutOf(screenName)
        const page = l.pages[l.page]
        const w = Math.min(e.size.w, cols), h = Math.min(e.size.h, rows)
        const spot = root.freeSpot(page, w, h, cols, rows)
        if (!spot) return false
        const uid = `${id}-${Date.now().toString(36)}`
        const pages = l.pages.slice()
        pages[l.page] = page.concat([{ uid, id, x: spot.x, y: spot.y, w, h, settings: {} }])
        root._save(screenName, { page: l.page, pages })
        return true
    }
    function remove(screenName: string, uid: string): void {
        const l = root.layoutOf(screenName)
        // (pages can be QML sequences, which flat() doesn't open: spread them)
        const name = root.entries[[].concat(...l.pages.map(p => Array.from(p))).find(w => w.uid === uid)?.id]?.name ?? "a piece"
        root._removeWithUndo(screenName, l, { page: l.page, pages: l.pages.map(p => p.filter(w => w.uid !== uid)) }, `Removed ${name}`)
    }
    // Moves/resizes a placed piece if the spot is inside the grid and free
    // (and the size within the manifest's minimum); false otherwise.
    function place(screenName: string, uid: string, x: int, y: int, w: int, h: int, cols: int, rows: int): bool {
        const l = root.layoutOf(screenName)
        const page = l.pages[l.page]
        const me = page.find(o => o.uid === uid)
        if (!me) return false
        const min = root.entries[me.id]?.minSize ?? { w: 1, h: 1 }
        if (w < min.w || h < min.h || x < 0 || y < 0 || x + w > cols || y + h > rows) return false
        const others = page.filter(o => o.uid !== uid)
        if (others.some(o => x < o.x + o.w && x + w > o.x && y < o.y + o.h && y + h > o.y)) return false
        if (me.x === x && me.y === y && me.w === w && me.h === h) return true
        const pages = l.pages.slice()
        pages[l.page] = page.map(o => o.uid === uid ? Object.assign({}, o, { x, y, w, h }) : o)
        root._save(screenName, { page: l.page, pages })
        return true
    }
    function setSetting(screenName: string, uid: string, key: string, value): void {
        const l = root.layoutOf(screenName)
        root._save(screenName, { page: l.page, pages: l.pages.map(p => p.map(o => {
            if (o.uid !== uid) return o
            const settings = Object.assign({}, o.settings ?? {}); settings[key] = value
            return Object.assign({}, o, { settings })
        })) })
    }

    // Edit mode (the layers go above windows and show handles): from IPC,
    // Settings, or a piece's right-click menu.
    property bool editing: false

    function freeSpot(page, w: int, h: int, cols: int, rows: int): var {
        const taken = (x, y) => page.some(o => x < o.x + o.w && x + w > o.x && y < o.y + o.h && y + h > o.y)
        for (let y = 0; y + h <= rows; y++)
            for (let x = 0; x + w <= cols; x++)
                if (!taken(x, y)) return { x, y }
        return null
    }

    // Page switching with the slide (the layers listen), for the IPC below.
    signal pageRequest(string screenName, int delta)

    IpcHandler {
        target: "pieces"
        function list(): string {
            return JSON.stringify(root.list.map(e => ({ id: e.id, name: e.name, source: e.source, errors: root.errorsOf(e.id) })))
        }
        // Next/previous page on the focused screen (bind these to keys).
        function next(): void { root.pageRequest(CompositorService.focusedMonitorName, 1) }
        function prev(): void { root.pageRequest(CompositorService.focusedMonitorName, -1) }
        function page(n: int): void { root.setPage(CompositorService.focusedMonitorName, n - 1) }
        function edit(): void { if (Config.options?.pieces?.enable) root.editing = true }
        function done(): void { root.editing = false }
        // Puts a piece on the focused screen's shown page (the Atelier's Add
        // to desktop from standalone Settings): "ok", or why not.
        function add(id: string): string {
            const scr = CompositorService.focusedMonitorName, g = root.grids[scr]
            if (!(Config.options?.pieces?.enable ?? false)) return "pieces are off"
            if (!root.entries[id]) return `no piece "${id}"`
            if (!g) return `no desktop layer on ${scr}`
            return root.add(scr, id, g.cols, g.rows) ? "ok" : "no free spot on this page"
        }
        // The grid per screen and the focused screen (what placing from the Atelier uses).
        // Remove the first placed piece of this id on the focused screen's
        // current page (Undo is offered, as from the edit handles).
        function remove(id: string): string {
            const screen = CompositorService.focusedMonitorName
            const l = root.layoutOf(screen)
            const w = (l.pages[l.page] ?? []).find(x => x.id === id)
            if (!w) return `no ${id} on this page`
            root.remove(screen, w.uid)
            return "ok"
        }
        function grid(): string { return JSON.stringify({ focused: CompositorService.focusedMonitorName, grids: root.grids }) }
    }
}
