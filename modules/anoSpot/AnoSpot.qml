import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.mediaControls
import qs.modules.controlPanel
import qs.modules.calendar
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

    // Surfaces the pill can grow into, hosting the same content component the
    // standalone panel uses (one implementation, one state).
    readonly property var growTargets: ["mediaControls", "controlPanel", "calendar"]
    function growsInto(target) {
        return growTargets.includes(target) && (Config.options?.anoSpot?.growInto?.[target] ?? false)
    }

    function _dispatchClick(button, win) {
        let target = "";
        if (button === Qt.LeftButton)        target = root.actions.leftClick   ?? "mediaControls";
        else if (button === Qt.RightButton)  target = root.actions.rightClick  ?? "controlPanel";
        else if (button === Qt.MiddleButton) target = root.actions.middleClick ?? "anoview";
        if (target.length === 0) return
        if (win && root.growsInto(target)) { win.grownTarget = win.grownTarget === target ? "" : target; return }
        Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", target, "toggle"]);
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
            implicitWidth: root.isVertical ? 3 : spotWindow._w
            implicitHeight: root.isVertical ? spotWindow._h : 3
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

            // ── Grow-into: the pill becomes the target surface ──────────────
            property string grownTarget: ""
            readonly property bool grown: grownTarget !== ""
            readonly property real _maxH: (modelData?.height ?? 1080) * 0.75
            readonly property real grownW: ({ mediaControls: 440, controlPanel: 380, calendar: 400 })[grownTarget] ?? 400
            readonly property real grownH: Math.min(_maxH, (grownLoader.item?.implicitHeight ?? 200) + 32)
            // Springs between resting and grown geometry.
            // Transient (volume, notification, …): on the focused screen only.
            readonly property bool transientShown: !grown && PillTransient.active
                && (CompositorService.focusedMonitorName === "" || CompositorService.focusedMonitorName === (modelData?.name ?? ""))
            readonly property real transientLen: Math.max(root.heightPx * 4, (transientView.implicitWidth ?? 0) + 28)
            property real _w: grown ? grownW : root.isVertical ? root.heightPx : (transientShown ? transientLen : length)
            property real _h: grown ? grownH : root.isVertical ? (transientShown ? Math.max(length, 120) : length) : root.heightPx
            // Only while growing/shrinking: resting length already springs.
            property bool _growing: false
            onGrownChanged: { if (grown) _big = true; _growing = true; growSettle.restart() }
            onTransientShownChanged: { _growing = true; growSettle.restart() }
            Timer { id: growSettle; interval: 1400; onTriggered: { spotWindow._growing = false; if (!spotWindow.grown) spotWindow._big = false } }
            Behavior on _w { enabled: spotWindow._animated && spotWindow._growing; MotionSpring { token: "liquid" } }
            Behavior on _h { enabled: spotWindow._animated && spotWindow._growing; MotionSpring { token: "liquid" } }
            readonly property real cornerRadius: grown ? Appearance.rounding.windowRounding : Math.min(_w, _h) / 2

            // ── Envelope ────────────────────────────────────────────────────
            // The window keeps a fixed size while the pill animates inside it
            // (pillBody): resizing a Wayland surface every frame is a configure
            // round trip per frame, which made every pill animation stutter.
            // It only changes when a grow starts (to the grow size) and after
            // a shrink has settled (back to the resting size).
            property bool _big: false
            readonly property real _maxAlong: Math.max(root.widthPx, 460)
            readonly property real _envW: !root.isVertical ? _maxAlong : (_big ? _maxAlong : root.heightPx)
            readonly property real _envH: !root.isVertical ? (_big ? _maxH : root.heightPx) : (_big ? _maxH : _maxAlong)
            WlrLayershell.keyboardFocus: grown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            Shortcut { sequence: "Escape"; enabled: spotWindow.grown; onActivated: spotWindow.grownTarget = "" }

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
            implicitWidth: Math.round(_envW)
            implicitHeight: Math.round(_envH)

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
            readonly property real _depth: (root.isVertical ? _w : _h) + gap
            readonly property real _shift: Math.max(0, tuck) * _depth
            // The whole content slides; the window itself stays put.
            Binding {
                target: spotWindow.contentItem
                property: root.isVertical ? "x" : "y"
                value: (root.position === "top" || root.position === "left") ? -spotWindow._shift : spotWindow._shift
            }
            // Fully tucked: click-through (only the peek strip takes input).
            mask: Region { item: spotWindow.tuck > 0.99 ? null : pillBody }

            ConnectedSurfaceLease {
                key: "pill:" + (spotWindow.modelData?.name ?? "")
                kind: "pill"; edge: root.position; priority: 15
                screenName: spotWindow.modelData?.name ?? ""
                active: spotWindow.visible && spotWindow._revealed && spotWindow.connected && spotWindow.tuck < 0.99
                progress: 1 - Math.max(0, Math.min(1, spotWindow.tuck))
                surfaceRadius: spotWindow.cornerRadius
                // Where the layer shell actually puts the window (centred in
                // the space other edges leave, e.g. beside a left bar).
                readonly property point _o: PanelRegistry.windowOrigin(spotWindow)
                readonly property real _s: (root.position === "top" || root.position === "left") ? -spotWindow._shift : spotWindow._shift
                x: _o.x + pillBody.x + (root.isVertical ? _s : 0); y: _o.y + pillBody.y + (root.isVertical ? 0 : _s)
                w: pillBody.width; h: pillBody.height
            }

            // Animated gradient ring rendered behind the pill. When the
            // border-pulse opacity is zero this is invisible and free.
            // When it ramps up, the slightly-oversized conical-gradient
            // rectangle peeks out from behind the pill as a colored halo
            // whose hue rotates over the pulse cycle.
            Item {
                id: borderHalo
                anchors.fill: pillBody
                opacity: 0
                visible: opacity > 0
                z: -1

                property real angle: 0

                Rectangle {
                    anchors.fill: parent
                    radius: spotWindow.cornerRadius
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

            // The visible pill: animates inside the fixed window, pinned to its
            // edge and centred along it.
            Rectangle {
                id: pillBody
                width: Math.round(spotWindow._w)
                height: Math.round(spotWindow._h)
                x: root.position === "right" ? parent.width - width : root.position === "left" ? 0 : Math.round((parent.width - width) / 2)
                y: root.position === "bottom" ? parent.height - height : root.position === "top" ? 0 : Math.round((parent.height - height) / 2)
                radius: spotWindow.cornerRadius
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
                    onClicked: mouse => root._dispatchClick(mouse.button, spotWindow)
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
                            radius: spotWindow.cornerRadius
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
                    opacity: spotWindow.grown || spotWindow.transientShown ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(140) } }
                    anchors.fill: parent
                    anchors.margins: 6
                    // Reserve space for the drag handle on the leading edge
                    anchors.leftMargin: !root.isVertical && root.draggable ? 18 : 6
                    anchors.topMargin: root.isVertical && root.draggable ? 18 : 6
                    vertical: root.isVertical
                    thickness: root.heightPx
                    faces: root.faces
                    // Clicks on the faces: a tap, distinct from the swipe drag
                    // (the drag handler here would otherwise swallow a left
                    // click before the pill's click area below sees it).
                    TapHandler {
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onTapped: (point, button) => root._dispatchClick(button, spotWindow)
                    }
                }

                // Grown: the target surface's own content component.
                Loader {
                    id: grownLoader
                    active: spotWindow.grown
                    anchors.fill: parent
                    anchors.margins: 16
                    opacity: spotWindow.grown && spotWindow._w >= spotWindow.grownW * 0.85 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(160) } }
                    sourceComponent: ({ mediaControls: grownMedia, controlPanel: grownControl, calendar: grownCalendar })[spotWindow.grownTarget] ?? null
                }
                // Transient: icon + level bar (volume/brightness/mic) or label.
                RowLayout {
                    id: transientView
                    visible: opacity > 0.01
                    opacity: spotWindow.transientShown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(140) } }
                    anchors.centerIn: parent
                    spacing: 10
                    readonly property bool level: ["volume", "brightness", "mic"].includes(PillTransient.kind)
                    MaterialSymbol {
                        iconSize: 18; fill: 1
                        color: PillTransient.kind === "recording" && !PillTransient.muted ? Appearance.colors.colError : Appearance.colors.colPrimary
                        text: ({
                            volume: PillTransient.muted ? "volume_off" : PillTransient.value < 0.35 ? "volume_down" : "volume_up",
                            brightness: "light_mode",
                            mic: PillTransient.muted ? "mic_off" : "mic",
                            keyboard: "keyboard",
                            notification: "notifications",
                            charging: PillTransient.muted ? "battery_5_bar" : "battery_charging_full",
                            recording: PillTransient.muted ? "stop_circle" : "fiber_manual_record"
                        })[PillTransient.kind] ?? "info"
                    }
                    Rectangle {
                        visible: transientView.level
                        implicitWidth: 120; implicitHeight: 6; radius: 3
                        color: Appearance.colors.colLayer2
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, PillTransient.value)); height: parent.height; radius: 3
                            color: PillTransient.muted ? Appearance.colors.colOutline : Appearance.colors.colPrimary
                            Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(120); easing.type: Easing.OutCubic } }
                        }
                    }
                    StyledText {
                        visible: transientView.level
                        text: Math.round(PillTransient.value * 100)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.family: Appearance.font.family.numbers
                        Layout.preferredWidth: 26
                        horizontalAlignment: Text.AlignRight
                    }
                    StyledText {
                        visible: !transientView.level
                        text: PillTransient.kind === "charging" ? `${PillTransient.label} · ${Math.round(PillTransient.value * 100)}%` : PillTransient.label
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                        Layout.maximumWidth: 280
                    }
                }

                Component { id: grownMedia; MediaControlsContent { } }
                Component { id: grownControl; ControlPanelContent { onCloseRequested: spotWindow.grownTarget = "" } }
                Component { id: grownCalendar; CalendarContent { } }
            }
        }
      }
    }
}
