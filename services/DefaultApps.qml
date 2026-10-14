pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Launches the user's default apps (Config.options.apps.*). Keybinds and
 * shell actions route through here so changing an app never means
 * regenerating binds:  qs -c ano ipc call apps run terminal
 *
 * An app value is a command line split on spaces (e.g. "kitty -1").
 */
Singleton {
    id: root

    function command(kind: string): list<string> {
        const value = (Config.options?.apps?.[kind] ?? "").trim()
        return value.length > 0 ? value.split(/\s+/) : []
    }

    // kind: "terminal" | "browser" | "fileManager"; extra args appended (e.g. a path).
    function run(kind: string, args): bool {
        const cmd = root.command(kind)
        if (cmd.length === 0) {
            console.warn(`[DefaultApps] no ${kind} configured`)
            return false
        }
        Quickshell.execDetached(cmd.concat(args ?? []))
        return true
    }

    IpcHandler {
        target: "apps"
        function run(kind: string): void { root.run(kind, []) }
        function open(kind: string, arg: string): void { root.run(kind, [arg]) }
    }
}
