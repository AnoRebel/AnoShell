import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets
import "."

/**
 * A single window thumbnail in AnoView. Shows a screencopy capture
 * with title badge, hover highlight, click-to-activate, middle-click-to-close.
 */
Item {
    id: thumbContainer

    property var hWin: null
    property var wHandle: null
    property string winKey: ''
    property real thumbW: -1
    property real thumbH: -1
    property var clientInfo: ({})
    property bool hovered: false
    property real targetX: -1000
    property real targetY: -1000
    property real targetZ: 0
    property real targetRotation: 0
    property bool moveCursorToActiveWindow: false
    property int order: 0 // staggers the first capture and the entrance

    // Parent AnoView injects these
    property bool animateWindows: false
    property var lastPositions: ({})
    signal activated()
    signal closed()

    width: thumbW; height: thumbH
    x: 0; y: 0; z: targetZ; rotation: 0
    visible: !!wHandle

    NumberAnimation { id: animX; target: thumbContainer; property: "x"; duration: animateWindows ? AnimationConfig.scaledDuration(300) : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
    NumberAnimation { id: animY; target: thumbContainer; property: "y"; duration: animateWindows ? AnimationConfig.scaledDuration(300) : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
    NumberAnimation { id: animRotation; target: thumbContainer; property: "rotation"; duration: AnimationConfig.scaledDuration(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial }

    function updateLastPos() {
        var lp = lastPositions || ({})
        var prev = lp[winKey] || ({})
        prev.x = x; prev.y = y; lp[winKey] = prev
    }

    onTargetXChanged: {
        if (!animateWindows) { x = targetX; updateLastPos(); return }
        var prev = (lastPositions || ({}))[winKey]
        var startX = (prev?.x !== undefined) ? prev.x : targetX
        if (startX === targetX) { x = targetX; updateLastPos(); return }
        animX.stop(); animX.from = startX; animX.to = targetX; animX.start()
    }
    onTargetYChanged: {
        if (!animateWindows) { y = targetY; updateLastPos(); return }
        var prev = (lastPositions || ({}))[winKey]
        var startY = (prev?.y !== undefined) ? prev.y : targetY
        if (startY === targetY) { y = targetY; updateLastPos(); return }
        animY.stop(); animY.from = startY; animY.to = targetY; animY.start()
    }
    onTargetRotationChanged: { animRotation.stop(); animRotation.from = 0; animRotation.to = targetRotation; animRotation.start() }
    onXChanged: updateLastPos()
    onYChanged: updateLastPos()

    Component.onCompleted: {
        rotation = targetRotation
        if (!animateWindows) { x = targetX; y = targetY; updateLastPos() }
    }

    function refreshThumb() {
        if (thumbLoader.item) thumbLoader.item.captureFrame()
    }
    // First capture, staggered so a dozen don't land in one frame.
    Timer { running: thumbLoader.status === Loader.Ready; interval: 30 + Math.min(thumbContainer.order, 12) * 25; onTriggered: thumbContainer.refreshThumb() }
    // Entrance: once its first frame is in (or after a moment without one).
    readonly property bool shown: (thumbLoader.item?.hasContent ?? false) || entranceFallback.fired
    Timer { id: entranceFallback; property bool fired: false; running: true; interval: 600; onTriggered: fired = true }

    Item {
        id: card
        anchors.fill: parent
        scale: !thumbContainer.shown ? 0.85 : thumbContainer.hovered ? 1.05 : 0.95
        opacity: thumbContainer.shown ? 1 : 0
        transformOrigin: Item.Center
        Behavior on scale { MotionSpring { token: "snappy" } }
        Behavior on opacity { Anim {} }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onEntered: thumbContainer.hovered = true
            onExited: thumbContainer.hovered = false
            onClicked: event => {
                if (event.button === Qt.LeftButton) thumbContainer.activated()
                if (event.button === Qt.MiddleButton) thumbContainer.closed()
            }
        }

        Rectangle {
            anchors.fill: parent; anchors.margins: -8
            radius: 24; color: "#55000000"; z: -1
        }

        Loader {
            id: thumbLoader
            anchors.fill: parent
            active: !!thumbContainer.wHandle
            sourceComponent: ScreencopyView {
                id: thumb
                anchors.fill: parent
                captureSource: thumbContainer.wHandle
                live: false
                paintCursor: false
                visible: thumbContainer.wHandle && hasContent

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: thumb.width; height: thumb.height; radius: 16 }
                }
                Rectangle {
                    anchors.fill: parent
                    color: thumbContainer.hovered ? "transparent" : "#33000000"
                    border.width: thumbContainer.hovered ? 3 : 1
                    border.color: thumbContainer.hovered ? (Appearance?.colors.colPrimary ?? "#0088cc") : "#cc444444"
                    radius: 16
                }
            }
        }

        Rectangle {
            z: 100
            width: Math.min(titleText.implicitWidth + 24, thumbContainer.thumbW * 0.75)
            height: titleText.implicitHeight + 12
            x: (card.width - width) / 2
            y: card.height - height - (card.height * 0.08)
            radius: 12; color: thumbContainer.hovered ? "#FF000000" : "#CC000000"
            border.width: 1; border.color: Appearance.colors.colOutlineVariant
            StyledText {
                id: titleText
                anchors.centerIn: parent; width: parent.width - 16
                text: hWin?.title ?? ""; color: "white"
                textFormat: Text.PlainText // window titles are arbitrary text
                font.pixelSize: thumbContainer.hovered ? 13 : 12
                elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
