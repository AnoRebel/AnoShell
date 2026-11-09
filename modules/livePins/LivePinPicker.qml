import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services

/**
 * The live-pin picker (LivePins.qml): choose a window from live thumbnails,
 * then drag a rectangle over its preview. The pin opens where the rectangle
 * was drawn, at the window's own size. Esc goes back a step, then cancels.
 */
PanelWindow {
    id: root

    signal picked(var pin)
    signal cancelled()

    property var win: null // the chosen CompositorService window

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Appearance.colors.colScrim
    WlrLayershell.namespace: "quickshell:livePinPicker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Shortcut { sequence: "Escape"; autoRepeat: false; onActivated: { if (root.win) root.win = null; else root.cancelled() } }

    // A click on the backdrop (outside the strip / preview) cancels.
    MouseArea { anchors.fill: parent; onClicked: root.cancelled() }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 16

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: hint.implicitWidth + 28
            implicitHeight: hint.implicitHeight + 14
            radius: height / 2
            color: Appearance.colors.colLayer0
            StyledText {
                id: hint
                anchors.centerIn: parent
                text: root.win ? "Drag over the part to pin · Esc goes back" : "Pick a window to pin a part of · Esc cancels"
                color: Appearance.colors.colOnLayer0
            }
        }

        // Step 1: the windows (WindowStrip holds its own window lease).
        Rectangle {
            visible: !root.win
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: strip.implicitWidth + 32
            implicitHeight: strip.implicitHeight + 32
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer0
            border.width: Appearance.glassTokens?.borderWidth ?? 1
            border.color: Appearance.glassTokens.borderColor
            MouseArea { anchors.fill: parent } // keeps backdrop clicks off the card
            WindowStrip {
                id: strip
                anchors.centerIn: parent
                active: !root.win
                focusOnTap: false
                maxWidth: root.width * 0.8
                windows: CompositorService.windows.filter(w => !!w.toplevel)
                onActivated: w => root.win = w
            }
        }

        // Step 2: the chosen window, live, fitted to the screen.
        Item {
            id: stage
            visible: !!root.win
            Layout.alignment: Qt.AlignHCenter
            readonly property real srcW: view.sourceSize.width || root.win?.width || 1
            readonly property real srcH: view.sourceSize.height || root.win?.height || 1
            readonly property real fit: Math.min(1, root.width * 0.85 / srcW, root.height * 0.75 / srcH)
            implicitWidth: Math.round(srcW * fit)
            implicitHeight: Math.round(srcH * fit)

            ScreencopyView {
                id: view
                anchors.fill: parent
                captureSource: root.win?.toplevel ?? null
                live: !!root.win
                paintCursor: false
            }
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: Appearance.glassTokens?.borderWidth ?? 1
                border.color: Appearance.glassTokens.borderColor
            }

            // The selection.
            Rectangle {
                id: sel
                visible: selector.pressed && width > 2 && height > 2
                color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.8)
                border.width: 2
                border.color: Appearance.colors.colPrimary
            }

            MouseArea {
                id: selector
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                property real ox: 0
                property real oy: 0
                function _span(a, b, max) { const lo = Math.max(0, Math.min(a, b)); return [lo, Math.min(max, Math.max(a, b)) - lo] }
                onPressed: mouse => { ox = mouse.x; oy = mouse.y; sel.x = ox; sel.y = oy; sel.width = 0; sel.height = 0 }
                onPositionChanged: mouse => {
                    const h = _span(ox, mouse.x, width), v = _span(oy, mouse.y, height)
                    sel.x = h[0]; sel.width = h[1]; sel.y = v[0]; sel.height = v[1]
                }
                onReleased: {
                    if (sel.width < 12 || sel.height < 12) return // a click, not a drag
                    const at = stage.mapToItem(null, sel.x, sel.y)
                    const sw = root.screen?.width ?? root.width, sh = root.screen?.height ?? root.height
                    // The pin opens at the window's own pixel size, within 60% of the screen.
                    const w = Math.min(sel.width * (root.win.width || stage.srcW) / width, sw * 0.6, (sel.width / sel.height) * sh * 0.6)
                    root.picked({
                        toplevel: root.win.toplevel, title: root.win.title || root.win.appId || "window",
                        fx: sel.x / width, fy: sel.y / height, fw: sel.width / width, fh: sel.height / height,
                        aspect: sel.width / sel.height, screen: root.screen,
                        x: Math.max(0, Math.min(sw - w, at.x)), y: Math.max(0, Math.min(sh - w * sel.height / sel.width, at.y)), w: w
                    })
                }
            }
        }
    }
}
