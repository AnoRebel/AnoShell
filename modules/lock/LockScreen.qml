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

    // ── Password check (one for all screens) ────────────────────────────
    QtObject {
        id: auth
        property bool busy: false
        property string error: ""
        property string _pending: ""
        signal failed()
        function submit(password) {
            if (auth.busy || !GlobalStates.screenLocked) return
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
                else { auth.error = pam.message || "PAM asked for more than a password"; pam.abort() }
            } else if (pam.messageIsError && pam.message) {
                auth.error = pam.message
            }
        }
        onCompleted: result => {
            auth.busy = false
            auth._pending = ""
            if (result === PamResult.Success) {
                auth.error = ""
                GlobalStates.screenLocked = false
                return
            }
            auth.error = result === PamResult.MaxTries ? "Too many tries: wait a moment" : (auth.error || "Wrong password")
            auth.failed()
        }
        onError: err => {
            auth.busy = false
            auth._pending = ""
            auth.error = `Password check failed: ${PamError.toString(err)}`
            auth.failed()
        }
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { auth.reset(); if (pam.active) pam.abort() }
    }

    // ── The lock ────────────────────────────────────────────────────────
    WlSessionLock {
        id: sessionLock
        locked: root.lockEnabled && GlobalStates.screenLocked
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
    Process {
        id: logindWatch
        running: root.lockEnabled && root.sessionPath !== ""
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", root.sessionPath]
        stdout: SplitParser {
            onRead: line => { if (line.includes("org.freedesktop.login1.Session.Lock (")) GlobalStates.screenLocked = true }
        }
        // gdbus exits if the bus restarts: watch again shortly.
        onExited: if (root.lockEnabled) rewatch.restart()
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
        function lock(): void { if (root.lockEnabled) GlobalStates.screenLocked = true }
        function unlock(): void { /* only a password unlocks */ }
        function preview(id: string): void { LockScreens.preview(id) }
        function status(): string {
            return JSON.stringify({ enabled: root.lockEnabled, locked: GlobalStates.screenLocked, secure: sessionLock.secure,
                screen: LockScreens.selected, using: LockScreens.current?.id ?? "default" })
        }
    }
}
