# Lock screens

On niri, AnoShell locks the session itself (`lock.enable`, on by default):
**Super+L**, `qs ipc call lock lock`, and `loginctl lock-session` (the session
menu, idle tools). It uses the ext-session-lock protocol, so the compositor
keeps every screen covered even if the shell stops; the password is checked by
PAM's `login` service, faillock included. On Hyprland, hyprlock locks the
session and only the preview below runs in the shell.

The lock screen itself is replaceable: pick one in **Settings → General →
Lock screen** or **Settings → Atelier → Lock screens** (`lock.screen`, `default`
for the built-in one).

| Where | |
|---|---|
| `lockscreens/<id>/` in the shell | bundled |
| `~/.config/anoshell/lockscreens/<id>/` | yours; the same id overrides a bundled one |
| `~/.config/anoshell/lockscreens/<id>~<n>/` | installed from a catalog |

Bundled: **Minimal** (a large clock on your wallpaper and one line to type on)
and **Bioma Gate** (Bioma's lock screen: a large clock with a minute dial,
your picture and name, one field; ported from Bioma, GPL-3.0).

## Fingerprint

With **Fingerprint unlock** on (`lock.fingerprint.enable`, off by default)
and a print enrolled with fprintd (`fprintd-enroll`), touching the reader
unlocks too. It runs beside the password check, never instead of it: the
password always works, and after `lock.fingerprint.maxTries` (3) failed
scans only the password does until the next lock. A scan that times out with
no finger starts again; a reader that stops answering is retried with
growing pauses. The fingerprint check is the shell's own PAM service
(`modules/lock/pam/fprint`) without faillock, so a finger unlocks even while
too many wrong passwords have the password locked out, and failed scans don't
count towards that lockout. Previews never scan. If your PAM `login` stack
also has `pam_fprintd` (`/etc/pam.d/system-auth`), a password check may find
the reader busy with this scan; PAM then moves on to the password.

## Preview

**Preview** (Settings or the Atelier) or `qs ipc call lock preview <id>` shows a
lock screen on the focused screen without locking. Nothing is checked:
Escape, any password, a minute or `qs ipc call lock endPreview` closes it.

## Never locked out

The shell falls back to the built-in lock screen when the chosen one:

- doesn't compile, or its manifest is invalid;
- fails to load, or isn't ready within 3 seconds;
- has no `ctx` property (it couldn't take a password).

**Ctrl+Shift+Escape** on a locked screen also switches to the built-in one,
for a lock screen that draws but doesn't let you type (unless it takes every
key itself). In a preview on Hyprland the compositor's own Ctrl+Shift+Escape
bind gets the key first.

If the shell itself stops while locked, the screens stay covered: that's the
protocol doing its job, and it means nothing can unlock them until a locker
takes over. The restarted shell locks again (the marker above); whether niri
hands the covered screens to it hasn't been tested yet. From another TTY (Ctrl+Alt+F2) you can always end the
session with `loginctl terminate-session <id>` (`loginctl list-sessions`
shows it), which closes your apps.

## Making one

A folder with `lockscreen.json` (`id`, `name`, `description`, `author`,
`version`, `entry`, as for [launcher plugins](plugins.md)) and the entry QML
file. Its root `Item` fills the screen and gets `ctx`:

| `ctx.` | |
|---|---|
| `submit(password)` | check this password; unlocks when it's right |
| `failed()` | signal: the password was wrong (clear your field) |
| `busy` | a check is running |
| `error` | why the last try failed (`""` when none) |
| `capsLock` | Caps Lock is on |
| `user`, `avatar`, `wallpaper` | the user name, `~/.face` and the wallpaper as `file://` URLs |
| `screen` | the screen this copy covers (one per screen) |
| `preview` | shown as a preview: nothing is checked |
| `fingerprint` | `{ available, state, tries, maxTries, message }`: whether a fingerprint also unlocks (`state` `"off"`, `"scanning"`, `"fail"`, `"max"` or `"error"`); to show only, the shell runs the scan |

Give your password field `focus: true`. Unlocking is never the lock screen's
job: it only draws and calls `ctx.submit()`. The shell holds the lock itself
until PAM accepts a password; setting `GlobalStates.screenLocked` or changing
`lock.enable` while locked doesn't release it, and neither does reloading the
shell (a crash leaves a marker in `$XDG_RUNTIME_DIR/ano/locked`, and the
restarted shell locks again).

```qml
import QtQuick

Item {
    property var ctx
    Rectangle { anchors.fill: parent; color: "#101014" }
    TextInput {
        id: field
        anchors.centerIn: parent
        width: 300
        focus: true
        echoMode: TextInput.Password
        color: "white"
        onAccepted: ctx.submit(text)
    }
    Connections { target: ctx; function onFailed() { field.text = "" } }
}
```

Like pieces and plugins, a lock screen runs with the shell's rights, so it
could still do anything the shell can: install only ones you trust. From a
catalog the Atelier checks it first, flags code that touches the lock state, the
session lock or PAM, and asks (see [Atelier](atelier.md)).
