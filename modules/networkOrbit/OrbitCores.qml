import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The orbit's cores: one glowing disc per connected device (up to 5; with
 * several Bluetooth devices they orbit each other). The primary core also
 * shows scanning, "disconnected" and the Wi-Fi password prompt. Press and hold
 * a connected core to disconnect: it fills from the bottom, then flashes.
 */
Item {
    id: orbitContainer
    required property var view
    property alias repeater: coreRepeater
    anchors.fill: parent
    anchors.bottomMargin: view.bottomBand
    z: 1

    component Dots: Row {
        id: dots
        property color dotCol: Appearance.colors.colOnLayer0
        property bool running: false
        spacing: 4
        Repeater {
            model: 3
            Rectangle {
                required property int index
                width: 5; height: 5; radius: 2.5; color: dots.dotCol
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    running: dots.running && dots.visible && AnimationConfig.continuous
                    PauseAnimation { duration: AnimationConfig.scaledDuration(index * 100) }
                    NumberAnimation { from: 0; to: -5; duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standardDecel }
                    NumberAnimation { from: -5; to: 0; duration: AnimationConfig.scaledDuration(250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standardAccel }
                    PauseAnimation { duration: AnimationConfig.scaledDuration((2 - index) * 100) }
                }
            }
        }
    }

    // A core's icon, name and status line.
    component CoreText: ColumnLayout {
        id: ct
        required property var core
        property bool hovered: false
        property color tint: Appearance.m3colors.m3onBackground
        spacing: 3
        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            iconSize: 40 - 12 * ct.core.multiShift
            fill: 1
            color: ct.tint
            text: ct.core.coreIcon
            visible: text !== ""
        }
        Dots { Layout.alignment: Qt.AlignHCenter; visible: ct.core.isMyDisconnecting; running: ct.core.view.live; dotCol: ct.tint }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 130 - 40 * ct.core.multiShift
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: ct.core.multiShift > 0.5 ? Appearance.font.pixelSize.smaller : Appearance.font.pixelSize.small
            font.weight: Font.Black
            color: ct.tint
            text: ct.core.myDevice?.name ?? ""
            elide: Text.ElideRight
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.Bold
            color: ct.tint
            opacity: ct.hovered || ct.core.isMyDisconnecting ? 1 : 0.6
            text: ct.core.coreStatus
        }
    }

    Repeater {
        id: coreRepeater
        model: 5

        delegate: Item {
            id: coreContainer
            required property int index
            readonly property var view: orbitContainer.view

            readonly property var myDevice: view.currentCores[index]
            readonly property bool isPrimary: index === 0
            readonly property bool hasDevice: myDevice !== null
            readonly property bool isReallyActive: view.currentPower && (hasDevice || (isPrimary && view.activeCoreCount === 0))

            property real activeTransition: isReallyActive ? 1 : 0
            Behavior on activeTransition {
                enabled: coreContainer.view.shown && coreContainer.view.introState >= 0.3
                MotionNumber { curve: "emphasizedDecel"; baseDuration: 1400 }
            }
            readonly property real coreIntroStart: 0.10 + view.coreVisualIndices[index] * 0.04
            readonly property real coreIntroProg: view.easeBack(view.animWin(view.introState, coreIntroStart, coreIntroStart + 0.22))
            readonly property real multiShift: view.activeMode === "bt" ? view.multiTransitionState : 0

            width: view.currentPower ? (170 - 25 * multiShift - 12 * Math.max(0, view.smoothedActiveCoreCount - 2)) : 140
            height: width
            Behavior on width { enabled: coreContainer.view.shown; MotionSpring { token: "liquid" } }

            readonly property real myBaseAngle: (view.coreVisualIndices[index] / Math.max(1, view.activeCoreCount)) * Math.PI * 2
            property real animatedBaseAngle: myBaseAngle
            Behavior on animatedBaseAngle { enabled: coreContainer.view.shown; MotionSpring { token: "liquid"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }
            readonly property real coreOrbitAngle: view.globalOrbitAngle * 1.5 + animatedBaseAngle
            readonly property real myOrbitRadiusX: 150 + (view.activeCoreCount > 2 ? 15 : 0)
            readonly property real myOrbitRadiusY: 90 + (view.activeCoreCount > 2 ? 12 : 0)

            x: (orbitContainer.width - width) / 2 + Math.cos(coreOrbitAngle) * myOrbitRadiusX * multiShift * activeTransition
            y: (orbitContainer.height - height) / 2 + Math.sin(coreOrbitAngle) * myOrbitRadiusY * multiShift * activeTransition
            opacity: activeTransition * view.easeOut(view.animWin(view.introState, coreIntroStart, coreIntroStart + 0.22))
            scale: centralCore.bumpScale * (0.8 + 0.2 * activeTransition) * coreIntroProg
            visible: opacity > 0.01

            readonly property string myId: myDevice ? myDevice.id : ""
            readonly property bool isMyDisconnecting: myId !== "" && (!!view.disconnectingIds[myId] || view.isDisconnecting(myId))

            readonly property bool showPassword: isPrimary && view.pendingWifiSsid !== "" && view.activeMode === "wifi"
            readonly property bool showScanning: isPrimary && view.currentPower && !view.currentConn && !showPassword && view.activeMode !== "eth"
            readonly property bool showConnected: view.currentConn && hasDevice && !showPassword
            readonly property bool lit: view.currentConn || showPassword
            readonly property string coreIcon: isMyDisconnecting ? "" : (coreMa.containsMouse ? view.modeOffIcon(view.activeMode) : (myDevice?.icon || view.modeIcon(view.activeMode)))
            readonly property string coreStatus: isMyDisconnecting ? "Disconnecting…" : (centralCore.disconnectFill > 0.01 ? "Hold to disconnect" : "Connected")

            MultiEffect {
                source: centralCore
                anchors.fill: centralCore
                shadowEnabled: coreContainer.view.currentPower
                shadowColor: Appearance.m3colors.m3shadow
                shadowOpacity: coreContainer.view.currentPower ? 0.5 : 0
                shadowBlur: 1.2
                shadowVerticalOffset: 5
                z: -1
            }

            Rectangle {
                id: centralCore
                anchors.fill: parent
                radius: width / 2

                property real disconnectFill: 0
                property bool disconnectTriggered: false
                property real flashOpacity: 0
                property real bumpScale: 1
                readonly property bool isDangerState: coreMa.containsMouse || disconnectFill > 0 || coreContainer.isMyDisconnecting
                readonly property bool danger: isDangerState && coreContainer.view.currentConn && !coreContainer.showPassword
                readonly property color errorTint: Qt.rgba(Appearance.colors.colError.r, Appearance.colors.colError.g, Appearance.colors.colError.b, 0.75)

                SequentialAnimation on bumpScale {
                    id: coreBumpAnim
                    running: false
                    NumberAnimation { to: 1.15; duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial }
                    NumberAnimation { to: 1; duration: AnimationConfig.scaledDuration(600); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                }

                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop {
                        position: 0
                        color: {
                            const v = coreContainer.view
                            if (!v.currentPower) return Appearance.m3colors.m3surfaceContainerLow
                            if (coreContainer.isMyDisconnecting) return Appearance.m3colors.m3surfaceContainerHigh
                            if (centralCore.danger) return Qt.tint(Qt.lighter(v.activeColor, 1.15), centralCore.errorTint)
                            return coreContainer.lit ? Qt.lighter(v.activeColor, 1.15) : Appearance.m3colors.m3surfaceContainerHigh
                        }
                        Behavior on color { enabled: coreContainer.view.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(300) } }
                    }
                    GradientStop {
                        position: 1
                        color: {
                            const v = coreContainer.view
                            if (!v.currentPower) return Appearance.m3colors.m3surfaceContainerLowest
                            if (coreContainer.isMyDisconnecting) return Appearance.m3colors.m3surfaceContainer
                            if (centralCore.danger) return Qt.tint(v.activeColor, centralCore.errorTint)
                            return coreContainer.lit ? v.activeColor : Appearance.m3colors.m3surfaceContainer
                        }
                        Behavior on color { enabled: coreContainer.view.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(300) } }
                    }
                }
                border.width: 2
                border.color: {
                    const v = coreContainer.view
                    if (!v.currentPower) return Appearance.m3colors.m3surfaceContainerLowest
                    if (coreContainer.isMyDisconnecting) return Appearance.m3colors.m3surfaceContainerHigh
                    if (centralCore.danger) return Qt.tint(Qt.lighter(v.activeColor, 1.1), Qt.rgba(Appearance.colors.colError.r, Appearance.colors.colError.g, Appearance.colors.colError.b, 0.45))
                    return coreContainer.lit ? Qt.lighter(v.activeColor, 1.1) : Appearance.m3colors.m3surfaceContainerHighest
                }
                Behavior on border.color { enabled: coreContainer.view.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(300) } }

                // Disconnect flash.
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Appearance.m3colors.m3onBackground
                    opacity: centralCore.flashOpacity
                    NumberAnimation { id: coreFlashAnim; target: centralCore; property: "flashOpacity"; from: 0.6; to: 0; duration: AnimationConfig.scaledDuration(500); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                }

                // Hold-to-disconnect fill, rising from the bottom (a circle
                // clipped by a growing strip).
                Item {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.height * centralCore.disconnectFill
                    clip: true
                    visible: centralCore.disconnectFill > 0
                    Rectangle {
                        width: centralCore.width; height: centralCore.height
                        y: parent.height - height
                        radius: width / 2
                        gradient: Gradient {
                            GradientStop { position: 0; color: Appearance.m3colors.m3surfaceVariant }
                            GradientStop { position: 1; color: Appearance.m3colors.m3surfaceContainerLowest }
                        }
                    }
                }

                // Soft halo + breathing pulse while connected.
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 30; height: width; radius: width / 2
                    color: centralCore.danger ? Appearance.colors.colError : coreContainer.view.activeColor
                    opacity: coreContainer.lit && !coreContainer.isMyDisconnecting ? (centralCore.danger ? 0.45 : 0.15) : 0
                    z: -1
                    Behavior on color { enabled: coreContainer.view.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }
                    Behavior on opacity { enabled: coreContainer.view.shown; MotionNumber { curve: "expressiveEffects"; baseDuration: 300 } }
                    SequentialAnimation on scale {
                        loops: Animation.Infinite
                        running: coreContainer.view.live && coreContainer.lit && AnimationConfig.continuous
                        NumberAnimation { to: 1.1; duration: AnimationConfig.scaledDuration(2000); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
                        NumberAnimation { to: 1; duration: AnimationConfig.scaledDuration(2000); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 12; height: width; radius: width / 2
                    color: "transparent"
                    border.color: centralCore.isDangerState && !coreContainer.showPassword ? Appearance.colors.colError : coreContainer.view.activeColor
                    border.width: 2
                    z: -2
                    readonly property bool pulseOn: coreContainer.lit && coreContainer.view.showInfoView && coreContainer.view.currentPower && !coreContainer.isMyDisconnecting
                    property real pulseOp: 0.3
                    opacity: pulseOn ? pulseOp : 0
                    SequentialAnimation on pulseOp {
                        loops: Animation.Infinite
                        running: coreContainer.view.live && parent.pulseOn && AnimationConfig.continuous
                        NumberAnimation { to: 0.45; duration: AnimationConfig.scaledDuration(1250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
                        NumberAnimation { to: 0.15; duration: AnimationConfig.scaledDuration(1250); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
                    }
                }

                // Scanning: ripples + the tab's glyph.
                Item {
                    anchors.fill: parent
                    opacity: coreContainer.showScanning ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { enabled: coreContainer.view.shown; MotionNumber { curve: "expressiveEffects"; baseDuration: 400 } }
                    Repeater {
                        model: 3
                        Rectangle {
                            required property int index
                            anchors.centerIn: parent
                            width: parent.width * 0.4; height: width; radius: width / 2
                            color: "transparent"
                            border.color: coreContainer.view.activeColor; border.width: 2
                            opacity: 0
                            readonly property bool run: coreContainer.view.live && coreContainer.showScanning && AnimationConfig.continuous
                            SequentialAnimation on scale {
                                running: parent.run; loops: Animation.Infinite
                                PauseAnimation { duration: AnimationConfig.scaledDuration(index * 400) }
                                NumberAnimation { from: 1; to: 2.5; duration: AnimationConfig.scaledDuration(2000); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standardDecel }
                            }
                            SequentialAnimation on opacity {
                                running: parent.run; loops: Animation.Infinite
                                PauseAnimation { duration: AnimationConfig.scaledDuration(index * 400) }
                                NumberAnimation { from: 0.8; to: 0; duration: AnimationConfig.scaledDuration(2000); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standardDecel }
                            }
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        iconSize: 40 - 12 * coreContainer.multiShift
                        color: coreContainer.view.activeColor
                        text: coreContainer.view.modeIcon(coreContainer.view.activeMode)
                        SequentialAnimation on opacity {
                            running: coreContainer.view.live && coreContainer.showScanning && AnimationConfig.continuous; loops: Animation.Infinite
                            NumberAnimation { to: 0.5; duration: AnimationConfig.scaledDuration(1000); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
                            NumberAnimation { to: 1; duration: AnimationConfig.scaledDuration(1000); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
                        }
                    }
                }

                // Wi-Fi password prompt.
                Item {
                    id: pwdLayer
                    anchors.fill: parent
                    opacity: coreContainer.showPassword ? 1 : 0
                    visible: opacity > 0.01
                    scale: coreContainer.showPassword ? 1 : 0.8
                    Behavior on scale { enabled: coreContainer.view.shown; MotionSpring { token: "snappy"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }
                    Behavior on opacity { enabled: coreContainer.view.shown; MotionNumber { curve: "expressiveEffects"; baseDuration: 300 } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol { Layout.alignment: Qt.AlignHCenter; iconSize: 28; color: coreContainer.view.onActiveColor; text: "lock" }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: pwdLayer.width - 30
                            font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Bold
                            color: coreContainer.view.onActiveColor
                            text: coreContainer.view.pendingWifiSsid
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: pwdLayer.width - 30; Layout.preferredHeight: 32
                            radius: Appearance.rounding.small
                            color: Appearance.m3colors.m3surfaceContainerHigh
                            border.color: pwdField.activeFocus ? coreContainer.view.onActiveColor : "transparent"
                            border.width: 1
                            TextInput {
                                id: pwdField
                                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: Appearance.font.family.main
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.m3colors.m3onSurface
                                echoMode: TextInput.Password
                                clip: true
                                onAccepted: { const pw = text; text = ""; coreContainer.view.submitPassword(pw) }
                                Keys.onEscapePressed: { text = ""; coreContainer.view.pendingWifiSsid = "" }
                            }
                        }
                    }
                    Timer { id: deferFocus; interval: 50; onTriggered: pwdField.forceActiveFocus() }
                    onVisibleChanged: if (visible) { pwdField.text = ""; deferFocus.start() }
                }

                // Connected: icon, name, status (and the same text in the
                // fill's colours, revealed by the rising fill).
                Item {
                    anchors.fill: parent
                    opacity: coreContainer.showConnected ? 1 : 0
                    visible: opacity > 0.01
                    scale: coreContainer.showConnected ? 1 : 0.95
                    Behavior on scale { enabled: coreContainer.view.shown; MotionSpring { token: "snappy"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }
                    Behavior on opacity { enabled: coreContainer.view.shown; MotionNumber { curve: "expressiveEffects"; baseDuration: 300 } }

                    CoreText {
                        anchors.centerIn: parent
                        core: coreContainer; hovered: coreMa.containsMouse
                        tint: coreContainer.isMyDisconnecting ? Appearance.colors.colOutline : coreContainer.view.onActiveColor
                    }
                    Item {
                        id: fillClip
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: parent.height * centralCore.disconnectFill
                        clip: true
                        visible: centralCore.disconnectFill > 0
                        CoreText {
                            core: coreContainer; hovered: coreMa.containsMouse
                            x: (fillClip.width - width) / 2
                            y: (centralCore.height - height) / 2 - (centralCore.height - fillClip.height)
                            tint: Appearance.m3colors.m3onBackground
                        }
                    }
                }

                MouseArea {
                    id: coreMa
                    anchors.fill: parent
                    hoverEnabled: true
                    readonly property bool canHold: coreContainer.view.currentConn && coreContainer.hasDevice && !coreContainer.isMyDisconnecting && !coreContainer.showPassword
                    cursorShape: canHold ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onContainsMouseChanged: {
                        if (!coreContainer.view.currentConn || coreContainer.showPassword) return
                        coreContainer.view.disconnectHoverCount = Math.max(0, coreContainer.view.disconnectHoverCount + (containsMouse ? 1 : -1))
                    }
                    onPressed: if (canHold && !centralCore.disconnectTriggered) { coreDrainAnim.stop(); coreFillAnim.start() }
                    onReleased: if (!centralCore.disconnectTriggered) { coreFillAnim.stop(); coreDrainAnim.start() }
                }

                NumberAnimation {
                    id: coreFillAnim
                    target: centralCore; property: "disconnectFill"; to: 1
                    duration: AnimationConfig.scaledDuration(800 * (1 - centralCore.disconnectFill))
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
                    onFinished: {
                        if (!coreMa.pressed) { centralCore.disconnectFill = 0; return }
                        centralCore.disconnectTriggered = true
                        coreFlashAnim.restart()
                        coreBumpAnim.restart()
                        coreContainer.view.disconnectCore(coreContainer.myId)
                        centralCore.disconnectFill = 0
                        centralCore.disconnectTriggered = false
                    }
                }
                NumberAnimation {
                    id: coreDrainAnim
                    target: centralCore; property: "disconnectFill"; to: 0
                    duration: AnimationConfig.scaledDuration(1500 * centralCore.disconnectFill)
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standardDecel
                }
            }
        }
    }
}
