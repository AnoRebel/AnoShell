import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * AnoSpot — dynamic-island-style overlay aggregating Mpris, Notifications,
 * Recording, and Clock/Weather. Compositor-agnostic: never reads compositor-specific services
 * directly; all compositor state flows through CompositorService.
 *
 * Toggle:    Config.options.anoSpot.enable
 * Position:  Config.options.anoSpot.position ∈ {top, bottom, left, right}
 *            (invalid values fall back to "top")
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.anoSpot?.enable ?? false
    readonly property string rawPosition: Config.options?.anoSpot?.position ?? "top"
    readonly property string configPosition: ["top", "bottom", "left", "right"].indexOf(rawPosition) >= 0
                                        ? rawPosition : "top"
    // The edge the pill is drawn on. An edge change tucks the pill into the
    // old edge, switches, then grows it out of the new one (state machine:
    // resting → leaving → arriving → resting).
    property string position: configPosition
    property bool edgeLeaving: false
    onConfigPositionChanged: {
        if (configPosition === position) return
        if (!AnimationConfig.transitions) { position = configPosition; return }
        edgeLeaving = true
        edgeSwap.restart()
    }
    Timer {
        id: edgeSwap
        interval: AnimationConfig.scaledDuration(260)
        onTriggered: { root.position = root.configPosition; root.edgeLeaving = false }
    }

    // Resting faces in cycle order: status, then media/spectrum (while a player
    // exists) and lyrics (lyrics service on), each toggle-able.
    readonly property var faceCfg: Config.options?.anoSpot?.faces ?? ({})
    readonly property bool hasPlayer: AnoSpotState.mpris !== null
    readonly property var faces: {
        const f = ["status"]
        if ((faceCfg.media ?? true) && hasPlayer) f.push("media")
        if ((faceCfg.spectrum ?? false) && hasPlayer) f.push("spectrum")
        if ((faceCfg.lyrics ?? false) && hasPlayer && (Config.options?.lyrics?.enable ?? false)) f.push("lyrics")
        return f
    }
    readonly property int widthPx: Config.options?.anoSpot?.widthPx ?? 420
    readonly property int heightPx: Config.options?.anoSpot?.heightPx ?? 36
    readonly property bool isVertical: position === "left" || position === "right"

    readonly property bool showMpris: Config.options?.anoSpot?.showMpris ?? true
    readonly property bool showNotification: Config.options?.anoSpot?.showNotification ?? true
    readonly property bool showRecording: Config.options?.anoSpot?.showRecording ?? true
    readonly property bool showClockWeather: Config.options?.anoSpot?.showClockWeather ?? true
    readonly property bool showBattery: Config.options?.anoSpot?.showBattery ?? true
    readonly property bool showWorkspace: Config.options?.anoSpot?.showWorkspace ?? true

    readonly property var actions: Config.options?.anoSpot?.actions ?? ({})
    readonly property bool draggable: Config.options?.anoSpot?.draggable ?? true
    readonly property bool acceptDrops: Config.options?.anoSpot?.acceptDrops ?? true

    function _dispatchClick(button) {
        let target = "";
        if (button === Qt.LeftButton)        target = root.actions.leftClick   ?? "mediaControls";
        else if (button === Qt.RightButton)  target = root.actions.rightClick  ?? "controlPanel";
        else if (button === Qt.MiddleButton) target = root.actions.middleClick ?? "anoview";
        if (target.length > 0) {
            Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", target, "toggle"]);
        }
    }

    // ─── Event border ────────────────────────────────────────────────────
    // Animated gradient halo behind the pill that pulses on configured
    // events. The current renderer (per-screen child below) uses a
    // ConicalGradient sweep as a placeholder; a Siri-style flowing-color
    // shader is planned to replace it later. The borderPulse signal is the
    // stable interface — swap the visual without touching this section.
    readonly property var eventBorderCfg: Config.options?.anoSpot?.eventBorder ?? ({})
    readonly property bool eventBorderEnabled: eventBorderCfg.enable ?? true
    readonly property int eventBorderHoldMs: eventBorderCfg.holdMs ?? 1500
    readonly property var eventBorderEvents: eventBorderCfg.events ?? ["notification", "track", "recording", "workspace"]

    signal borderPulse()

    // Startup fires workspace/track/notification signals as services settle;
    // they are not events, so the halo stays off until this arms.
    property bool _armed: false
    Timer { running: true; interval: 2000; onTriggered: root._armed = true }

    function triggerBorder(eventType) {
        if (!eventBorderEnabled || !_armed) return;
        if (eventBorderEvents.indexOf(eventType) < 0) return;
        root.borderPulse();
    }

    Connections {
        target: Notifications
        function onNotify(_) { root.triggerBorder("notification") }
    }
    Connections {
        target: MprisController
        function onActiveTrackChanged() { root.triggerBorder("track") }
    }
    Connections {
        target: RecorderStatus
        function onIsRecordingChanged() { root.triggerBorder("recording") }
    }
    Connections {
        target: CompositorService
        function onActiveWorkspaceIndexChanged() { root.triggerBorder("workspace") }
    }

    Variants {
        model: root.enabled ? Quickshell.screens : []

      Scope {
        id: spotScope
        required property var modelData

        // Edge strip that brings a tucked pill back on hover (fullscreen only).
        PanelWindow {
            screen: spotScope.modelData
            visible: spotWindow.screenFullscreen
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:anospot:peek"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: root.position === "top"
                bottom: root.position === "bottom"
                left: root.position === "left"
                right: root.position === "right"
            }
            implicitWidth: root.isVertical ? 3 : spotWindow.width
            implicitHeight: root.isVertical ? spotWindow.height : 3
            MouseArea {
                id: peekArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
                onExited: spotWindow.peek()
            }
        }

        AnoSpotEdgePicker {
            id: edgePicker
            screen: spotScope.modelData
            open: spotWindow.picking
            current: root.position
            onChose: edge => { spotWindow.picking = false; if (edge !== root.position) Config.setNestedValue("anoSpot.position", edge) }
            onCancelled: spotWindow.picking = false
        }

        PanelWindow {
            id: spotWindow
            readonly property var modelData: spotScope.modelData
            screen: modelData

            visible: root.enabled && GlobalStates.shellSettled
            color: "transparent"
            property bool picking: false

            // The pill fits its content (a fixed length clipped it), springing
            // between sizes; anoSpot.widthPx is the maximum length.
            readonly property real _lead: root.draggable ? 18 : 6
            readonly property real _contentLen: faceView.preferredLength + _lead + 6
            property real length: Math.max(root.heightPx * 2, Math.min(_contentLen, root.widthPx))
            // First appearance: the window maps transparent (a hidden window
            // doesn't lay out, so its size would be stale) and fades in once
            // the pill's width has held for 600 ms (clock, weather, media
            // arriving). Late content in the first 2 s snaps; the spring runs
            // after that.
            property bool _revealed: false
            property real _fade: _revealed ? 1 : 0
            Behavior on _fade { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }
            Binding { target: spotWindow.contentItem; property: "opacity"; value: spotWindow._fade }
            property bool _animated: false
            Timer { id: revealTimer; interval: 600; running: GlobalStates.shellSettled && !spotWindow._revealed; onTriggered: spotWindow._revealed = true }
            Timer { running: spotWindow._revealed && !spotWindow._animated; interval: 2000; onTriggered: spotWindow._animated = true }
            onLengthChanged: if (!spotWindow._revealed && revealTimer.running) revealTimer.restart()
            Behavior on length { enabled: spotWindow._animated; MotionSpring { token: "snappy" } }
            implicitWidth: root.isVertical ? root.heightPx : length
            implicitHeight: root.isVertical ? length : root.heightPx

            // Normal: placed past the bar on the same edge instead of over it.
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:anospot"
            WlrLayershell.layer: WlrLayer.Overlay

            // One anchor: the layer shell centres the pill along its edge at
            // its own size (anchoring both ends stretched it edge to edge).
            anchors {
                top: root.position === "top"
                bottom: root.position === "bottom"
                left: root.position === "left"
                right: root.position === "right"
            }

            // Connected mode: flush on its edge, painted by the frame.
            // The frame retracts in fullscreen, so the pill paints itself then.
            readonly property bool connected: PanelRegistry.enabled && !(Config.options?.anoSpot?.floating ?? false) && !screenFullscreen
            readonly property int gap: connected ? 0 : 6
            margins {
                top: root.position === "top" ? gap : 0
                bottom: root.position === "bottom" ? gap : 0
                left: root.position === "left" ? gap : 0
                right: root.position === "right" ? gap : 0
            }

            // ── Fullscreen: slide into the edge, peek on edge hover ───────────
            // Like the bar: hidden while a window is fullscreen on this screen,
            // revealed by hovering the edge strip (peekStrip) and kept while the
            // pointer is on the pill or for a short grace period after.
            readonly property bool screenFullscreen: {
                void CompositorService.fullscreenRevision
                return (Config.options?.anoSpot?.hideOnFullscreen ?? true)
                    && CompositorService.hasFullscreenOnScreen(modelData?.name ?? "")
            }
            // Shown while hovered, and for a grace period after the pointer
            // touches the edge strip or leaves the pill.
            readonly property bool tucked: root.edgeLeaving
                || (screenFullscreen && !pillHover.hovered && !peekArea.containsMouse && !peekGrace.running)
            function peek() { peekGrace.restart() }
            Timer { id: peekGrace; interval: 1000 }
            HoverHandler {
                id: pillHover
                onHoveredChanged: if (!hovered) peekGrace.restart()
            }
            // 0 = shown, 1 = fully inside the edge.
            property real tuck: tucked ? 1 : 0
            Behavior on tuck { MotionSpring { token: spotWindow.tucked ? "settle" : "liquid" } }
            readonly property real _depth: (root.isVertical ? width : height) + gap
            readonly property real _shift: Math.max(0, tuck) * _depth
            // The whole content slides; the window itself stays put.
            Binding {
                target: spotWindow.contentItem
                property: root.isVertical ? "x" : "y"
                value: (root.position === "top" || root.position === "left") ? -spotWindow._shift : spotWindow._shift
            }
            // Fully tucked: click-through (only the peek strip takes input).
            mask: Region { item: spotWindow.tuck > 0.99 ? null : spotWindow.contentItem }

            ConnectedSurfaceLease {
                key: "pill:" + (spotWindow.modelData?.name ?? "")
                kind: "pill"; edge: root.position; priority: 15
                screenName: spotWindow.modelData?.name ?? ""
                active: spotWindow.visible && spotWindow._revealed && spotWindow.connected && spotWindow.tuck < 0.99
                progress: 1 - Math.max(0, Math.min(1, spotWindow.tuck))
                surfaceRadius: Math.min(spotWindow.width, spotWindow.height) / 2
                // Where the layer shell actually puts the window (centred in
                // the space other edges leave, e.g. beside a left bar).
                readonly property point _o: PanelRegistry.windowOrigin(spotWindow)
                readonly property real _s: (root.position === "top" || root.position === "left") ? -spotWindow._shift : spotWindow._shift
                x: _o.x + (root.isVertical ? _s : 0); y: _o.y + (root.isVertical ? 0 : _s)
                w: spotWindow.width; h: spotWindow.height
            }

            // Animated gradient ring rendered behind the pill. When the
            // border-pulse opacity is zero this is invisible and free.
            // When it ramps up, the slightly-oversized conical-gradient
            // rectangle peeks out from behind the pill as a colored halo
            // whose hue rotates over the pulse cycle.
            Item {
                id: borderHalo
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                opacity: 0
                visible: opacity > 0
                z: -1

                property real angle: 0

                Rectangle {
                    anchors.fill: parent
                    radius: Math.min(width, height) / 2
                    layer.enabled: true
                    layer.effect: ConicalGradient {
                        angle: borderHalo.angle
                        gradient: Gradient {
                            GradientStop { position: 0.00; color: Appearance?.colors?.colPrimary    ?? "#a6e3a1" }
                            GradientStop { position: 0.33; color: Appearance?.colors?.colSecondary  ?? "#cba6f7" }
                            GradientStop { position: 0.66; color: Appearance?.colors?.colTertiary   ?? "#94e2d5" }
                            GradientStop { position: 1.00; color: Appearance?.colors?.colPrimary    ?? "#a6e3a1" }
                        }
                    }
                    // A ring, not a fill: the gradient takes this item's alpha, and a
                    // filled source washed the whole pill pale (its body is
                    // transparent in connected mode).
                    color: "transparent"
                    border.width: 2
                    border.color: "white"
                }

                Connections {
                    target: root
                    function onBorderPulse() { borderAnim.restart() }
                }

                SequentialAnimation {
                    id: borderAnim
                    ParallelAnimation {
                        NumberAnimation { target: borderHalo; property: "opacity"; to: 1; duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                        RotationAnimation { target: borderHalo; property: "angle"; from: 0; to: 360
                                            duration: AnimationConfig.scaledDuration(200) + root.eventBorderHoldMs + 400; easing.type: Easing.Linear }
                    }
                    PauseAnimation { duration: root.eventBorderHoldMs }
                    NumberAnimation { target: borderHalo; property: "opacity"; to: 0; duration: AnimationConfig.scaledDuration(400); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel }
                }
            }

            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                radius: Math.min(width, height) / 2
                color: spotWindow.connected ? "transparent" : (Appearance?.colors?.colLayer0 ?? "#1e1e2e")
                // Glass-token-driven border + opacity so static themes
                // (aurora, angel, etc.) can dial the pill's translucency.
                // Material You and "neutral" static themes leave the
                // tokens at sensible defaults and look unchanged.
                border.width: spotWindow.connected ? 0 : (Appearance?.glassTokens?.borderWidth ?? 1)
                border.color: Appearance?.glassTokens?.borderColor
                            ?? Appearance?.colors?.colOutlineVariant
                            ?? "#444"
                opacity: Appearance?.glassTokens?.opacity ?? 0.96

                // Click dispatcher — catches left/right/middle on the pill background.
                // Widget MouseAreas (e.g. AnoSpotMpris wheel handler) sit above this
                // and intercept their own events; unclaimed clicks fall through here.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: mouse => root._dispatchClick(mouse.button)
                }

                // Drop target — files/URIs dragged from any Wayland source
                // get copied into the AnoSpotStash and the popout opens.
                Loader {
                    anchors.fill: parent
                    active: root.acceptDrops
                    sourceComponent: dropAreaComp
                }
                Component {
                    id: dropAreaComp
                    DropArea {
                        keys: ["text/uri-list"]
                        property bool dropHover: false

                        onEntered: drag => {
                            if (drag.hasUrls) {
                                dropHover = true;
                                drag.accept();
                            }
                        }
                        onExited: dropHover = false
                        onDropped: drop => {
                            if (drop.hasUrls) {
                                AnoSpotStash.addUrls(drop.urls);
                                GlobalStates.anoSpotStashOpen = true;
                                drop.accept();
                            }
                            dropHover = false;
                        }

                        // Drop hover indicator: tinted overlay on the pill.
                        Rectangle {
                            anchors.fill: parent
                            radius: Math.min(width, height) / 2
                            color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
                            opacity: parent.dropHover ? 0.18 : 0
                            border.width: parent.dropHover ? 2 : 0
                            border.color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
                            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(120) } }
                        }
                    }
                }

                // Drag handle — leading edge of the pill. Press, drag the
                // pointer toward any screen edge, release to snap. The pill
                // itself is layer-shell-anchored so it doesn't free-float;
                // we just compute the pointer's release-point edge and
                // rewrite Config.options.anoSpot.position.
                Rectangle {
                    id: dragHandle
                    visible: root.draggable
                    width: root.isVertical ? parent.width : 14
                    height: root.isVertical ? 14 : parent.height
                    color: "transparent"
                    anchors {
                        top: root.isVertical ? parent.top : undefined
                        left: root.isVertical ? undefined : parent.left
                        horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
                        verticalCenter: root.isVertical ? undefined : parent.verticalCenter
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "drag_indicator"
                        iconSize: 12
                        opacity: handleArea.containsMouse || handleArea.drag.active ? 0.85 : 0.5
                        rotation: root.isVertical ? 90 : 0
                        color: Appearance?.colors?.colOnLayer0Subtle ?? "#a6adc8"
                        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(120) } }
                    }

                    MouseArea {
                        id: handleArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.SizeAllCursor
                        acceptedButtons: Qt.LeftButton
                        // Press the grip: the edge picker opens over the screen
                        // (the pill's own window can't follow a drag across it);
                        // release over an edge to move there, or click one.
                        onPressed: spotWindow.picking = true
                        // Released, or the grab cancelled when the overlay mapped
                        // over the pointer: the overlay may already know the
                        // edge under the pointer; otherwise its first pointer
                        // report decides.
                        onPressedChanged: {
                            if (pressed || !spotWindow.picking) return
                            const h = edgePicker.hovered
                            if (h && h !== root.position) edgePicker.chose(h)
                            else edgePicker.dropPending = true
                        }
                    }
                }

                // Resting faces (status, media, spectrum, lyrics): swipe or
                // shift-wheel to switch; the capsule morphs to the face.
                AnoSpotFaces {
                    id: faceView
                    anchors.fill: parent
                    anchors.margins: 6
                    // Reserve space for the drag handle on the leading edge
                    anchors.leftMargin: !root.isVertical && root.draggable ? 18 : 6
                    anchors.topMargin: root.isVertical && root.draggable ? 18 : 6
                    vertical: root.isVertical
                    thickness: root.heightPx
                    faces: root.faces
                }
            }
        }
      }
    }
}
