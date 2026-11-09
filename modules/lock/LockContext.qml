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
    // Fingerprint, to show only (the shell runs the scan): available (a
    // reader with your print, and it's on), state "off"|"scanning"|"fail"|
    // "max"|"error", tries, maxTries, message ("" none).
    property var fingerprint: ({ available: false, state: "off", tries: 0, maxTries: 0, message: "" })
    readonly property bool capsLock: LockKeys.capsLock
    readonly property string user: Quickshell.env("USER") || "user"
    readonly property string avatar: `file://${Directories.userAvatarPath}`
    readonly property string wallpaper: {
        const p = Config.options?.background?.wallpaperPath ?? ""
        return p.length ? (p.startsWith("file://") ? p : "file://" + p) : ""
    }

    // How many characters are in the focused screen's field, shared by every
    // screen's copy so the others can mirror it as dots. Only the length
    // ever leaves the field, never the text. The host binds it.
    property int typedLength: 0

    signal failed()                    // a wrong password: clear the field, shake
    signal submitted(string password)  // the host's; lock screens call submit()
    signal typedLengthReported(int length) // the host's; lock screens call reportTyped()

    function submit(password) {
        if (typeof password !== "string" || password.length === 0 || ctx.busy) return
        ctx.submitted(password)
    }
    // Call from the field that has focus when its text changes (and when it
    // gains focus) with its length.
    function reportTyped(length) {
        if (typeof length === "number") ctx.typedLengthReported(Math.max(0, Math.floor(length)))
    }
}
