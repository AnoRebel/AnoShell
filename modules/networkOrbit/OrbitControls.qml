import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The orbit's controls: the tab switch along the bottom, and the power
 * button, which sits big in the middle while the tab's radio (or VPN) is off
 * and morphs into a small button in the corner once it is on.
 */
Item {
    id: controls
    required property var view
    anchors.fill: parent
    z: 100

    readonly property var labels: ({ eth: "Ethernet", wifi: "Wi-Fi", bt: "Bluetooth", vpn: "VPN" })

    // ── Tab switch ────────────────────────────────────────────────────────
    Rectangle {
        id: tabs
        readonly property real prog: controls.view.easeOut(controls.view.animWin(controls.view.introState, 0.25, 0.50))
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 18 }
        width: Math.min(parent.width - 40, controls.view.modes.length * 110)
        height: 42
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainerHigh
        visible: controls.view.modes.length > 0
        opacity: prog
        scale: 0.9 + 0.1 * controls.view.easeBack(controls.view.animWin(controls.view.introState, 0.25, 0.50))
        transform: Translate { y: (1 - tabs.prog) * 26 }

        readonly property real segW: width / Math.max(1, controls.view.modes.length)
        readonly property int current: Math.max(0, controls.view.modes.indexOf(controls.view.activeMode))

        Rectangle {
            id: thumb
            y: 3; height: parent.height - 6
            width: tabs.segW - 6
            x: tabs.current * tabs.segW + 3
            radius: Math.max(0, tabs.radius - 3)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.lighter(controls.view.activeColor, 1.15) }
                GradientStop { position: 1; color: controls.view.activeColor }
            }
            Behavior on x { enabled: controls.view.shown; MotionSpring { token: "snappy" } }
            Behavior on width { enabled: controls.view.shown; MotionSpring { token: "snappy" } }
        }

        Row {
            anchors.fill: parent
            Repeater {
                model: controls.view.modes
                Item {
                    id: seg
                    required property string modelData
                    required property int index
                    readonly property bool active: index === tabs.current
                    width: tabs.segW; height: tabs.height
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: controls.view.modeIcon(seg.modelData)
                            iconSize: 18
                            fill: seg.active ? 1 : 0
                            color: seg.active ? controls.view.onActiveColor : Appearance.m3colors.m3onSurface
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: controls.labels[seg.modelData] ?? seg.modelData
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: seg.active ? Font.Bold : Font.Medium
                            color: seg.active ? controls.view.onActiveColor : Appearance.m3colors.m3onSurface
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { controls.view.pendingWifiSsid = ""; controls.view.gotoMode(seg.modelData) }
                    }
                }
            }
        }
    }

    // ── Power button ──────────────────────────────────────────────────────
    Item {
        id: power
        z: 100
        readonly property real introProg: controls.view.easeOut(controls.view.animWin(controls.view.introState, 0.10, 0.35))
        opacity: introProg
        scale: controls.view.easeBack(controls.view.animWin(controls.view.introState, 0.10, 0.35))

        // 0 = big, centred (off); 1 = small, bottom-right corner (on).
        property real morph: controls.view.currentPower ? 1 : 0
        Behavior on morph {
            enabled: controls.view.powerAnimAllowed && controls.view.shown
            MotionNumber { curve: "emphasized"; baseDuration: 800 }
        }

        readonly property real bigX: parent.width / 2 - 70
        readonly property real bigY: (parent.height - controls.view.bottomBand) / 2 - 70
        width: 140 + (42 - 140) * morph
        height: width
        x: bigX + ((parent.width - 24 - 42) - bigX) * morph
        y: bigY + ((parent.height - 24 - 42) - bigY) * morph
        visible: opacity > 0.01

        Rectangle {
            anchors { fill: parent; topMargin: 2; bottomMargin: -2 }
            radius: width / 2
            color: Appearance.colors.colShadow
            z: -1
        }

        Rectangle {
            id: powerFace
            anchors.fill: parent
            radius: width / 2
            scale: pwrMa.pressed ? 0.95 : (pwrMa.containsMouse ? 1.05 : 1)
            Behavior on scale { enabled: controls.view.shown; MotionSpring { token: "snappy"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }
            color: controls.view.currentPower ? "transparent" : (pwrMa.containsMouse ? Appearance.m3colors.m3surfaceContainerHighest : Appearance.m3colors.m3surfaceContainerHigh)
            Behavior on color { enabled: controls.view.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }
            border.width: 1
            border.color: controls.view.currentPowerPending ? controls.view.activeColor
                : (controls.view.currentPower ? "transparent" : Appearance.colors.colOutlineVariant)

            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                opacity: controls.view.currentPower ? 1 : 0
                Behavior on opacity { enabled: controls.view.powerAnimAllowed && controls.view.shown; MotionNumber { curve: "emphasized"; baseDuration: 800 } }
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.lighter(controls.view.activeColor, 1.15) }
                    GradientStop { position: 1; color: controls.view.activeColor }
                }
            }

            MaterialSymbol {
                id: pwrIcon
                anchors.centerIn: parent
                iconSize: 54
                scale: 1 + (20 / 54 - 1) * power.morph
                color: controls.view.currentPower ? controls.view.onActiveColor : Appearance.colors.colSubtext
                text: controls.view.currentPowerPending ? "progress_activity"
                    : (controls.view.activeMode === "vpn" && VPN.status.state === "needs-auth" ? "key" : "power_settings_new")
                RotationAnimation on rotation {
                    from: 0; to: 360; loops: Animation.Infinite
                    duration: AnimationConfig.scaledDuration(800); easing.type: Easing.Linear
                    running: controls.view.live && controls.view.currentPowerPending
                    onRunningChanged: if (!running) pwrIcon.rotation = 0
                }
            }

            MouseArea {
                id: pwrMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: controls.view.togglePower()
            }
            StyledToolTip {
                text: controls.view.activeMode === "vpn"
                    ? (VPN.connected ? "Disconnect VPN" : (VPN.status.state === "needs-auth" ? "Sign in to the VPN" : "Connect VPN"))
                    : `Turn ${controls.labels[controls.view.activeMode] ?? ""} ${controls.view.currentPower ? "off" : "on"}`
                extraVisibleCondition: pwrMa.containsMouse
            }
        }
    }
}
