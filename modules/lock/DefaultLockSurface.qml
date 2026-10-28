import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * The built-in lock screen: clock, avatar, password field, Caps Lock warning,
 * and the opt-in notifications, status row and on-screen keyboard. Draws only;
 * the password goes to ctx.submit() (LockContext).
 */
Item {
    id: root
    property var ctx

    // Auto-dim after Config.options.lock.dim.idleMs of no input.
    property bool dimmed: false
    Timer {
        id: dimIdleTimer
        interval: Config.options?.lock?.dim?.idleMs ?? 30000
        running: Config.options?.lock?.dim?.enable ?? true
        repeat: false
        onTriggered: root.dimmed = true
    }
    function _wake() {
        root.dimmed = false
        dimIdleTimer.restart()
    }

    Connections {
        target: root.ctx
        function onFailed() {
            passwordInput.text = ""
            errorShake.start()
        }
    }

    // Background: the wallpaper, darkened.
    Rectangle {
        anchors.fill: parent
        color: Appearance?.m3colors.m3background ?? "#1C1B1F"
        Image {
            anchors.fill: parent
            source: root.ctx?.wallpaper ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.6) }
    }

    // Idle dim overlay — fades to a configurable opacity after dim.idleMs of
    // no input, back to 0 on any pointer/key event.
    Rectangle {
        anchors.fill: parent
        color: "black"
        z: 1
        opacity: root.dimmed ? (Config.options?.lock?.dim?.opacity ?? 0.6) : 0
        Behavior on opacity {
            NumberAnimation { duration: AnimationConfig.scaledDuration(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
        }
    }

    // Catch-all wake input; accepts nothing, so events reach the field.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        z: 2
        onPositionChanged: root._wake()
    }
    Connections {
        target: passwordInput
        function onTextChanged() { root._wake() }
        function onActiveFocusChanged() { root._wake() }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 24; width: 320
        z: 3

        // Notifications while locked (lock.notifications.enable); hides when empty.
        LockNotifications {
            Layout.fillWidth: true
        }

        // Clock
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter; spacing: 4
            StyledText {
                text: DateTime.time
                font.pixelSize: 72; font.weight: Font.Bold
                font.family: Appearance?.font.family.numbers ?? "monospace"
                color: "white"; Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                text: DateTime.collapsedCalendarFormat
                font.pixelSize: Appearance.font.pixelSize.larger; color: "white"; opacity: 0.6
                Layout.alignment: Qt.AlignHCenter
            }
        }

        // Avatar
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 80; height: 80; radius: 40
            color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
            border.width: 3; border.color: Appearance?.colors.colPrimary ?? "#65558F"
            Image {
                id: avatar
                anchors.centerIn: parent; width: 72; height: 72
                source: root.ctx?.avatar ?? ""
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
                layer.enabled: true
                layer.effect: OpacityMask { maskSource: Rectangle { width: 72; height: 72; radius: 36 } }
            }
            MaterialSymbol {
                anchors.centerIn: parent; text: "person"; iconSize: 40
                color: Appearance?.colors.colPrimary ?? "#65558F"
                visible: avatar.status !== Image.Ready
            }
        }

        StyledText {
            text: root.ctx?.user ?? ""
            font.pixelSize: Appearance.font.pixelSize.huge; font.weight: Font.DemiBold
            font.capitalization: Font.Capitalize
            color: "white"; Layout.alignment: Qt.AlignHCenter
        }

        // Status row (lock.statusRow.enable)
        LockStatusRow {
            Layout.alignment: Qt.AlignHCenter
        }

        // Password field; widens on focus (lock.passwordInput.expandOnFocus).
        Rectangle {
            id: field
            Layout.alignment: Qt.AlignHCenter
            readonly property bool expandOnFocus: Config.options?.lock?.passwordInput?.expandOnFocus ?? true
            Layout.preferredWidth: expandOnFocus ? (passwordInput.activeFocus ? 320 : 240) : 320
            implicitHeight: 48; radius: 24
            Behavior on Layout.preferredWidth {
                NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
            }
            color: Qt.rgba(1, 1, 1, 0.1)
            border.width: passwordInput.activeFocus ? 2 : 1
            border.color: (root.ctx?.error ?? "").length > 0 ? Appearance.colors.colError : (passwordInput.activeFocus ? Appearance?.colors.colPrimary ?? "#65558F" : "#33ffffff")

            // A wrong password shakes the field (its content, so the layout
            // keeps its place).
            SequentialAnimation {
                id: errorShake
                loops: 3
                NumberAnimation { target: fieldRow; property: "anchors.horizontalCenterOffset"; to: -10; duration: AnimationConfig.scaledDuration(40) }
                NumberAnimation { target: fieldRow; property: "anchors.horizontalCenterOffset"; to: 10; duration: AnimationConfig.scaledDuration(80) }
                NumberAnimation { target: fieldRow; property: "anchors.horizontalCenterOffset"; to: 0; duration: AnimationConfig.scaledDuration(40) }
            }

            RowLayout {
                id: fieldRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 32
                spacing: 8
                MaterialSymbol {
                    text: root.ctx?.busy ? "hourglass_top" : "lock"
                    iconSize: 20; color: "white"; opacity: 0.5
                }
                TextInput {
                    id: passwordInput
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    font.pixelSize: Appearance.font.pixelSize.normal; color: "white"
                    focus: true
                    verticalAlignment: TextInput.AlignVCenter
                    enabled: !(root.ctx?.busy ?? false)
                    onAccepted: root.ctx?.submit(text)
                    Text {
                        anchors.fill: parent; verticalAlignment: Text.AlignVCenter
                        text: "Password"; color: "white"; opacity: 0.3; font.pixelSize: Appearance.font.pixelSize.normal
                        visible: passwordInput.text.length === 0
                    }
                }
                MaterialSymbol {
                    text: "arrow_forward"; iconSize: 20; color: "white"
                    visible: passwordInput.text.length > 0 && !(root.ctx?.busy ?? false)
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: root.ctx?.submit(passwordInput.text)
                    }
                }
            }
        }

        StyledText {
            text: root.ctx?.error ?? ""
            visible: text.length > 0
            font.pixelSize: Appearance.font.pixelSize.smallie; color: Appearance.colors.colError
            Layout.alignment: Qt.AlignHCenter
        }

        // Caps Lock warning (LockKeys reads it when the lock starts and on
        // each Caps Lock press)
        StyledText {
            text: "Caps Lock is on"
            visible: (root.ctx?.capsLock ?? false) && !(root.ctx?.busy ?? false)
            font.pixelSize: Appearance.font.pixelSize.smallie; color: Appearance.colors.colWarning
            Layout.alignment: Qt.AlignHCenter
        }

        StyledText {
            text: "Checking…"
            visible: root.ctx?.busy ?? false
            font.pixelSize: Appearance.font.pixelSize.smallie; color: "white"; opacity: 0.5
            Layout.alignment: Qt.AlignHCenter
        }

        // On-screen keyboard (lock.osk.enable)
        LockOSK {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 12
            onKey: (text) => { passwordInput.text = passwordInput.text + text; root._wake() }
            onBackspace: { passwordInput.text = passwordInput.text.slice(0, -1); root._wake() }
            onSubmit: root.ctx?.submit(passwordInput.text)
        }
    }
}
