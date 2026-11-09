import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * One live pin (see LivePins.qml): the crop modelData.fx/fy/fw/fh of a
 * window, refreshed `fps` times a second while it can be seen. Drag to move,
 * the corner grip to resize (aspect kept), double-click to focus the window.
 */
PanelWindow {
    id: pin

    required property var modelData
    property int fps: 10
    property bool shownAll: true
    signal closeRequested()

    // Place and size are the pin's own (not written back: pins don't persist).
    property real px: modelData.x
    property real py: modelData.y
    property real pw: modelData.w
    readonly property real ph: Math.round(pw / Math.max(0.05, modelData.aspect))
    property string layerName: modelData.layer

    readonly property bool onDesktop: layerName === "bottom"
    // Paused when hidden, on a locked screen, or behind a fullscreen window
    // (desktop pins: behind any window covering the screen).
    readonly property bool capturing: shownAll && !GlobalStates.screenLocked
        && !(onDesktop ? CompositorService.isCovered(screen?.name ?? "") : CompositorService.hasFullscreenOnScreen(screen?.name ?? ""))

    screen: modelData.screen
    visible: shownAll
    anchors { top: true; left: true }
    margins { left: Math.round(px); top: Math.round(py) }
    implicitWidth: Math.round(pw)
    implicitHeight: ph
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "quickshell:livePin"
    WlrLayershell.layer: onDesktop ? WlrLayer.Bottom : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    function _clamp() {
        const sw = pin.screen?.width ?? 1920, sh = pin.screen?.height ?? 1080
        pin.px = Math.max(0, Math.min(sw - pin.pw, pin.px))
        pin.py = Math.max(0, Math.min(sh - pin.ph, pin.py))
    }

    Timer {
        interval: Math.round(1000 / Math.max(1, pin.fps))
        running: pin.capturing
        repeat: true
        triggeredOnStart: true // live: false captures nothing until asked
        onTriggered: view.captureFrame()
    }

    Item {
        id: frame
        anchors.fill: parent
        // Passive: still hovered while the pointer is on the buttons above.
        HoverHandler { id: hover }
        layer.enabled: true
        layer.effect: OpacityMask {
            maskSource: Rectangle { width: frame.width; height: frame.height; radius: Appearance.rounding.small }
        }

        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer1 }

        // The whole window, scaled so the crop fills the pin, shifted to it.
        ScreencopyView {
            id: view
            width: pin.pw / pin.modelData.fw
            height: pin.ph / pin.modelData.fh
            x: -pin.modelData.fx * width
            y: -pin.modelData.fy * height
            captureSource: pin.modelData.toplevel ?? null
            live: false // frames come from the Timer (livePins.fps)
            paintCursor: false
        }
    }

    // Outline: the theme's glass edge, the accent while the pointer is on it.
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: Appearance.rounding.small
        border.width: hover.hovered ? 2 : (Appearance.glassTokens?.borderWidth ?? 1)
        border.color: hover.hovered ? Appearance.colors.colPrimary : Appearance.glassTokens.borderColor
        Behavior on border.color { ColorAnimation { duration: AnimationConfig.scaledDuration(120) } }
    }

    // Drag to move: the window follows, so the press point stays under the pointer.
    MouseArea {
        anchors.fill: parent
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real sx: 0
        property real sy: 0
        onPressed: mouse => { sx = mouse.x; sy = mouse.y }
        onPositionChanged: mouse => {
            if (!pressed) return
            pin.px += mouse.x - sx
            pin.py += mouse.y - sy
            pin._clamp()
        }
        onDoubleClicked: CompositorService.focusWindow(pin.modelData.toplevel)
    }

    Row {
        anchors { top: parent.top; right: parent.right; margins: 4 }
        spacing: 4
        opacity: hover.hovered ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Anim {} }
        Repeater {
            model: [
                { icon: pin.onDesktop ? "flip_to_front" : "flip_to_back", tip: pin.onDesktop ? "Above windows" : "On the desktop",
                  act: () => { pin.layerName = pin.onDesktop ? "top" : "bottom" } },
                { icon: "close", tip: "Close", act: () => pin.closeRequested() }
            ]
            delegate: Rectangle {
                id: btn
                required property var modelData
                width: 24; height: 24; radius: 12
                color: btnHover.hovered ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: btn.modelData.icon
                    iconSize: 16
                    color: btnHover.hovered ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                }
                HoverHandler { id: btnHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: btn.modelData.act() }
                StyledToolTip { text: btn.modelData.tip; extraVisibleCondition: btnHover.hovered }
            }
        }
    }

    // Resize from the bottom-right corner; the top-left stays put, so the
    // pointer's place in the window is the new size.
    Rectangle {
        anchors { right: parent.right; bottom: parent.bottom; margins: 4 }
        width: 18; height: 18; radius: 9
        color: Appearance.colors.colLayer2
        opacity: hover.hovered ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Anim {} }
        MaterialSymbol { anchors.centerIn: parent; text: "open_in_full"; iconSize: 12; color: Appearance.colors.colOnLayer2 }
        MouseArea {
            anchors.fill: parent
            anchors.margins: -4
            cursorShape: Qt.SizeFDiagCursor
            property real offset: 0
            onPressed: mouse => { offset = pin.pw - mapToItem(frame, mouse.x, mouse.y).x }
            onPositionChanged: mouse => {
                if (!pressed) return
                const maxW = (pin.screen?.width ?? 1920) - pin.px
                pin.pw = Math.max(64, Math.min(maxW, mapToItem(frame, mouse.x, mouse.y).x + offset))
            }
        }
    }
}
