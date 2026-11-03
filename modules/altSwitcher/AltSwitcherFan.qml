import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.modules.common
import qs.modules.common.functions
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
    Behavior on shown { id: shownMotion; MotionSpring { token: shownMotion.targetValue > 0.5 ? "liquid" : "settle" } }
    visible: open || shown > 0.01
    // On the monitor you're using (it opened on the first one).
    screen: Quickshell.screens.find(sc => sc.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
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

    // Flip between windows and workspaces: fold the deck edge-on, swap what it
    // shows, unfold. Reversible mid-way (it just plays the other way).
    property bool showingWs: false
    property real flip: 0          // 0 flat … 1 edge-on
    Connections {
        target: root.switcher
        function onWsModeChanged() { if (root.open) flipAnim.restart() }
    }
    SequentialAnimation {
        id: flipAnim
        NumberAnimation { target: root; property: "flip"; to: 1; duration: AnimationConfig.scaledDuration(150); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel }
        ScriptAction { script: root.showingWs = root.switcher.wsMode }
        NumberAnimation { target: root; property: "flip"; to: 0; duration: AnimationConfig.scaledDuration(190); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
    }


    // Set once the pointer moves over the fan after it opened.
    property bool pointerMoved: false
    property point _firstPoint: Qt.point(-1, -1)
    onOpenChanged: {
        if (open) { pointerMoved = false; _firstPoint = Qt.point(-1, -1) }
        else { flipAnim.stop(); flip = 0; showingWs = false }
    }

    // The deck slides out of the edge as it opens.
    Item {
        id: deck
        anchors.fill: parent
        opacity: Math.min(1, root.shown * 1.4)
        readonly property real slide: (1 - Math.max(0, Math.min(1, root.shown))) * root.depth * 0.6
        transform: [
            Translate {
                x: root.edge === "left" ? -deck.slide : root.edge === "right" ? deck.slide : 0
                y: root.edge === "top" ? -deck.slide : root.edge === "bottom" ? deck.slide : 0
            },
            Rotation {
                origin.x: deck.width / 2; origin.y: deck.height / 2
                axis { x: root.vertical ? 0 : 1; y: root.vertical ? 1 : 0; z: 0 }
                angle: root.flip * 90
            }
        ]

        HoverHandler {
            onPointChanged: {
                const p = point.position
                if (root._firstPoint.x < 0) { root._firstPoint = p; return }
                if (Math.abs(p.x - root._firstPoint.x) + Math.abs(p.y - root._firstPoint.y) > 6) root.pointerMoved = true
            }
        }
                WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => { (event.angleDelta.y || event.angleDelta.x) < 0 ? root.switcher.cycleNext() : root.switcher.cyclePrev() }
        }

        // The fan's body: every visible card's rounded rect plus a stem down
        // to the pill, melted into one silhouette (fan_body.frag), in the
        // frame's colour — it hugs the cards instead of boxing them.
        ShaderEffect {
            id: body
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/fan_body.frag.qsb"))
            readonly property bool connected: PanelRegistry.enabled
            readonly property color tone: Appearance.colors.colLayer0
            property real widthPx: width
            property real heightPx: height
            property real radius: Appearance.rounding.normal + 8
            property real k: 34
            property vector4d color: Qt.vector4d(tone.r, tone.g, tone.b,
                connected ? (Config.options?.appearance?.connectedCorners?.opacity ?? 1) : 0.92)
            // Card rects follow the cards as they glide (offset) and scale.
            readonly property var rects: {
                void fan.offset; void fan.count
                // Each card's rect, stretched along the arc to meet its
                // neighbours (on side edges the cards sit further apart than
                // the joins can bridge, which left separate blobs).
                const cards = fan.children.filter(c => c.isFanCard && c.visible).map(c => ({
                    cx: c.x + c.width / 2, cy: c.y + c.height / 2,
                    w: c.width * c.scale + 20, h: c.height * c.scale + 20 }))
                const al = c => root.vertical ? c.cy : c.cx
                cards.sort((a, b) => al(a) - al(b))
                const out = []
                for (let i = 0; i < cards.length; i++) {
                    const c = cards[i], half = root.vertical ? c.h / 2 : c.w / 2
                    let lo = half, hi = half
                    if (i > 0) lo = Math.max(half, (al(c) - al(cards[i - 1])) / 2 + 6)
                    if (i < cards.length - 1) hi = Math.max(half, (al(cards[i + 1]) - al(c)) / 2 + 6)
                    out.push(root.vertical
                        ? Qt.vector4d(c.cx - c.w / 2, c.cy - lo, c.w, lo + hi)
                        : Qt.vector4d(c.cx - lo, c.cy - c.h / 2, lo + hi, c.h))
                }
                // Stem: from the window's edge (where the pill is) to the arc's middle.
                const along = root.vertical ? height : width
                const sw = Math.min(fan.stemBase, along * 0.5), mid = fan.far
                const st = root.edge === "bottom" ? Qt.vector4d(width / 2 - sw / 2, height - mid, sw, mid)
                    : root.edge === "top" ? Qt.vector4d(width / 2 - sw / 2, 0, sw, mid)
                    : root.edge === "left" ? Qt.vector4d(0, height / 2 - sw / 2, mid, sw)
                    : Qt.vector4d(width - mid, height / 2 - sw / 2, mid, sw)
                out.unshift(st)
                return out.slice(0, 8)
            }
            property vector4d r0: rects[0] ?? Qt.vector4d(0, 0, 0, 0)
            property vector4d r1: rects[1] ?? Qt.vector4d(0, 0, 0, 0)
            property vector4d r2: rects[2] ?? Qt.vector4d(0, 0, 0, 0)
            property vector4d r3: rects[3] ?? Qt.vector4d(0, 0, 0, 0)
            property vector4d r4: rects[4] ?? Qt.vector4d(0, 0, 0, 0)
            property vector4d r5: rects[5] ?? Qt.vector4d(0, 0, 0, 0)
            property vector4d r6: rects[6] ?? Qt.vector4d(0, 0, 0, 0)
            property vector4d r7: rects[7] ?? Qt.vector4d(0, 0, 0, 0)
        }

        PathView {
            id: fan
            anchors.fill: parent
            model: root.showingWs ? root.switcher.workspaceList : root.switcher.filteredWindows
            interactive: false
            pathItemCount: Math.min(count, 7)
            preferredHighlightBegin: 0.5
            preferredHighlightEnd: 0.5
            highlightRangeMode: PathView.StrictlyEnforceRange
            highlightMoveDuration: AnimationConfig.scaledDuration(260)
            currentIndex: root.showingWs ? root.switcher.wsIndex : root.switcher.selectedIndex
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
            // Stem width where it meets the pill: the pill's length.
            readonly property real stemBase: {
                const r = PanelRegistry.panels.find(p => p.kind === "pill" && p.screenName === (root.screen?.name ?? ""))
                return r ? (root.vertical ? r.h : r.w) : 220
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
                readonly property bool isFanCard: true
                required property var modelData
                required property int index
                readonly property bool current: PathView.isCurrentItem
                readonly property real lift: PathView.lift ?? 0
                width: root.cardW
                height: root.cardH
                z: lift * 10 + (current ? 100 : 0)
                scale: 0.72 + 0.28 * lift * lift + (current ? 0.06 : 0)
                Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(180); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                opacity: 0.55 + 0.45 * lift

                // Workspace card (flipped): number and its windows' icons.
                Rectangle {
                    visible: root.showingWs
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    border.width: card.current ? 2 : 1
                    border.color: card.current ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    readonly property var wins: root.showingWs ? CompositorService.windows.filter(w => w.workspace === card.modelData.number) : []
                    StyledText {
                        anchors { left: parent.left; top: parent.top; margins: 10 }
                        text: card.modelData.name ?? card.modelData.number ?? ""
                        font.pixelSize: Appearance.font.pixelSize.hugeass
                        font.weight: Font.Bold
                        color: card.modelData.focused ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    }
                    Flow {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                        spacing: 6
                        Repeater {
                            model: parent.parent.wins.slice(0, 12)
                            IconImage {
                                required property var modelData
                                implicitSize: 26
                                source: FileUtils.appIcon(modelData.appId)
                            }
                        }
                    }
                    StyledText {
                        visible: parent.wins.length === 0
                        anchors.centerIn: parent
                        text: "empty"; opacity: 0.5
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }

                Rectangle {
                    id: face
                    visible: !root.showingWs
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
                        active: !root.showingWs && root.capture && root.open && !!card.modelData.toplevel
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
                        source: FileUtils.appIcon(card.modelData.appId)
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

                // Only after the pointer really moves, and not while the cards
                // glide: otherwise a resting pointer keeps re-selecting whatever
                // card slides under it (and overrides Alt+Tab's pick on open).
                HoverHandler { onHoveredChanged: if (hovered && root.pointerMoved && !fan.moving) { if (root.showingWs) root.switcher.wsIndex = card.index; else root.switcher.selectedIndex = card.index } }
                TapHandler { onTapped: { if (root.showingWs) root.switcher.wsIndex = card.index; else root.switcher.selectedIndex = card.index; root.switcher.activateSelected() } }
            }
        }
    }
}
