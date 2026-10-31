pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.common.functions

/**
 * Atelier — the shell side of anod's content
 * store (spec atelier): themes, looks, pieces (desktop widgets), launcher
 * plugins, lock screens, wallpapers and rices from three sources (built-in,
 * yours in ~/.config/anoshell/<type>/, installed from a catalog). anod lists,
 * fetches, verifies and installs (atelier.*); installing never applies, apply
 * is the shell's own action per type (apply()). Exists only while the
 * Atelier page or `atelier` IPC uses it; anod bumps
 * $XDG_STATE_HOME/anoshell/atelier/revision after every change, which this
 * watches.
 */
Singleton {
    id: root

    readonly property var types: [
        { id: "themes", name: "Themes", icon: "palette", code: false },
        { id: "looks", name: "Looks", icon: "style", code: false },
        { id: "pieces", name: "Pieces", icon: "widgets", code: true },
        { id: "plugins", name: "Plugins", icon: "extension", code: true },
        { id: "lockscreens", name: "Lock screens", icon: "lock", code: true },
        { id: "wallpapers", name: "Wallpapers", icon: "wallpaper", code: false },
        { id: "rices", name: "Rices", icon: "auto_awesome_mosaic", code: false }
    ]
    property string tab: "themes"       // the tab the page shows (IPC atelier open sets it)
    function typeName(t) { return root.types.find(x => x.id === t)?.name ?? t }

    property var items: []              // local: built-in, user, installed
    property var catalog: []            // catalog entries (installed: true when they are local too)
    property var catalogs: []           // [{url, name, ok, error, fetchedAt, offline}]
    property var lastRice: null         // {id, name, appliedAt} while an undo is possible
    property int revision: -1
    property bool loading: false
    property bool refreshing: false
    property string error: ""

    function list() {
        root.loading = true
        Anod.call("atelier.list", {}, (r, e) => {
            root.loading = false
            if (!r) { root.error = e?.message ?? "anod didn't answer"; return }
            root.error = ""
            root._take(r)
        })
    }
    function refresh() {
        root.refreshing = true
        Anod.call("atelier.refresh", {}, (r, e) => {
            root.refreshing = false
            if (!r) { root.error = e?.message ?? "anod didn't answer"; return }
            root.error = ""
            root._take(r)
        }, 120000)
    }
    function _take(r) {
        root.items = r.items ?? []
        root.catalog = r.catalog ?? []
        root.catalogs = r.catalogs ?? []
        root.lastRice = r.lastRice ?? null
        if (typeof r.revision === "number") root.revision = r.revision
    }

    // Two steps for a catalog item: prepare (download, checksum, audit) gives
    // a token plus what the confirmation shows; commit installs it.
    function prepare(type, id, catalog, cb) { Anod.call("atelier.prepare", { type, id, catalog }, cb, 180000) }
    function commit(token, cb) { Anod.call("atelier.commit", { token }, cb, 60000) }
    function cancel(token) { if (token) Anod.call("atelier.cancel", { token }) }
    function remove(type, id, cb) { Anod.call("atelier.remove", { type, id }, cb) }
    function riceApply(id, layers, cb) { Anod.call("atelier.riceApply", { id, layers }, cb, 180000) }
    function riceUndo(cb) { Anod.call("atelier.riceUndo", {}, cb, 180000) }
    function riceExport(name, cb) { Anod.call("atelier.riceExport", { name }, cb, 60000) }
    // Wallhaven (wallpapers): search, then install one (anod fetches the real
    // image path itself, verifies it and keeps a receipt).
    function wallhaven(query, page, cb) { Anod.call("atelier.wallhaven", { query, page }, cb, 30000) }
    function wallhavenInstall(id, cb) { Anod.call("atelier.wallhavenInstall", { id }, cb, 150000) }

    // ── Applying (the shell's job; install never applies) ─────────────
    function isActive(item) {
        switch (item.type) {
        case "themes": return (Config.options?.appearance?.theme?.source ?? "") === "static"
            && (Config.options?.appearance?.theme?.name ?? "") === item.id
        case "looks": return (Config.options?.appearance?.look ?? "") === item.id
        case "wallpapers": return !!item.path && (Config.options?.background?.wallpaperPath ?? "") === item.path
        case "pieces": {
            const scr = Config.options?.pieces?.screens ?? {}
            return Object.values(scr).some(s => (s?.pages ?? []).some(p => (p ?? []).some(p2 => p2.id === item.id)))
        }
        case "plugins": return LauncherPlugins.isEnabled(item.id)
        case "lockscreens": return LockScreens.selected === item.id
        }
        return false
    }
    // Why a local code item can't be used ([] when it can).
    function problems(item) {
        switch (item.type) {
        case "pieces": return Pieces.errorsOf(item.id)
        case "plugins": return LauncherPlugins.registry.errorsOf(item.id)
        case "lockscreens": return item.id === "default" ? [] : LockScreens.registry.errorsOf(item.id)
        }
        return []
    }
    // Returns "" or a message for the page to show.
    function apply(item) {
        switch (item.type) {
        case "themes":
            Config.setNestedValue("appearance.theme.source", "static")
            Config.setNestedValue("appearance.theme.name", item.id)
            return ""
        case "looks":
            Config.setNestedValue("appearance.look", item.id)
            return ""
        case "wallpapers":
            Wallpapers.apply(item.path)
            return ""
        case "pieces": {
            if (!(Config.options?.pieces?.enable ?? false)) return "Turn on pieces first (Settings → Modules → Desktop pieces)."
            const scr = CompositorService.focusedMonitorName
            const g = Pieces.grids[scr]
            // No pieces layer in this process (standalone Settings): the
            // running shell places it, on its focused screen.
            if (!g) { Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "pieces", "add", item.id]); return "" }
            return Pieces.add(scr, item.id, g.cols, g.rows) ? "" : "No free spot on this desktop page."
        }
        case "plugins":
            LauncherPlugins.setEnabled(item.id, !LauncherPlugins.isEnabled(item.id))
            return ""
        case "lockscreens":
            LockScreens.select(item.id)
            return ""
        }
        return "Nothing to apply for this type."
    }

    readonly property string _revisionPath: `${FileUtils.trimFileProtocol(Directories.state)}/anoshell/atelier/revision`
    FileView {
        path: root._revisionPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const n = parseInt(text().trim(), 10)
            if (!isNaN(n) && n !== root.revision) root.list()
        }
    }
    Connections {
        target: Anod
        function onAvailableChanged() { if (Anod.available) root.list() }
    }
    Component.onCompleted: if (Anod.available) root.list()
}
