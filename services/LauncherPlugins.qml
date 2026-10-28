pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

/**
 * LauncherPlugins: launcher plugin packages (docs/plugins.md), bundled in the
 * shell's plugins/ and yours in ~/.config/anoshell/plugins/. Each is off until
 * you turn it on (search.userPlugins lists the ones that are on); the launcher
 * loads only those (modules/search/Providers.qml).
 */
Singleton {
    id: root

    readonly property PackageRegistry registry: PackageRegistry { kind: "plugins"; manifest: "plugin.json" }
    readonly property var list: root.registry.list
    readonly property var enabledIds: Config.options?.search?.userPlugins ?? []
    // On and loadable, in the order of the list.
    readonly property var active: root.list.filter(e => root.enabledIds.includes(e.id) && root.registry.usable(e.id))

    function isEnabled(id: string): bool { return root.enabledIds.includes(id) }
    function setEnabled(id: string, on: bool): void {
        const ids = root.enabledIds.filter(x => x !== id)
        if (on) ids.push(id)
        Config.setNestedValue("search.userPlugins", ids)
    }
}
