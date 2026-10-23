pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services

/**
 * Widgets: the desktop widget registry (spec desktop-widgets). A widget is a
 * folder with a `widget.json` manifest and a QML entry file; the bundled ones
 * live in the shell's widgets/, yours in ~/.config/anoshell/widgets/, where
 * the same id overrides a bundled one (as Looks and ThemeRegistry do).
 * Folders are watched, so a package you drop in shows up without a restart.
 *
 * A package whose manifest is invalid, or whose QML doesn't compile, is
 * listed with its errors and can't be placed; the rest keep working. Each
 * manifest change bumps the entry's revision, which is part of its QML URL,
 * so an edited widget is compiled afresh.
 *
 * Manifest: { id, name, description, author, version, entry ("main.qml"),
 * size: { w, h } in grid cells, minSize?: { w, h }, frame (true: the host
 * draws the card), settings: [{ key, type: bool|int|real|string|choice,
 * label, default, options? }] }.
 *
 * The layout (which widgets sit where) is in widgets.screens; editing helpers
 * for it are here so the picker, edit mode and IPC share them.
 */
Singleton {
    id: root

    readonly property string bundledDir: Quickshell.shellPath("widgets")
    readonly property string userDir: `${Directories.userConfigDir}/widgets`

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
        if (!e) return [`no widget "${id}"`]
        return root.qmlErrors[id] ? e.errors.concat([root.qmlErrors[id]]) : e.errors
    }
    function usable(id: string): bool { return root.errorsOf(id).length === 0 }

    // ── Manifests ───────────────────────────────────────────────────────
    property int _rev: 0
    function _ingest(source: string, dir: string, text: string): void {
        if (!dir.startsWith((source === "user" ? root.userDir : root.bundledDir) + "/")) return
        const dirId = dir.split("/").pop()
        let m = null
        const errors = []
        try { m = JSON.parse(text) } catch (err) { errors.push(`widget.json: invalid JSON: ${err.message ?? err}`) }
        const str = v => typeof v === "string" && v.length > 0 ? v : ""
        const cells = (v, d) => ({ w: Math.max(1, Math.min(12, Math.round(v?.w ?? d.w))), h: Math.max(1, Math.min(12, Math.round(v?.h ?? d.h))) })
        if (m) {
            if (m.id !== undefined && m.id !== dirId) errors.push(`widget.json: id "${m.id}" doesn't match its folder "${dirId}"`)
            if (!str(m.name)) errors.push("widget.json: no name")
            const entryFile = str(m.entry) || "main.qml"
            if (!/^[A-Za-z0-9_.-]+\.qml$/.test(entryFile)) errors.push(`widget.json: entry "${entryFile}" must be a .qml file in the folder`)
            if (m.settings !== undefined && !Array.isArray(m.settings)) errors.push("widget.json: settings must be a list")
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
        if (errors.length) console.warn(`[Widgets] ${dir}: ${errors.join("; ")}`)
        const q = Object.assign({}, root.qmlErrors); delete q[dirId]; root.qmlErrors = q
        if (root.checking) root._check(e)
    }
    function _drop(dir: string): void {
        const id = dir.split("/").pop()
        const user = dir.startsWith(root.userDir + "/")
        const m = user ? root._user : root._bundled
        if (m[id]?.dir !== dir) return
        const e = Object.assign({}, m); delete e[id]
        if (user) root._user = e; else root._bundled = e
    }

    // ── Compile check ───────────────────────────────────────────────────
    // Only while something needs it (the picker, the layer): compiling a
    // widget is the first point where its code is touched.
    property int _holds: 0
    readonly property bool checking: root._holds > 0
    function hold(on: bool): void { root._holds = Math.max(0, root._holds + (on ? 1 : -1)) }
    onCheckingChanged: if (root.checking) for (const e of Object.values(root.entries)) root._check(e)
    function _check(e): void {
        if (e.errors.length) return
        const c = Qt.createComponent(e.url, Component.Asynchronous)
        const done = () => {
            if (c.status === Component.Loading) return
            const q = Object.assign({}, root.qmlErrors)
            // "file:///…/id/Main.qml?r=3:2:38: …" → "Main.qml:2:38: …"
            q[e.id] = c.status === Component.Error ? c.errorString().trim().split(`file://${e.dir}/`).join("").replace(/\?r=\d+/g, "") : ""
            if (q[e.id]) console.warn(`[Widgets] ${e.id}: ${q[e.id]}`)
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
        // Only folders really inside the widget folders (a FolderListModel
        // lists the working directory until its folder is set).
        readonly property bool mine: filePath.startsWith((source === "user" ? root.userDir : root.bundledDir) + "/")
        path: mf.mine ? `${filePath}/widget.json` : ""
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

    // ── Layout (widgets.screens) ────────────────────────────────────────
    // Each running layer's grid, by screen name: { cols, rows }.
    property var grids: ({})
    function setGrid(screenName: string, cols: int, rows: int): void {
        if (root.grids[screenName]?.cols === cols && root.grids[screenName]?.rows === rows) return
        const g = Object.assign({}, root.grids); g[screenName] = { cols, rows }; root.grids = g
    }
    readonly property var screens: Config.options?.widgets?.screens ?? ({})
    function layoutOf(screenName: string): var {
        const s = root.screens[screenName]
        const pages = Array.isArray(s?.pages) && s.pages.length ? s.pages : [[]]
        return { page: Math.max(0, Math.min(pages.length - 1, s?.page ?? 0)), pages }
    }
    function _save(screenName: string, layout): void {
        const all = JSON.parse(JSON.stringify(root.screens))
        all[screenName] = layout
        Config.setNestedValue("widgets.screens", all)
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
        if (l.pages.length <= 1) { root._save(screenName, { page: 0, pages: [[]] }); return }
        const pages = l.pages.filter((_, i) => i !== page)
        root._save(screenName, { page: Math.min(l.page, pages.length - 1), pages })
    }
    // Places a widget on the shown page at the first free spot of a grid of
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
        root._save(screenName, { page: l.page, pages: l.pages.map(p => p.filter(w => w.uid !== uid)) })
    }
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
        target: "widgets"
        function list(): string {
            return JSON.stringify(root.list.map(e => ({ id: e.id, name: e.name, source: e.source, errors: root.errorsOf(e.id) })))
        }
        // Next/previous page on the focused screen (bind these to keys).
        function next(): void { root.pageRequest(CompositorService.focusedMonitorName, 1) }
        function prev(): void { root.pageRequest(CompositorService.focusedMonitorName, -1) }
        function page(n: int): void { root.setPage(CompositorService.focusedMonitorName, n - 1) }
    }
}
