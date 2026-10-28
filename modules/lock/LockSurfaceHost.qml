import QtQuick
import Quickshell
import qs.modules.common
import qs.services
import "."

/**
 * One screen's lock content: the chosen lock screen package (LockScreens), or
 * the built-in one when there is none, or it doesn't compile, fails to load,
 * isn't ready within 3 s, or has no `ctx` property (it couldn't take a
 * password). Ctrl+Shift+Escape also switches to the built-in one, in case a
 * package draws but doesn't let you type.
 */
FocusScope {
    id: host
    required property var ctx
    // A package id to show instead of the configured one (the preview).
    property string packageId: ""

    readonly property var entry: host.packageId !== ""
        ? (host.packageId !== "default" && LockScreens.registry.usable(host.packageId) ? LockScreens.registry.entries[host.packageId] : null)
        : LockScreens.current
    property bool fallback: false
    onEntryChanged: host.fallback = false
    readonly property bool usePackage: !!host.entry && !host.fallback

    function _giveUp(why) {
        if (host.fallback) return
        console.warn(`[lock] ${host.entry?.id ?? "?"}: ${why}; using the built-in lock screen`)
        host.fallback = true
    }

    // ctx is set as the package is created (setSource), so its bindings and
    // Connections see it from the start.
    readonly property string _url: host.usePackage ? host.entry.url : ""
    on_UrlChanged: host._url ? pkg.setSource(host._url, { ctx: host.ctx }) : pkg.setSource("")
    Component.onCompleted: if (host._url) pkg.setSource(host._url, { ctx: host.ctx })
    Loader {
        id: pkg
        anchors.fill: parent
        focus: host.usePackage
        onStatusChanged: if (status === Loader.Error) host._giveUp("it failed to load")
        // The Loader is a focus scope: the package's own focus: true field
        // gets the keys (focusing its root would take them from the field).
        onLoaded: if (!item.hasOwnProperty("ctx")) host._giveUp("it has no ctx property")
    }
    Timer {
        running: host.usePackage && pkg.status !== Loader.Ready
        interval: 3000
        onTriggered: host._giveUp("it wasn't ready within 3 s")
    }

    Loader {
        anchors.fill: parent
        focus: !host.usePackage
        active: !host.usePackage
        sourceComponent: DefaultLockSurface { ctx: host.ctx }
    }

    // Keys the package leaves alone reach here (a Shortcut doesn't fire in
    // the lock's layer surface).
    Keys.onPressed: event => {
        if (host.usePackage && event.key === Qt.Key_Escape && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) {
            host._giveUp("Ctrl+Shift+Escape")
            event.accepted = true
        }
    }
}
