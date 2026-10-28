pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

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
}
