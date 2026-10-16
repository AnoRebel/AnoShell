import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Fan window switcher (altSwitcher.style: fan; design D12b): window cards on an
 * arc grown from the pill's edge, the selected one lifted at the centre.
 * Live thumbnails only while open, and only where the compositor can capture
 * windows (Hyprland); otherwise each card shows the app icon and title.
 * Its window is sized to the arc, not the screen.
 */
PanelWindow {
    id: root

    required property var switcher          // AltSwitcher scope: windows, selection, actions
    readonly property bool open: switcher.panelVisible && switcher.style === "fan"
    readonly property string edge: BarStyle.pillEdge
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property bool capture: CompositorService.supports.windowCapture ?? false

    // Arc size: along the edge, and how far it reaches into the screen.
    readonly property real along: Math.min((vertical ? screen?.height : screen?.width) ?? 1200, 1100) * 0.92
    readonly property real depth: 330
    readonly property real cardW: vertical ? 190 : 240
    readonly property real cardH: vertical ? 130 : 150

    // Mapped from the moment it opens until the close animation ends.
    property real shown: open ? 1 : 0
    Behavior on shown { MotionSpring { token: root.open ? "liquid" : "settle" } }
    visible: open || shown > 0.01
    color: "transparent"
    exclusionMode: ExclusionMode.Normal   // past the bar/pill on that edge
    WlrLayershell.namespace: "quickshell:altSwitcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors {
        top: edge === "top"; bottom: edge === "bottom"
        left: edge === "left"; right: edge === "right"
    }
    implicitWidth: vertical ? depth : along
    implicitHeight: vertical ? along : depth

    Item {
        anchors.fill: parent
        focus: root.open
        Keys.onPressed: event => {
            const s = root.switcher
            if (event.key === Qt.Key_Escape) { s.hide(); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { s.activateSelected(); event.accepted = true }
            else if (event.key === Qt.Key_Tab) { (event.modifiers & Qt.ShiftModifier) ? s.cyclePrev() : s.cycleNext(); event.accepted = true }
            else if ([Qt.Key_Right, Qt.Key_Down].includes(event.key)) { s.cycleNext(); event.accepted = true }
            else if ([Qt.Key_Left, Qt.Key_Up].includes(event.key)) { s.cyclePrev(); event.accepted = true }
        }
        // Opened with Alt+Tab: letting go of Alt picks the selected window.
        Keys.onReleased: event => {
            if (event.key === Qt.Key_Alt && root.switcher.viaAlt) { root.switcher.activateSelected(); event.accepted = true }
        }
    }

    // The deck slides out of the edge as it opens.
    Item {
        id: deck
        anchors.fill: parent
        opacity: Math.min(1, root.shown * 1.4)
        readonly property real slide: (1 - Math.max(0, Math.min(1, root.shown))) * root.depth * 0.6
        transform: Translate {
            x: root.edge === "left" ? -deck.slide : root.edge === "right" ? deck.slide : 0
            y: root.edge === "top" ? -deck.slide : root.edge === "bottom" ? deck.slide : 0
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => { (event.angleDelta.y || event.angleDelta.x) < 0 ? root.switcher.cycleNext() : root.switcher.cyclePrev() }
        }

        PathView {
            id: fan
            anchors.fill: parent
            model: root.switcher.filteredWindows
            interactive: false
            pathItemCount: Math.min(count, 7)
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: AnimationConfig.scaledDuration(260)
            currentIndex: root.switcher.selectedIndex
            // An arc bulging away from the edge: ends near the edge, middle out.
            readonly property real m: 40      // edge margin
            // How far a card centre may go from the edge and stay inside.
            readonly property real reach: root.depth - (root.vertical ? root.cardW : root.cardH) / 2 - 24 - fan.m
            // One hump: the ends near the edge, the middle (selected card)
            // furthest out, with a smooth top.
            readonly property real near: fan.m + root.cardH / 2
            readonly property real far: fan.m + fan.reach
            function px(t, d) {   // t along the edge 0..1, d distance from the edge
                const a = t * (root.vertical ? fan.height : fan.width)
                const o = root.edge === "bottom" || root.edge === "right" ? (root.vertical ? fan.width : fan.height) - d : d
                return root.vertical ? Qt.point(o, a) : Qt.point(a, o)
            }
            readonly property real e0: (root.vertical ? root.cardH : root.cardW) * 0.6 / (root.vertical ? fan.height : fan.width)
            path: Path {
                startX: fan.px(fan.e0, fan.near).x; startY: fan.px(fan.e0, fan.near).y
                PathAttribute { name: "lift"; value: 0 }
                PathCubic {
                    x: fan.px(0.5, fan.far).x; y: fan.px(0.5, fan.far).y
                    control1X: fan.px(fan.e0 + 0.1, fan.far).x; control1Y: fan.px(fan.e0 + 0.1, fan.far).y
                    control2X: fan.px(0.32, fan.far).x; control2Y: fan.px(0.32, fan.far).y
                }
                PathAttribute { name: "lift"; value: 1 }
                PathCubic {
                    x: fan.px(1 - fan.e0, fan.near).x; y: fan.px(1 - fan.e0, fan.near).y
                    control1X: fan.px(0.68, fan.far).x; control1Y: fan.px(0.68, fan.far).y
                    control2X: fan.px(0.9 - fan.e0, fan.far).x; control2Y: fan.px(0.9 - fan.e0, fan.far).y
                }
                PathAttribute { name: "lift"; value: 0 }
            }

            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool current: PathView.isCurrentItem
                readonly property real lift: PathView.lift ?? 0
                width: root.cardW
                height: root.cardH
                z: lift * 10 + (current ? 100 : 0)
                scale: 0.72 + 0.28 * lift * lift + (current ? 0.06 : 0)
                Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(180); easing.type: Easing.OutCubic } }
                opacity: 0.55 + 0.45 * lift

                Rectangle {
                    id: face
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: card.current ? 2 : 1
                    border.color: card.current ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    clip: true

                    // Live thumbnail, only while open and only for the cards on
                    // the arc (PathView instantiates just those).
                    Loader {
                        id: thumb
                        anchors { fill: parent; margins: 4; bottomMargin: 30 }
                        active: root.capture && root.open && !!card.modelData.toplevel
                        sourceComponent: ScreencopyView {
                            captureSource: card.modelData.toplevel
                            live: true
                            paintCursor: false
                        }
                    }
                    // Icon fallback (no capture, e.g. niri) and app badge.
                    IconImage {
                        anchors.centerIn: thumb.active ? undefined : parent
                        anchors.verticalCenterOffset: thumb.active ? 0 : -10
                        x: thumb.active ? 8 : 0
                        y: thumb.active ? parent.height - 26 : 0
                        implicitSize: thumb.active ? 20 : 48
                        source: { void DesktopEntries.applications.values.length; return `image://icon/${DesktopEntries.heuristicLookup(card.modelData.appId)?.icon || card.modelData.appId}` }
                    }
                    StyledText {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: thumb.active ? 34 : 10; rightMargin: 10; bottomMargin: 7 }
                        horizontalAlignment: thumb.active ? Text.AlignLeft : Text.AlignHCenter
                        elide: Text.ElideRight
                        text: card.modelData.title || card.modelData.appId
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: card.current ? Font.DemiBold : Font.Normal
                    }
                }

                HoverHandler { onHoveredChanged: if (hovered) root.switcher.selectedIndex = card.index }
                TapHandler { onTapped: { root.switcher.selectedIndex = card.index; root.switcher.activateSelected() } }
            }
        }
    }
}
