pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Looks: the shell's switchable visual identities (design-identity spec, D6).
 *
 * A look is a JSON file (format: looks/schema.md). Built-ins live in the
 * shell's looks/; yours in ~/.config/anoshell/looks/, where the same id
 * overrides a built-in. Files are watched, so a look you drop in or edit
 * appears without a restart. A file that fails validation is listed with its
 * errors and can't be applied.
 *
 * Which look is active: your global choice (appearance.look) > your choice for
 * the current panel family (appearance.familyLooks[family]) > the family's
 * default > Liquid. `current` is the active look merged over Liquid's values,
 * so a look only has to say what it changes.
 */
Singleton {
    id: root

    readonly property string bundledDir: Quickshell.shellPath("looks")
    readonly property string userDir: `${Directories.userConfigDir}/looks`

    // Family defaults (spec: each family declares one).
    readonly property var familyDefaults: ({ "ano": "liquid", "hefty": "liquid", "clean": "neotech", "minimal": "ink" })
    readonly property var knownShaders: ["caustics", "paper_grain", "ink_bleed", "grid_scan", "clay_soft"]
    readonly property var fontAliases: ["@main", "@mono", "@reading", "@expressive"]

    // id -> { id, name, description, source: "bundled"|"user", path, look, errors[] }
    property var entries: ({})
    readonly property var list: Object.values(root.entries).sort((a, b) => a.name.localeCompare(b.name))

    function usable(id) { const e = root.entries[id]; return !!e && e.errors.length === 0 }

    readonly property string family: PanelGate.family
    readonly property string activeId: {
        const global = Config.options?.appearance?.look ?? ""
        const perFamily = (Config.options?.appearance?.familyLooks ?? {})[root.family] ?? ""
        for (const id of [global, perFamily, root.familyDefaults[root.family] ?? "", "liquid"])
            if (id && root.usable(id)) return id
        return "liquid"
    }
    readonly property var current: root._merge(root.entries["liquid"]?.look ?? root._fallback, root.entries[root.activeId]?.look ?? {})

    // Used until liquid.json has loaded (and if it ever fails to).
    readonly property var _fallback: ({
        shape: { radiusScale: 1, stroke: 0, connectedRadius: 18, squircle: false },
        material: { kind: "solid", glass: true }, texture: null, typography: {},
        motion: {
            liquid: { spring: 3.2, damping: 0.28, mass: 1.0 },
            settle: { spring: 7.0, damping: 0.65, mass: 1.0 },
            snappy: { spring: 6.0, damping: 0.55, mass: 0.8 }
        },
        surfaces: {}
    })

    function _merge(base, over) {
        const out = JSON.parse(JSON.stringify(base ?? {}))
        for (const k in (over ?? {})) {
            const v = over[k]
            out[k] = (v && typeof v === "object" && !Array.isArray(v) && out[k] && typeof out[k] === "object")
                ? root._merge(out[k], v) : v
        }
        return out
    }

    // Per-surface view of the current look: its surfaces.<name> overrides
    // merged over the look itself.
    function forSurface(name) {
        const s = root.current.surfaces?.[name]
        return s ? root._merge(root.current, s) : root.current
    }

    // Resolve a typography value ("@mono" etc. map to your configured fonts).
    function font(role, fallback) {
        const v = root.current.typography?.[role]
        if (!v) return fallback
        const f = Config.options?.appearance?.fonts ?? {}
        return v === "@main" ? f.main : v === "@mono" ? f.monospace : v === "@reading" ? f.reading
            : v === "@expressive" ? f.expressive : v
    }

    // ── Validation (looks/schema.md) ─────────────────────────────────────
    function validate(look, fileId) {
        const e = []
        const num = (v, lo, hi, path) => { if (v !== undefined && (typeof v !== "number" || v < lo || v > hi)) e.push(`${path} must be a number from ${lo} to ${hi}`) }
        const obj = (v, path) => { if (v !== undefined && v !== null && (typeof v !== "object" || Array.isArray(v))) e.push(`${path} must be an object`) }
        if (!look || typeof look !== "object" || Array.isArray(look)) return ["the file must contain a JSON object"]
        if (typeof look.id !== "string" || !look.id) e.push("id is required")
        else if (look.id !== fileId) e.push(`id "${look.id}" must match the file name "${fileId}"`)
        if (typeof look.name !== "string" || !look.name) e.push("name is required")
        obj(look.shape, "shape"); obj(look.material, "material"); obj(look.typography, "typography")
        obj(look.motion, "motion"); obj(look.surfaces, "surfaces")
        const sh = look.shape ?? {}
        num(sh.radiusScale, 0.2, 3, "shape.radiusScale"); num(sh.stroke, 0, 4, "shape.stroke")
        num(sh.connectedRadius, 0, 48, "shape.connectedRadius")
        const kind = look.material?.kind
        if (kind !== undefined && !["solid", "paper", "clay"].includes(kind)) e.push(`material.kind "${kind}" is not solid, paper or clay`)
        if (look.texture !== undefined && look.texture !== null) {
            if (!root.knownShaders.includes(look.texture.shader)) e.push(`texture.shader "${look.texture.shader}" is not a known shader (${root.knownShaders.join(", ")})`)
            if (look.texture.animate !== undefined && !["static", "interaction"].includes(look.texture.animate)) e.push("texture.animate must be static or interaction")
        }
        for (const role in (look.typography ?? {})) {
            const v = look.typography[role]
            if (typeof v !== "string") e.push(`typography.${role} must be a font name or ${root.fontAliases.join("/")}`)
            else if (v.startsWith("@") && !root.fontAliases.includes(v)) e.push(`typography.${role}: unknown alias ${v}`)
        }
        for (const tok in (look.motion ?? {})) {
            if (!["liquid", "settle", "snappy"].includes(tok)) { e.push(`motion.${tok} is not liquid, settle or snappy`); continue }
            const m = look.motion[tok] ?? {}
            num(m.spring, 0.5, 40, `motion.${tok}.spring`); num(m.damping, 0.05, 1, `motion.${tok}.damping`); num(m.mass, 0.2, 3, `motion.${tok}.mass`)
        }
        return e
    }

    function _ingest(source, path, text) {
        // A FolderListModel lists the working directory while its folder is
        // unset; only files really inside the look folders count.
        if (!path.startsWith((source === "user" ? root.userDir : root.bundledDir) + "/")) return
        const fileId = path.split("/").pop().replace(/\.json$/, "")
        let look = null, errors
        try { look = JSON.parse(text) } catch (err) { errors = [`invalid JSON: ${err.message ?? err}`] }
        if (!errors) errors = root.validate(look, fileId)
        const prev = root.entries[fileId]
        // A user look overrides a built-in of the same id, but not the reverse.
        if (prev && prev.source === "user" && source === "bundled" && prev.path !== path) return
        const e = Object.assign({}, root.entries)
        e[fileId] = { id: fileId, name: look?.name ?? fileId, description: look?.description ?? "", source, path,
                      look: errors.length ? null : look, errors }
        root.entries = e
        if (errors.length) console.warn(`[Looks] ${path}: ${errors.join("; ")}`)
    }
    function _drop(path) {
        const id = path.split("/").pop().replace(/\.json$/, "")
        if (root.entries[id]?.path !== path) return
        const e = Object.assign({}, root.entries); delete e[id]; root.entries = e
    }

    FolderListModel { id: bundledFolder; folder: "file://" + root.bundledDir; nameFilters: ["*.json"]; showDirs: false }
    // A FolderListModel on a missing folder lists the process's working
    // directory instead, so the user folder is created first and only then
    // watched.
    property bool _userReady: false
    Process {
        running: true
        command: ["mkdir", "-p", root.userDir]
        onExited: root._userReady = true
    }
    FolderListModel { id: userFolder; folder: root._userReady ? "file://" + root.userDir : ""; nameFilters: ["*.json"]; showDirs: false }

    component LookFile: FileView {
        required property string filePath
        required property string source
        path: filePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._ingest(source, filePath, text())
        onLoadFailed: root._drop(filePath)
        Component.onDestruction: root._drop(filePath)
    }
    Instantiator {
        model: bundledFolder
        delegate: LookFile { source: "bundled" }
    }
    Instantiator {
        model: root._userReady ? userFolder : null
        delegate: LookFile { source: "user" }
    }

    IpcHandler {
        target: "looks"
        function list(): string {
            return JSON.stringify(root.list.map(e => ({ id: e.id, name: e.name, source: e.source, errors: e.errors })))
        }
        function active(): string { return root.activeId }
        function set(id: string): void { Config.setNestedValue("appearance.look", id) }
    }
}
