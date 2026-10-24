import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import QtQuick.Shapes
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Session/Power screen: lock, logout, sleep, reboot and shutdown on a ring
 * around your avatar. Logout, reboot and shutdown need a second press: the
 * first arms the action and a ring counts down (4 s); Esc or the countdown
 * disarms. Keys: ←/→ or Tab move, Enter/Space press, Esc disarms, then closes.
 */
Scope {
    id: root

    // Tell anod (its logout/reboot/shutdown hook) first, giving the hook a
    // short head start before the session ends; immediate without anod.
    property var _pendingAction: null
    function endSession(event, action) {
        if (!Anod.available) { action(); return }
        Anod.emit(event, {})
        root._pendingAction = action
        endSessionTimer.restart()
    }
    Timer {
        id: endSessionTimer
        interval: 500
        onTriggered: { const a = root._pendingAction; root._pendingAction = null; if (a) a() }
    }

    // The actions, in ring order. confirm: needs a second press (session.confirm*).
    readonly property var actions: [
        { key: "lock", icon: "lock", label: "Lock", accent: Appearance.colors.colInfo, confirm: false },
        { key: "logout", icon: "logout", label: "Logout", accent: Appearance.colors.colWarning, confirm: Config.options?.session?.confirmLogout ?? true },
        { key: "sleep", icon: "dark_mode", label: "Sleep", accent: Appearance.colors.colTertiary, confirm: false },
        { key: "hibernate", icon: "downloading", label: "Hibernate", accent: Appearance.colors.colSecondary, confirm: true },
        { key: "reboot", icon: "restart_alt", label: "Reboot", accent: Appearance.colors.colSuccess, confirm: true },
        { key: "shutdown", icon: "power_settings_new", label: "Shutdown", accent: Appearance.colors.colError, confirm: Config.options?.session?.confirmShutdown ?? true }
    ]
    property int selected: 0
    property string armed: ""          // the action waiting for its second press
    property real armLeft: 0           // 1 → 0 over the countdown
    property real _armedAt: 0          // a confirm needs a deliberate second press
    NumberAnimation { id: armCountdown; target: root; property: "armLeft"; from: 1; to: 0; duration: 4000; onFinished: root.armed = "" }
    onArmedChanged: if (armed === "") { armCountdown.stop(); root.armLeft = 0 }
    Connections {
        target: GlobalStates
        function onSessionOpenChanged() { root.armed = ""; if (GlobalStates.sessionOpen) root.selected = 0 }
    }

    function press(i) {
        const a = root.actions[i]
        if (!a) return
        root.selected = i
        if (a.confirm && root.armed !== a.key) { root.armed = a.key; root._armedAt = Date.now(); armCountdown.restart(); return }
        // A double-click or a bounced key isn't a second press.
        if (a.confirm && Date.now() - root._armedAt < 400) return
        root.armed = ""
        root.run(a.key)
    }
    function run(key) {
        GlobalStates.sessionOpen = false
        switch (key) {
        case "lock": Quickshell.execDetached(["loginctl", "lock-session"]); break
        case "sleep": Quickshell.execDetached(["systemctl", "suspend"]); break
        case "hibernate": Quickshell.execDetached(["systemctl", "hibernate"]); break
        case "logout":
            // Compositor exit where supported, else end the login session.
            root.endSession("logging_out", () => {
                if (!CompositorService.exit())
                    Quickshell.execDetached(["loginctl", "terminate-session", Quickshell.env("XDG_SESSION_ID") || ""])
            })
            break
        case "reboot": root.endSession("rebooting", () => Quickshell.execDetached(["systemctl", "reboot"])); break
        case "shutdown": root.endSession("shutting_down", () => Quickshell.execDetached(["systemctl", "poweroff"])); break
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: sessionWindow
            required property var modelData
            screen: modelData

            // Mapped until the card's exit animation ends (closing used to unmap at once).

            visible: GlobalStates.sessionOpen || sessionCard.opacity > 0.01
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: GlobalStates.sessionOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            // Fading out: no input (a click there could still run an action).
            mask: GlobalStates.sessionOpen ? null : noInput
            Region { id: noInput; item: null }

            // Esc disarms first, then closes.
            // autoRepeat off: holding Esc must not close (or disarm then close) in one go.
            Shortcut { sequence: "Escape"; autoRepeat: false; onActivated: { if (root.armed) root.armed = ""; else GlobalStates.sessionOpen = false } }

            // Dim backdrop
            Rectangle {
                anchors.fill: parent
                color: "#000000"
                opacity: GlobalStates.sessionOpen ? 0.7 : 0
                Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(300) } }
                MouseArea { anchors.fill: parent; onClicked: GlobalStates.sessionOpen = false }
            }

            // The ring: avatar in the middle, actions around it.
            FocusScope {
                id: sessionCard
                anchors.centerIn: parent
                width: 460; height: 460
                focus: GlobalStates.sessionOpen
                opacity: GlobalStates.sessionOpen ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(GlobalStates.sessionOpen ? 250 : 180); easing.type: Easing.BezierSpline; easing.bezierCurve: (GlobalStates.sessionOpen ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel) } }

                Keys.onPressed: event => {
                    if (event.isAutoRepeat) { event.accepted = true; return } // holding a key never confirms
                    const n = root.actions.length
                    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { root.selected = (root.selected + 1) % n; event.accepted = true }
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { root.selected = (root.selected + n - 1) % n; event.accepted = true }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { root.press(root.selected); event.accepted = true }
                    // 1…n: that action, as if pressed (still twice for the ones that confirm)
                    else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + n) { root.press(event.key - Qt.Key_1); event.accepted = true }
                }

                // Avatar, name, uptime
                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    scale: GlobalStates.sessionOpen ? 1 : 0.8
                    Behavior on scale { id: scaleMotion; MotionSpring { token: scaleMotion.targetValue > 0.9 ? "liquid" : "settle" } }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 96; height: 96; radius: 48
                        color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
                        border.width: 2; border.color: Appearance?.colors.colPrimary ?? "#65558F"
                        Image {
                            id: avatarImg
                            anchors.centerIn: parent
                            width: 88; height: 88
                            source: `file://${Directories.userAvatarPath}`
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: status === Image.Ready
                            layer.enabled: visible
                            layer.effect: OpacityMask { maskSource: Rectangle { width: 88; height: 88; radius: 44 } }
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            visible: avatarImg.status !== Image.Ready
                            text: "person"; iconSize: 44
                            color: Appearance?.colors.colPrimary ?? "#65558F"
                        }
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Quickshell.env("USER") || "user"
                        font.pixelSize: Appearance?.font.pixelSize.huger ?? 24
                        font.weight: Font.Bold
                        font.capitalization: Font.Capitalize
                        color: "white"
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: `Up ${DateTime.uptime}`
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        color: "white"; opacity: 0.5
                    }
                }

                Repeater {
                    model: root.actions
                    delegate: SessionButton {
                        required property var modelData
                        required property int index
                        action: modelData
                        order: index
                        // On a circle, starting at the top; flies out from the avatar.
                        readonly property real angle: -Math.PI / 2 + index * 2 * Math.PI / root.actions.length
                        property real reach: GlobalStates.sessionOpen ? 172 : 0
                        Behavior on reach { id: reachMotion; SequentialAnimation {
                            PauseAnimation { duration: reachMotion.targetValue > 0 ? AnimationConfig.scaledDuration(35 * index) : 0 }
                            MotionSpring { token: reachMotion.targetValue > 0 ? "liquid" : "settle" }
                        } }
                        x: sessionCard.width / 2 + Math.cos(angle) * reach - width / 2
                        y: sessionCard.height / 2 + Math.sin(angle) * reach - height / 2
                        selectedHere: root.selected === index
                        armedHere: root.armed === modelData.key
                        onClicked: root.press(index)
                        onHovered: root.selected = index
                    }
                }
            }

            // Hint
            StyledText {
                anchors { horizontalCenter: parent.horizontalCenter; top: sessionCard.bottom; topMargin: 4 }
                opacity: sessionCard.opacity * 0.6
                text: root.armed !== ""
                    ? `Press ${root.actions.find(a => a.key === root.armed)?.label ?? ""} again to confirm · Esc cancels`
                    : "←/→ or 1–6 choose · Enter · Esc closes"
                font.pixelSize: Appearance?.font.pixelSize.small ?? 13
                color: "white"
            }
        }
    }

    // One action: a circle with its icon; armed, an accent ring counts down.
    component SessionButton: Item {
        id: btn
        property var action: ({})
        property int order: 0
        property bool selectedHere: false
        property bool armedHere: false
        signal clicked()
        signal hovered()
        readonly property color accent: action.accent ?? Appearance.colors.colPrimary
        width: 84; height: 96
        opacity: GlobalStates.sessionOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(200) } }

        Item {
            id: circle
            anchors.horizontalCenter: parent.horizontalCenter
            width: 68; height: 68
            scale: btnMA.pressed ? 0.9 : (btn.selectedHere || btn.armedHere ? 1.08 : 1)
            Behavior on scale { MotionSpring { token: "snappy" } }

            Rectangle {
                anchors.fill: parent; radius: width / 2
                color: Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, btn.armedHere ? 0.35 : btn.selectedHere ? 0.22 : 0.1)
                border.width: btn.selectedHere ? 2 : 1
                border.color: Qt.rgba(btn.accent.r, btn.accent.g, btn.accent.b, btn.selectedHere ? 0.9 : 0.4)
                Behavior on color { CAnim {} }
            }
            // Countdown ring (GPU path, not a repainted Canvas)
            Shape {
                anchors.fill: parent
                visible: btn.armedHere
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: btn.accent
                    strokeWidth: 4
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: circle.width / 2; centerY: circle.height / 2
                        radiusX: circle.width / 2 - 3; radiusY: circle.height / 2 - 3
                        startAngle: -90
                        sweepAngle: 360 * root.armLeft
                    }
                }
            }
            MaterialSymbol {
                anchors.centerIn: parent
                text: btn.action.icon ?? ""; iconSize: 30
                fill: btn.armedHere ? 1 : 0
                color: btn.armedHere ? btn.accent : "white"
                Behavior on color { CAnim {} }
            }
            MouseArea {
                id: btnMA
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: btn.hovered()
                onClicked: btn.clicked()
            }
        }
        StyledText {
            anchors { horizontalCenter: parent.horizontalCenter; top: circle.bottom; topMargin: 6 }
            text: btn.armedHere ? "Again" : (btn.action.label ?? "")
            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
            font.weight: Font.DemiBold
            color: btn.armedHere ? btn.accent : "white"
            Behavior on color { CAnim {} }
        }
    }

    IpcHandler {
        target: "session"
        function toggle(): void { GlobalStates.sessionOpen = !GlobalStates.sessionOpen }
        function open(): void { GlobalStates.sessionOpen = true }
        function close(): void { GlobalStates.sessionOpen = false }
    }
}
