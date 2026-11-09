import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

/**
 * The actions ring: your first 8 macros (services/Actions.qml) around the
 * centre of the focused screen (the pointer's position isn't known the same
 * way on every compositor). Keys: 1–8 run one, arrows/Tab move, Enter runs,
 * Esc closes. Open it with Super+Ctrl+X or `qs -c ano ipc call actions ring`.
 */
Scope {
    id: root
    readonly property bool open: GlobalStates.actionsRingOpen
    readonly property var items: Actions.ring
    property int selected: 0
    // Picked when it opens: the ring stays where it appeared.
    property var targetScreen: Quickshell.screens[0]
    onOpenChanged: if (open) {
        root.selected = 0
        root.targetScreen = Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
    }

    function close() { GlobalStates.actionsRingOpen = false }
    function press(i) {
        const m = root.items[i]
        if (!m) return
        root.close()
        Actions.run(m.name)
    }
    function edit() {
        root.close()
        GlobalStates.settingsPage = Math.max(0, SettingsRegistry.pages.findIndex(p => p.name === "Actions"))
        GlobalStates.settingsOpen = true
    }

    PanelWindow {
        id: win
        screen: root.targetScreen
        visible: root.open || ring.opacity > 0.01
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:actions"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        // Fading out: no input.
        mask: root.open ? null : noInput
        Region { id: noInput; item: null }
        Shortcut { sequence: "Escape"; autoRepeat: false; enabled: root.open; onActivated: root.close() }

        Rectangle {
            anchors.fill: parent
            color: Appearance.colors.colScrim
            opacity: root.open ? 0.45 : 0
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(220) } }
            MouseArea { anchors.fill: parent; onClicked: root.close() }
        }

        FocusScope {
            id: ring
            anchors.centerIn: parent
            width: 420; height: 420
            focus: root.open
            opacity: root.open ? 1 : 0
            Behavior on opacity { id: fade; NumberAnimation { duration: AnimationConfig.scaledDuration(fade.targetValue > 0.5 ? 220 : 160); easing.type: Easing.BezierSpline; easing.bezierCurve: fade.targetValue > 0.5 ? Appearance.animationCurves.emphasizedDecel : Appearance.animationCurves.emphasizedAccel } }

            Keys.onPressed: event => {
                const n = root.items.length
                if (event.isAutoRepeat && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) { event.accepted = true; return }
                if (n === 0) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.edit(); event.accepted = true }
                    return
                }
                if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) { root.selected = (root.selected + 1) % n; event.accepted = true }
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) { root.selected = (root.selected + n - 1) % n; event.accepted = true }
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) { root.press(root.selected); event.accepted = true }
                else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + n) { root.press(event.key - Qt.Key_1); event.accepted = true }
            }

            // The centre: the chosen macro and what it does, or how to make one.
            Rectangle {
                id: hub
                anchors.centerIn: parent
                width: 168; height: 168; radius: width / 2
                color: Appearance.colors.colLayer1
                border.width: 1; border.color: Appearance.colors.colLayer0Border
                scale: root.open ? 1 : 0.85
                Behavior on scale { id: hubScale; MotionSpring { token: hubScale.targetValue > 0.9 ? "liquid" : "settle" } }

                Column {
                    anchors.centerIn: parent
                    width: parent.width - 28
                    spacing: 4
                    visible: root.items.length > 0
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.items[root.selected]?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        readonly property var steps: Array.from(root.items[root.selected]?.steps ?? [])
                        text: steps.length === 0 ? "No steps yet" : steps.slice(0, 3).map(s => Actions.describe(s)).join(" · ") + (steps.length > 3 ? " …" : "")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: Actions.running !== ""
                        text: `Running ${Actions.running}`
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colPrimary
                    }
                }
                EmptyState {
                    anchors.centerIn: parent
                    width: parent.width - 24
                    visible: root.items.length === 0
                    icon: "bolt"
                    title: "No actions yet"
                    hint: "Write one in Settings → Actions (Enter)"
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.items.length === 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.edit()
                }
            }

            Repeater {
                model: root.items
                delegate: Item {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property bool chosen: root.selected === index
                    // On a circle from the top, flying out of the centre.
                    readonly property real angle: -Math.PI / 2 + index * 2 * Math.PI / Math.max(1, root.items.length)
                    property real reach: root.open ? 160 : 0
                    Behavior on reach { id: reachMotion; SequentialAnimation {
                        PauseAnimation { duration: reachMotion.targetValue > 0 ? AnimationConfig.scaledDuration(30 * slot.index) : 0 }
                        MotionSpring { token: reachMotion.targetValue > 0 ? "liquid" : "settle" }
                    } }
                    width: 64; height: 64
                    x: ring.width / 2 + Math.cos(angle) * reach - width / 2
                    y: ring.height / 2 + Math.sin(angle) * reach - height / 2

                    Rectangle {
                        anchors.fill: parent; radius: width / 2
                        scale: slotMA.pressed ? 0.9 : slot.chosen ? 1.1 : 1
                        Behavior on scale { MotionSpring { token: "snappy" } }
                        color: slot.chosen ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        border.width: slot.chosen ? 2 : 1
                        border.color: slot.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                        Behavior on color { CAnim {} }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: slot.modelData.icon || "bolt"
                            iconSize: 28
                            fill: slot.chosen ? 1 : 0
                            color: slot.chosen ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer2
                        }
                    }
                    // Its number key.
                    StyledText {
                        anchors { right: parent.right; top: parent.top; rightMargin: -2; topMargin: -4 }
                        text: `${slot.index + 1}`
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colSubtext
                    }
                    MouseArea {
                        id: slotMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.selected = slot.index
                        onClicked: root.press(slot.index)
                    }
                }
            }
        }

        StyledText {
            anchors { horizontalCenter: parent.horizontalCenter; top: ring.bottom; topMargin: 4 }
            opacity: ring.opacity * 0.8
            text: root.items.length ? `1–${root.items.length} or arrows · Enter runs · Esc closes` : "Enter opens Settings · Esc closes"
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer0
        }
    }
}
