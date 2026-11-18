pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import "../modules/lock/lockLayout.js" as LockLayout

/**
 * LockScreens: lock screen packages (docs/lockscreens.md), bundled in the
 * shell's lockscreens/ and yours in ~/.config/anoshell/lockscreens/.
 * lock.screen picks one; "default" (or one that's missing or broken) is the
 * built-in lock screen. Unlocking always stays with the shell: a lock screen
 * only draws, and gets the password field's state and a submit() to call.
 */
Singleton {
    id: root

    readonly property PackageRegistry registry: PackageRegistry { kind: "lockscreens"; manifest: "lockscreen.json" }
    readonly property var list: root.registry.list
    readonly property string selected: Config.options?.lock?.screen ?? "default"
    // The package to load, or null for the built-in one.
    readonly property var current: root.selected !== "default" && root.registry.usable(root.selected) ? root.registry.entries[root.selected] : null

    function select(id: string): void { Config.setNestedValue("lock.screen", id || "default") }

    // The preview (modules/lock/LockScreen.qml shows it): "" when none.
    property string previewId: ""
    // Standalone Settings (settings.qml) sets this: its preview is the
    // shell's, asked for over IPC.
    property bool remote: false
    function preview(id: string): void {
        if (root.remote) Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "lock", "preview", id || root.selected])
        else root.previewId = id || root.selected
    }
    function endPreview(): void { root.previewId = "" }

    // ── Layouts (lock.layouts; modules/lock/lockLayout.js) ──
    // A package supports them by bringing its own arrangement as `layout` in lockscreen.json.
    function ownLayout(id: string): var { return id === "default" ? null : (root.registry.entries[id]?.manifest?.layout ?? null) }
    function supportsLayout(id: string): bool { return id === "default" || (Array.isArray(root.ownLayout(id)) && root.registry.usable(id)) }
    function layoutOf(id: string): var { return LockLayout.resolve(Config.options?.lock?.layouts ?? {}, id, root.ownLayout(id)) }
    function defaultLayoutOf(id: string): var { return LockLayout.defaultsFor(id, root.ownLayout(id)) }
    function arranged(id: string): bool { return Array.isArray(Config.options?.lock?.layouts?.[id]) && Config.options.lock.layouts[id].length > 0 }
    function saveLayout(id: string, list: var): void {
        const all = Object.assign({}, Config.options?.lock?.layouts ?? {})
        if (list && list.length) all[id] = LockLayout.normalize(list, id, root.ownLayout(id))
        else delete all[id]
        Config.setNestedValue("lock.layouts", all)
    }
    // The full-screen layout editor (modules/lock/LockLayoutEditor.qml): the lock screen being arranged, "" none.
    property string editingId: ""
    function editLayout(id: string): void {
        const target = id || root.selected
        if (root.remote) Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "lock", "editLayout", target])
        else if (root.supportsLayout(target)) root.editingId = target
    }
    function endEdit(): void { root.editingId = "" }
}
