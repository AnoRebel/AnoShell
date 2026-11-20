pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "revolver.js" as R

/**
 * The corner revolver (revolver.*): rest the pointer in `corner` for `dwellMs` and a quarter of a cylinder grows out of
 * the corner, its three visible chambers holding quick actions (`actions`, up to 12 ids, three per quarter). The wheel
 * or a swipe turns it a quarter to the next three. Clicking a chamber fires it and closes the revolver, except toggles,
 * which stay open and glow while on. Lock shoots a bullet to the opposite corner first. It replaces that corner's
 * screen-corner action. Inspired by Anserin's corner revolver.
 *
 * Action ids: revolver.js CATALOG; "macro:<name>" runs one of your macros (Settings → Actions).
 */
Scope {
    id: root
    readonly property var opts: Config.options?.revolver ?? ({})
    readonly property bool enabled: root.opts.enable ?? false
    readonly property string corner: ["topLeft", "topRight", "bottomLeft", "bottomRight"].includes(root.opts.corner) ? root.opts.corner : "bottomLeft"
    readonly property int dwellMs: Math.max(0, root.opts.dwellMs ?? 90)
    readonly property var ids: Array.from(root.opts.actions ?? []).slice(0, 12)
    readonly property real radius: 230

    // How each id runs, and a toggle's state (names and icons: revolver.js CATALOG).
    readonly property var runners: ({
        lock: { run: () => Quickshell.execDetached(["loginctl", "lock-session"]) },
        wallpaperPicker: { run: () => GlobalStates.wallpaperSelectorOpen = true },
        shuffleWallpaper: { run: () => Wallpapers.shuffle() },
        nightLight: { on: () => NightLight.enabled, run: () => NightLight.toggle() },
        settings: { run: () => GlobalStates.settingsOpen = true },
        restartShell: { run: () => Quickshell.reload(true) },
        dnd: { on: () => Notifications.silent, run: () => Notifications.silent = !Notifications.silent },
        caffeine: { on: () => Idle.inhibit, run: () => Idle.toggleInhibit() },
        performance: { on: () => GameMode.performance, run: () => GameMode.toggle() },
        overview: { run: () => GlobalStates.overviewOpen = true },
        clipboard: { run: () => GlobalStates.clipboardOpen = true },
        session: { run: () => GlobalStates.sessionOpen = true },
        sidebarLeft: { run: () => GlobalStates.sidebarLeftOpen = true },
        sidebarRight: { run: () => GlobalStates.sidebarRightOpen = true }
    })
    function action(id) {
        if (String(id).startsWith("macro:")) {
            const name = String(id).slice(6)
            return { label: name, icon: Actions.find(name)?.icon ?? "bolt", run: () => Actions.run(name) }
        }
        const meta = R.info(id), how = root.runners[id]
        return meta && how ? Object.assign({}, meta, how) : null
    }

    IpcHandler {
        target: "revolver"
        function toggle(): void { root.toggleRequested() }
    }
    signal toggleRequested() // IPC: on the focused screen

    Variants {
        model: root.enabled ? Quickshell.screens : []

        Scope {
            id: perScreen
            required property var modelData
            readonly property string screenName: modelData?.name ?? ""
            property bool open: false
            property real openedAt: 0
            signal ipcOpened()
            // Each opening starts at the first three.
            onOpenChanged: { if (open) { turns = 0; openedAt = Date.now() } }
            property int turns: 0
            Connections {
                target: root
                function onToggleRequested() {
                    if (perScreen.screenName === CompositorService.focusedMonitorName || Quickshell.screens.length === 1)
                        perScreen.open = !perScreen.open
                    // Opened away from the pointer: it closes by itself unless the pointer comes to it.
                    if (perScreen.open) perScreen.ipcOpened()
                }
            }

            PanelWindow {
                id: win
                screen: perScreen.modelData
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:revolver"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                anchors {
                    top: root.corner.startsWith("top"); bottom: root.corner.startsWith("bottom")
                    left: root.corner.endsWith("Left"); right: root.corner.endsWith("Right")
                }
                implicitWidth: root.radius + 12
                implicitHeight: root.radius + 12
                readonly property bool left: root.corner.endsWith("Left")
                readonly property bool top: root.corner.startsWith("top")
                // Closed: a few pixels in the corner; open: the quarter disc.
                mask: perScreen.open || body.scale > 0.02 ? openMask : closedMask
                Region { id: closedMask; x: win.left ? 0 : win.width - 3; y: win.top ? 0 : win.height - 3; width: 3; height: 3 }
                Region {
                    id: openMask
                    shape: RegionShape.Ellipse
                    x: win.left ? -root.radius : win.width - root.radius
                    y: win.top ? -root.radius : win.height - root.radius
                    width: root.radius * 2; height: root.radius * 2
                }

                // ── Opening and closing ──
                // Handlers on the window's content see the pointer over any chamber too.
                HoverHandler {
                    // Opening swaps the input region, and compositors may then report the pointer as gone though it
                    // hasn't moved; a leave inside that moment only arms a longer fallback (no later enter or leave
                    // comes while the pointer is still).
                    onHoveredChanged: {
                        if (hovered) { closeTimer.stop(); if (!perScreen.open) dwell.restart() }
                        else {
                            dwell.stop()
                            if (!perScreen.open) return
                            closeTimer.interval = Date.now() - perScreen.openedAt < 400 ? 4000 : 320
                            closeTimer.restart()
                        }
                    }
                }
                // A notch, or a touchpad swipe's worth, turns a quarter (down: clockwise).
                WheelHandler {
                    property real acc: 0
                    property real last: 0
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        if (!perScreen.open) return
                        // angleDelta: 120 a notch; touchpads report their swipe in it too (a mouse also sends a small
                        // pixelDelta on Wayland, which isn't a notch's worth).
                        acc += event.angleDelta.y
                        if (Math.abs(acc) >= 120 && Date.now() - last > 180) {
                            perScreen.turns += acc < 0 ? 1 : -1
                            acc = 0; last = Date.now()
                        }
                    }
                }
                Timer { id: dwell; interval: root.dwellMs; onTriggered: perScreen.open = true }
                Timer { id: closeTimer; interval: 320; onTriggered: perScreen.open = false }
                Connections { target: perScreen; function onIpcOpened() { closeTimer.interval = 4000; closeTimer.restart() } }

                // ── The cylinder ──
                Item {
                    id: body
                    anchors.fill: parent
                    transformOrigin: win.top ? (win.left ? Item.TopLeft : Item.TopRight) : (win.left ? Item.BottomLeft : Item.BottomRight)
                    scale: perScreen.open ? 1 : 0
                    visible: scale > 0.01
                    Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(perScreen.open ? 520 : 240); easing.type: Easing.BezierSpline; easing.bezierCurve: perScreen.open ? Appearance.animationCurves.expressiveDefaultSpatial : Appearance.animationCurves.emphasizedAccel } }

                    // Its body: glass or the surface colour, or the connected frame's own when that is on.
                    SurfaceMaterial {
                        surface: "revolver"
                        visible: !PanelRegistry.enabled
                        x: win.left ? -root.radius : win.width - root.radius
                        y: win.top ? -root.radius : win.height - root.radius
                        width: root.radius * 2; height: root.radius * 2
                        radius: root.radius
                        color: Appearance.colors.colLayer0
                    }
                }
                ConnectedSurfaceLease {
                    key: "revolver:" + perScreen.screenName
                    kind: "panel"; edge: win.left ? "left" : "right"; priority: 6
                    screenName: perScreen.screenName
                    active: body.visible
                    // A disc centred on the screen corner (a quarter of it on screen), as the
                    // unconnected body draws it, joined to the frame by a fillet. As an ordinary
                    // edge panel the frame drew an s×s square from the edge, rounded: its centre
                    // sat s/2 in from the corner, with an edge connector bulging below it.
                    readonly property real s: root.radius * body.scale
                    detached: true
                    neckK: 16
                    x: (win.left ? 0 : (perScreen.modelData?.width ?? 0)) - s
                    y: (win.top ? 0 : (perScreen.modelData?.height ?? 0)) - s
                    w: 2 * s; h: 2 * s
                    surfaceRadius: s
                    progress: body.scale
                }

                // ── The chambers ──
                // The disc's angle: a quarter per turn, with an overshoot; on opening it swings in from a quarter back.
                property real disc: perScreen.open ? -90 * perScreen.turns : -90 * perScreen.turns + 70
                Behavior on disc { NumberAnimation { duration: AnimationConfig.scaledDuration(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveDefaultSpatial } }
                readonly property var slotIds: R.slots(root.ids, perScreen.turns)
                Repeater {
                    model: 12
                    Item {
                        id: chamber
                        required property int index
                        readonly property string actionId: win.slotIds[chamber.index] ?? ""
                        readonly property var act: root.action(chamber.actionId)
                        readonly property real deg: R.angle(chamber.index, win.disc)
                        readonly property var at: R.point(root.corner, deg, root.radius * 0.66, win.width, win.height)
                        readonly property bool isOn: chamber.act?.toggle ? !!chamber.act.on() : false
                        visible: body.visible && R.shown(chamber.deg)
                        width: 58; height: 58
                        x: chamber.at.x - width / 2; y: chamber.at.y - height / 2
                        scale: body.scale * (ma.pressed ? 0.9 : ma.containsMouse ? 1.12 : 1)
                        Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(140); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard } }

                        Rectangle {
                            anchors.fill: parent; radius: width / 2
                            color: chamber.isOn ? Appearance.colors.colPrimary
                                : ma.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                            border.width: chamber.isOn ? 0 : 1
                            border.color: Appearance.colors.colOutlineVariant
                            opacity: chamber.act ? 1 : 0.4
                        }
                        // The glow of a toggle that is on.
                        Rectangle {
                            visible: chamber.isOn
                            anchors.centerIn: parent
                            width: parent.width + 14; height: width; radius: width / 2
                            color: "transparent"
                            border.width: 4; border.color: Qt.alpha(Appearance.colors.colPrimary, 0.35)
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: !!chamber.act
                            text: chamber.act?.icon ?? ""
                            iconSize: 24
                            fill: chamber.isOn ? 1 : 0
                            color: chamber.isOn ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            enabled: !!chamber.act && perScreen.open
                            hoverEnabled: true
                            onClicked: root.fire(perScreen, win, chamber)
                        }
                        StyledToolTip {
                            text: chamber.act?.label ?? ""
                            extraVisibleCondition: ma.containsMouse
                        }
                    }
                }
            }

            // The shot: a bullet from the chamber to the opposite corner, drawn over the whole screen, then the lock.
            property point shotFrom: Qt.point(0, 0)
            property bool shooting: false
            PanelWindow {
                id: shotWin
                screen: perScreen.modelData
                visible: perScreen.shooting
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:revolverShot"
                WlrLayershell.layer: WlrLayer.Overlay
                anchors { top: true; bottom: true; left: true; right: true }
                mask: Region {}
                Rectangle {
                    id: bullet
                    width: 26; height: 8; radius: 4
                    color: Appearance.colors.colPrimary
                    property real p: 0
                    readonly property string to: R.opposite(root.corner)
                    readonly property point end: Qt.point(bullet.to.endsWith("Left") ? -40 : shotWin.width + 40, bullet.to.startsWith("top") ? -40 : shotWin.height + 40)
                    x: perScreen.shotFrom.x + (end.x - perScreen.shotFrom.x) * p - width / 2
                    y: perScreen.shotFrom.y + (end.y - perScreen.shotFrom.y) * p - height / 2
                    rotation: Math.atan2(end.y - perScreen.shotFrom.y, end.x - perScreen.shotFrom.x) * 180 / Math.PI
                    // A short trail.
                    Rectangle {
                        anchors { right: parent.left; verticalCenter: parent.verticalCenter }
                        width: 60; height: 4; radius: 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "transparent" }
                            GradientStop { position: 1; color: Qt.alpha(Appearance.colors.colPrimary, 0.7) }
                        }
                    }
                    NumberAnimation on p {
                        id: flight
                        running: false
                        from: 0; to: 1
                        duration: AnimationConfig.scaledDuration(450)
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                        onFinished: {
                            perScreen.shooting = false
                            GlobalStates.lockShotFrom = { corner: bullet.to, at: Date.now() }
                            root.runners.lock.run()
                        }
                    }
                }
            }
            function shoot(from) {
                perScreen.shotFrom = from
                perScreen.shooting = true
                bullet.p = 0
                flight.restart()
            }
        }
    }

    function fire(scope, win, chamber) {
        const act = chamber.act
        if (!act) return
        if (chamber.actionId === "lock") {
            // The chamber's centre on the screen.
            const sw = scope.modelData?.width ?? 0, sh = scope.modelData?.height ?? 0
            const x = win.left ? chamber.at.x : sw - win.width + chamber.at.x
            const y = win.top ? chamber.at.y : sh - win.height + chamber.at.y
            scope.open = false
            scope.shoot(Qt.point(x, y))
            return
        }
        act.run()
        if (!act.toggle) scope.open = false
    }
}
