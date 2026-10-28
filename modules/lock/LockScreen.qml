import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import qs
import qs.modules.common
import qs.services
import "."

/**
 * The lock screen. On niri the shell locks the session itself (ext-session-
 * lock, so the compositor keeps every screen covered even if the shell dies);
 * on Hyprland hyprlock does, and only the preview runs here.
 *
 * Every screen shows the chosen lock screen (LockScreens: the built-in one or
 * a package, through LockSurfaceHost); they share one password check, PAM's
 * "login" service. Locks on IPC `lock lock` and when logind asks
 * (`loginctl lock-session`, the session menu, idle tools).
 *
 * Preview (IPC `lock preview [id]`, Settings → Hub): the lock screen in an
 * ordinary window on the focused screen. Nothing is checked: Escape, a
 * password or 60 s close it.
 */
Scope {
    id: root

    readonly property bool lockEnabled: CompositorService.compositor === "niri" && (Config.options?.lock?.enable ?? true)

    // ── The latch ───────────────────────────────────────────────────────
    // The lock is held from a lock request until PAM says yes, and nothing
    // else releases it: GlobalStates.screenLocked only mirrors it (the bars
    // hide on it), so config changes, IPC, a package or any other code
    // setting it false don't unlock. It survives a shell reload
    // (PersistentProperties) and a crash: a marker in $XDG_RUNTIME_DIR, read
    // synchronously at start, locks again (the compositor keeps the screens
    // covered meanwhile).
    readonly property string markerPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/ano/locked`
    FileView { id: marker; path: root.markerPath; blockLoading: true; printErrors: false }
    readonly property bool _bootMarker: marker.text().trim() === "1"
    property bool _booting: true
    PersistentProperties {
        id: persist
        reloadableId: "anoSessionLock"
        property bool held: false
    }
    readonly property bool held: persist.held || (root._booting && root.lockEnabled && root._bootMarker)
    Component.onCompleted: {
        if (root.held) persist.held = true
        root._booting = false
        GlobalStates.screenLocked = persist.held
    }
    function _lock() {
        if (!root.lockEnabled || persist.held) return
        persist.held = true
        markerProc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf 1 > "$1"', "sh", root.markerPath]
        markerProc.running = true
    }
    function _unlocked() {
        persist.held = false
        markerProc.command = ["rm", "-f", "--", root.markerPath]
        markerProc.running = true
    }
    Process { id: markerProc }
    onHeldChanged: {
        GlobalStates.screenLocked = root.held
        auth.reset()
        if (pam.active) pam.abort()
        if (root.sessionPath) Quickshell.execDetached(["gdbus", "call", "--system", "--dest", "org.freedesktop.login1",
            "--object-path", root.sessionPath, "--method", "org.freedesktop.login1.Session.SetLockedHint", root.held ? "true" : "false"])
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked === root.held) return
            if (GlobalStates.screenLocked) {
                root._lock()
                if (!root.held) GlobalStates.screenLocked = false // nothing to lock with here
            } else {
                GlobalStates.screenLocked = true // only a password unlocks
            }
        }
    }
    // A lock the compositor refused (another locker holds the session) leaves
    // nothing to protect: let go rather than hide the bars for good.
    Timer {
        running: root.held && !sessionLock.secure
        interval: 5000
        onTriggered: {
            console.warn("[lock] the compositor didn't confirm the lock; letting go")
            root._unlocked()
            Quickshell.execDetached(["notify-send", "-a", "AnoShell", "Couldn't lock the screen", "The compositor refused the lock (is another locker running?)."])
        }
    }

    // ── Password check (one for all screens) ────────────────────────────
    QtObject {
        id: auth
        property bool busy: false
        property string error: ""
        property string _pending: ""
        signal failed()
        function submit(password) {
            if (auth.busy || !root.held) return
            auth._pending = password
            auth.busy = true
            auth.error = ""
            if (!pam.start()) {
                auth._pending = ""
                auth.busy = false
                auth.error = "Couldn't start the password check"
            }
        }
        function reset() { auth.busy = false; auth.error = ""; auth._pending = "" }
    }
    PamContext {
        id: pam
        config: "login"
        onPamMessage: {
            if (pam.responseRequired) {
                if (auth._pending !== "") { pam.respond(auth._pending); auth._pending = "" }
                else {
                    // A second question (a code, a token): not supported here.
                    // abort() signals nothing, so this try ends now.
                    auth.error = pam.message || "PAM asked for more than a password"
                    pam.abort()
                    auth.busy = false
                    auth.failed()
                }
            } else if (pam.messageIsError && pam.message) {
                auth.error = pam.message
            }
        }
        onCompleted: result => {
            auth.busy = false
            auth._pending = ""
            if (result === PamResult.Success) {
                auth.error = ""
                root._unlocked()
                return
            }
            auth.error = result === PamResult.MaxTries ? "Too many tries: wait a moment" : (auth.error || "Wrong password")
            auth.failed()
        }
        // completed(PamResult.Error) follows, which ends the try.
        onError: err => { auth.error = `Password check failed: ${PamError.toString(err)}` }
    }

    // ── The lock ────────────────────────────────────────────────────────
    WlSessionLock {
        id: sessionLock
        locked: root.held
        WlSessionLockSurface {
            id: surface
            color: "black"
            LockSurfaceHost {
                id: lockHost
                anchors.fill: parent
                focus: true
                ctx: LockContext {
                    screen: surface.screen
                    busy: auth.busy
                    error: auth.error
                    onSubmitted: password => auth.submit(password)
                }
                Connections { target: auth; function onFailed() { lockHost.ctx.failed() } }
            }
        }
    }

    // logind's Lock for this session (loginctl lock-session, idle tools):
    // signals come from the session's object path, the id escaped as
    // systemd does (anything but a letter, or a digit after the first
    // character, becomes _xx).
    readonly property string sessionPath: {
        const id = Quickshell.env("XDG_SESSION_ID") ?? ""
        if (!id) return ""
        let s = ""
        for (let i = 0; i < id.length; i++) {
            const c = id[i]
            s += /[A-Za-z]/.test(c) || (i > 0 && /[0-9]/.test(c)) ? c : "_" + c.charCodeAt(0).toString(16).padStart(2, "0")
        }
        return `/org/freedesktop/login1/session/${s}`
    }
    property int _watchFails: 0
    Process {
        id: logindWatch
        running: root.lockEnabled && root.sessionPath !== ""
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", root.sessionPath]
        stdout: SplitParser {
            onRead: line => {
                root._watchFails = 0
                if (line.includes("org.freedesktop.login1.Session.Lock (")) root._lock()
            }
        }
        // gdbus exits if the bus restarts: watch again, giving up after a
        // few quick failures (no gdbus: ano doctor says so).
        onExited: if (root.lockEnabled && ++root._watchFails <= 5) rewatch.restart()
    }
    Timer { id: rewatch; interval: 5000; onTriggered: logindWatch.running = root.lockEnabled && root.sessionPath !== "" }

    // ── Preview ─────────────────────────────────────────────────────────
    PanelWindow {
        id: previewWin
        visible: LockScreens.previewId !== ""
        screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "black"
        WlrLayershell.namespace: "quickshell:lockPreview"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: previewWin.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Loader {
            anchors.fill: parent
            active: previewWin.visible
            focus: true
            sourceComponent: LockSurfaceHost {
                focus: true
                packageId: LockScreens.previewId
                ctx: LockContext {
                    preview: true
                    screen: previewWin.screen
                    onSubmitted: LockScreens.endPreview()
                }
                Keys.onEscapePressed: LockScreens.endPreview()
            }
        }
        Rectangle {
            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 16 }
            width: note.implicitWidth + 24; height: note.implicitHeight + 12
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.6)
            z: 10
            Text {
                id: note
                anchors.centerIn: parent
                color: "white"
                text: "Preview: nothing is checked. Escape or any password closes it."
            }
        }
        Timer { running: previewWin.visible; interval: 60000; onTriggered: LockScreens.endPreview() }
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root._lock() }
        function unlock(): void { /* only a password unlocks */ }
        function preview(id: string): void { LockScreens.preview(id) }
        function status(): string {
            return JSON.stringify({ enabled: root.lockEnabled, locked: root.held, secure: sessionLock.secure,
                screen: LockScreens.selected, using: LockScreens.current?.id ?? "default" })
        }
    }
}
