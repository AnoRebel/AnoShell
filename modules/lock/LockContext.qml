import QtQuick
import Quickshell
import qs.modules.common
import qs.services

/**
 * What a lock screen (the built-in one or a package, docs/lockscreens.md) gets
 * as `ctx`. It only draws: the password goes to submit(), and the shell checks
 * it with PAM. In a preview nothing is checked and submit() ends the preview.
 */
QtObject {
    id: ctx

    property var screen: null          // the ShellScreen this surface covers
    property bool preview: false
    property bool busy: false          // checking a password
    property string error: ""          // why the last try failed ("" none)
    readonly property bool capsLock: LockKeys.capsLock
    readonly property string user: Quickshell.env("USER") || "user"
    readonly property string avatar: `file://${Directories.userAvatarPath}`
    readonly property string wallpaper: {
        const p = Config.options?.background?.wallpaperPath ?? ""
        return p.length ? (p.startsWith("file://") ? p : "file://" + p) : ""
    }

    signal failed()                    // a wrong password: clear the field, shake
    signal submitted(string password)  // the host's; lock screens call submit()

    function submit(password) {
        if (typeof password !== "string" || password.length === 0 || ctx.busy) return
        ctx.submitted(password)
    }
}
