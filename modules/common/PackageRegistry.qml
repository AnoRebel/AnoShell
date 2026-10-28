pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * PackageRegistry: the folders of one kind of QML package (launcher plugins,
 * lock screens), merged from the shell's bundled folder and the user's
 * ~/.config/anoshell/<kind>/, where the same id overrides a bundled one. A
 * package is a folder with a JSON manifest (`manifest`) and a QML entry file.
 * Folders are watched; the Hub installs a fresh `<id>~<n>` folder per version
 * and the id is the part before "~". Each manifest load bumps the entry's
 * revision, part of its QML URL, so an edited package compiles afresh.
 *
 * An entry is { id, name, description, author, version, entry, source:
 * "bundled"|"user", dir, url, errors[], manifest } (`manifest` is the parsed
 * JSON, for kind-specific fields). A package whose manifest is invalid or
 * whose QML doesn't compile is listed with its errors (errorsOf) and isn't
 * usable; the others are unaffected.
 *
 * ponytail: services/Widgets.qml predates this and keeps its own copy;
 * move it onto this when it next needs work.
 */
Scope {
    id: root

    required property string kind      // "plugins", "lockscreens": the folder name
    required property string manifest  // "plugin.json"
    property string bundledDir: Quickshell.shellPath(root.kind)
    readonly property string userDir: `${Directories.userConfigDir}/${root.kind}`

    property var _bundled: ({})
    property var _user: ({})
    property var qmlErrors: ({})       // id -> compile error ("" when it compiled)
    readonly property var entries: Object.assign({}, root._bundled, root._user)
    readonly property var list: Object.values(root.entries).sort((a, b) => a.name.localeCompare(b.name))

    function errorsOf(id: string): var {
        const e = root.entries[id]
        if (!e) return [`no ${root.kind} package "${id}"`]
        return root.qmlErrors[id] ? e.errors.concat([root.qmlErrors[id]]) : e.errors
    }
    // Usable once its manifest is valid and its QML compiled (check()).
    function usable(id: string): bool { return root.errorsOf(id).length === 0 && root.qmlErrors[id] === "" }

    property int _rev: 0
    function _ingest(source: string, dir: string, text: string): string {
        const dirId = dir.split("/").pop().replace(/~\d+$/, "")
        let m = null
        const errors = []
        try { m = JSON.parse(text) } catch (err) { errors.push(`${root.manifest}: invalid JSON: ${err.message ?? err}`) }
        const str = v => typeof v === "string" && v.length > 0 ? v : ""
        if (m) {
            if (m.id !== undefined && m.id !== dirId) errors.push(`${root.manifest}: id "${m.id}" doesn't match its folder "${dirId}"`)
            if (!str(m.name)) errors.push(`${root.manifest}: no name`)
            if (!/^[A-Za-z0-9_.-]+\.qml$/.test(str(m.entry) || "main.qml")) errors.push(`${root.manifest}: entry "${m.entry}" must be a .qml file in the folder`)
        }
        root._rev++
        const entryFile = str(m?.entry) || "main.qml"
        const e = {
            id: dirId, name: str(m?.name) || dirId, description: str(m?.description), author: str(m?.author),
            version: str(m?.version), entry: entryFile, source, dir,
            url: `file://${dir}/${entryFile}?r=${root._rev}`, errors, manifest: m ?? {}
        }
        const all = Object.assign({}, source === "user" ? root._user : root._bundled)
        all[dirId] = e
        if (source === "user") root._user = all; else root._bundled = all
        if (errors.length) console.warn(`[${root.kind}] ${dir}: ${errors.join("; ")}`)
        const q = Object.assign({}, root.qmlErrors); delete q[dirId]; root.qmlErrors = q
        root._check(e)
        return entryFile
    }
    function _drop(dir: string): void {
        const id = dir.split("/").pop().replace(/~\d+$/, "")
        const user = dir.startsWith(root.userDir + "/")
        const m = user ? root._user : root._bundled
        if (m[id]?.dir !== dir) return
        const e = Object.assign({}, m); delete e[id]
        if (user) root._user = e; else root._bundled = e
    }

    // Compiling is the first point where a package's code is touched; it
    // only creates the component, never an object.
    function _check(e): void {
        if (e.errors.length) return
        const c = Qt.createComponent(e.url, Component.Asynchronous)
        const done = () => {
            if (c.status === Component.Loading) return
            if (root.entries[e.id]?.url !== e.url) { c.destroy(); return } // stale
            const q = Object.assign({}, root.qmlErrors)
            q[e.id] = c.status === Component.Error ? c.errorString().trim().split(`file://${e.dir}/`).join("").replace(/\?r=\d+/g, "") : ""
            if (q[e.id]) console.warn(`[${root.kind}] ${e.id}: ${q[e.id]}`)
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
        required property string filePath
        required property string source
        property int _tries: 0
        readonly property bool mine: filePath.startsWith((source === "user" ? root.userDir : root.bundledDir) + "/")
            && !/^[_.]/.test(filePath.split("/").pop())
        path: mf.mine ? `${filePath}/${root.manifest}` : ""
        watchChanges: mf.mine
        onFileChanged: reload()
        onLoaded: mf.entryFile = root._ingest(source, filePath, text())
        // A folder copied in may show up before its manifest: look again shortly.
        onLoadFailed: { root._drop(filePath); if (mf.mine && mf._tries++ < 5) retry.restart() }
        Component.onDestruction: root._drop(filePath)
        property Timer retry: Timer { interval: 1000; onTriggered: mf.reload() }
        // An edit to the entry file compiles it afresh too (through the
        // manifest, which bumps the revision in the URL).
        property string entryFile: ""
        property FileView entryWatch: FileView {
            path: mf.mine && mf.entryFile ? `${mf.filePath}/${mf.entryFile}` : ""
            watchChanges: true
            printErrors: false
            onFileChanged: mf.reload()
        }
    }
    Instantiator { model: bundledFolder; delegate: Manifest { source: "bundled" } }
    Instantiator { model: root._userReady ? userFolder : null; delegate: Manifest { source: "user" } }
}
