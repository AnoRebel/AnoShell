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
import qs.modules.scratchpad
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

    // Pill-bar style (bar.style pill, Ano family): the pill is the bar.
    readonly property bool barMode: BarStyle.pillBar
    readonly property bool enabled: (Config.options?.anoSpot?.enable ?? false) || barMode
    readonly property string rawPosition: BarStyle.pillEdge
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
    readonly property int widthPx: barMode ? Math.max(Config.options?.anoSpot?.widthPx ?? 420, 820) : (Config.options?.anoSpot?.widthPx ?? 420)
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
        // The scratchpad always grows out of the pill (Scratchpad.open drives it).
        if (target === "scratchpad") { Scratchpad.open = !Scratchpad.open; return }
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

        // Edge strip that brings a tucked pill back on hover (fullscreen, or
        // auto-hide: then past whatever reserves the edge, where the pill sits).
        PanelWindow {
            screen: spotScope.modelData
            visible: spotWindow.screenFullscreen || spotWindow.autoHide
            color: "transparent"
            exclusionMode: spotWindow.screenFullscreen || spotWindow._hostBar ? ExclusionMode.Ignore : ExclusionMode.Normal
            WlrLayershell.namespace: "quickshell:anospot:peek"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: root.position === "top"
                bottom: root.position === "bottom"
                left: root.position === "left"
                right: root.position === "right"
            }
            // The pill's resting length, not its springing size: this surface
            // would otherwise resize every frame while the pill morphs.
            implicitWidth: root.isVertical ? 3 : spotWindow.length
            implicitHeight: root.isVertical ? spotWindow.length : 3
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
            onChose: edge => { spotWindow.picking = false; if (edge !== root.position) BarStyle.moveEdge("pill", edge) }
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
            readonly property real grownW: ({ mediaControls: 440, controlPanel: 380, calendar: 400,
                scratchpad: Math.min(760, (modelData?.width ?? 1280) - 32) })[grownTarget] ?? 400
            // The scratchpad (Scratchpad.open) grows out of the pill on the
            // focused screen, and closing it here closes the service's state.
            readonly property bool _scratchHere: CompositorService.focusedMonitorName
                ? CompositorService.focusedMonitorName === (modelData?.name ?? "") : modelData === Quickshell.screens[0]
            Connections {
                target: Scratchpad
                function onOpenChanged() {
                    if (Scratchpad.open && spotWindow._scratchHere) spotWindow.grownTarget = "scratchpad"
                    else if (!Scratchpad.open && spotWindow.grownTarget === "scratchpad") spotWindow.grownTarget = ""
                }
            }
            readonly property bool holdsScratchpad: grownTarget === "scratchpad"
            onHoldsScratchpadChanged: if (!holdsScratchpad) Scratchpad.open = false
            // The envelope's width while big: the widest grow since it started
            // (grownTarget empties before the shrink has finished).
            property real _bigW: 0
            onGrownTargetChanged: if (grownTarget) _bigW = grownW
            readonly property real grownH: Math.min(_maxH, (grownLoader.item?.implicitHeight ?? 200) + 32)
            // Springs between resting and grown geometry.
            // Transient (volume, notification, …): on the focused screen only.
            readonly property bool canHostTransient: visible && _revealed && !grown && !tucked && !picking && !GlobalStates.popoutWindows.includes(spotWindow)
            onCanHostTransientChanged: PillTransient.setHost(modelData?.name ?? "", canHostTransient)
            Component.onDestruction: PillTransient.setHost(modelData?.name ?? "", false)
            readonly property bool transientShown: !grown && PillTransient.active && canHostTransient
                && (CompositorService.focusedMonitorName === "" || CompositorService.focusedMonitorName === (modelData?.name ?? ""))
            readonly property real transientLen: Math.max(root.heightPx * 4, (transientView.implicitWidth ?? 0) + 28)
            property real _w: grown ? grownW : root.isVertical ? root.heightPx : (transientShown ? transientLen : length)
            property real _h: grown ? grownH : root.isVertical ? (transientShown ? Math.max(length, 120) : length) : root.heightPx
            // Only while growing/shrinking: resting length already springs.
            property bool _growing: false
            onGrownChanged: { if (grown) _big = true; _growing = true; growSettle.restart() }
            onTransientShownChanged: { _growing = true; growSettle.restart() }
            // The tween's length plus a margin (was a 1.4 s guess).
            Timer { id: growSettle; interval: AnimationConfig.scaledDuration(450) + 60; onTriggered: { spotWindow._growing = false; if (!spotWindow.grown) spotWindow._big = false } }
            // Always animated (after the first appearance): gating on _growing lost
            // the race with the new size in the same turn, so the morph jumped.
            // Grow on the expressive curve, shrink on the accelerate one.
            Behavior on _w { id: wMotion; enabled: spotWindow._animated; MotionSpring { token: Math.abs(wMotion.targetValue - (root.isVertical ? root.heightPx : spotWindow.length)) < 0.5 ? "settle" : "liquid" } }
            Behavior on _h { id: hMotion; enabled: spotWindow._animated; MotionSpring { token: Math.abs(hMotion.targetValue - (root.isVertical ? spotWindow.length : root.heightPx)) < 0.5 ? "settle" : "liquid" } }
            readonly property real cornerRadius: grown ? Appearance.rounding.windowRounding : Math.min(_w, _h) / 2

            // ── Envelope ────────────────────────────────────────────────────
            // The window keeps a fixed size while the pill animates inside it
            // (pillBody): resizing a Wayland surface every frame is a configure
            // round trip per frame, which made every pill animation stutter.
            // It only changes when a grow starts (to the grow size) and after
            // a shrink has settled (back to the resting size).
            property bool _big: false
            readonly property real _screenAlong: (root.isVertical ? modelData?.height : modelData?.width) ?? 1080
            readonly property real _maxAlong: Math.min(Math.max(root.widthPx, 460), _screenAlong - 40)
            readonly property real _envW: !root.isVertical ? Math.max(_maxAlong, _big ? _bigW : 0) : (_big ? Math.max(_maxAlong, _bigW) : root.heightPx)
            readonly property real _envH: !root.isVertical ? (_big ? _maxH : root.heightPx) : (_big ? _maxH : _maxAlong)
            // Exclusive while grown, so Escape works right after the click that
            // grew it (OnDemand only focuses on a later click).
            WlrLayershell.keyboardFocus: grown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Shortcut { sequence: "Escape"; autoRepeat: false; enabled: spotWindow.grown; onActivated: spotWindow.grownTarget = "" }

            // The pill fits its content (a fixed length clipped it), springing
            // between sizes; anoSpot.widthPx is the maximum length.
            readonly property real _lead: root.draggable ? 18 : 6
            readonly property real _contentLen: faceView.preferredLength + _lead + 6
            property real length: Math.max(root.heightPx * 2, Math.min(_contentLen, root.widthPx, _maxAlong))
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
            onLengthChanged: { if (!spotWindow._revealed && revealTimer.running) revealTimer.restart(); spotWindow._moving = true; movingSettle.restart() }
            property bool _moving: false
            Timer { id: movingSettle; interval: 500; onTriggered: spotWindow._moving = false }
            // Only when the frame is opaque (a translucent one would show the
            // overlap darker).
            readonly property bool _paintBody: (_growing || _moving || tuck > 0.001)
                && (Config.options?.appearance?.connectedCorners?.opacity ?? 1) >= 0.999
            // _w follows length and already tweens; animating both stacked two curves.
            Behavior on length { enabled: false; MotionSpring { token: "snappy" } }
            implicitWidth: Math.round(_envW)
            implicitHeight: Math.round(_envH)

            // A classic bar on the same edge: the pill sits inside its band,
            // centred across it (the bar's centre groups make way, BarWindow).
            // Otherwise Normal: placed past whatever else reserves the edge.
            readonly property var _hostBar: !BarStyle.pillInBar ? null : PanelRegistry.panels.find(e => e.kind === "bar"
                && e.screenName === (modelData?.name ?? "") && e.edge === root.position && e.reserve > 0) ?? null
            readonly property real _inBarInset: _hostBar ? Math.max(0, Math.round((_hostBar.reserve - root.heightPx) / 2)) : 0
            exclusionMode: _hostBar ? ExclusionMode.Ignore : ExclusionMode.Normal
            // As the bar it reserves its edge (not while tucked in fullscreen).
            readonly property int barReserve: root.barMode && !screenFullscreen && !autoHide ? root.heightPx + gap : 0
            exclusiveZone: barReserve
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
            readonly property bool connected: fusedLook && !screenFullscreen
            // Connected mode's look (flush, no outline), kept in fullscreen too:
            // the frame retracts under the fullscreen window at once, and the
            // pill switching to its floating look there dropped a bare outlined
            // capsule. It paints its own body (frame colour) instead.
            readonly property bool fusedLook: PanelRegistry.enabled && !(Config.options?.anoSpot?.floating ?? false)
            readonly property int gap: _hostBar ? _inBarInset : fusedLook ? 0 : 6
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
            readonly property bool autoHide: Config.options?.anoSpot?.autoHide ?? false
            readonly property bool tucked: root.edgeLeaving
                || ((screenFullscreen || autoHide) && !grown && !pillHover.hovered && !peekArea.containsMouse && !peekGrace.running)
            function peek() { peekGrace.restart() }
            Timer { id: peekGrace; interval: 1000 }
            HoverHandler {
                id: pillHover
                onHoveredChanged: if (!hovered) peekGrace.restart()
            }
            // 0 = shown, 1 = fully inside the edge.
            property real tuck: tucked ? 1 : 0
            Behavior on tuck { id: tuckMotion; MotionSpring { token: tuckMotion.targetValue > 0.5 ? "settle" : "liquid" } }
            readonly property real _depth: (root.isVertical ? _w : _h) + gap
            readonly property real _shift: Math.max(0, tuck) * _depth
            // The whole content slides; the window itself stays put.
            Binding {
                target: spotWindow.contentItem
                property: root.isVertical ? "x" : "y"
                value: (root.position === "top" || root.position === "left") ? -spotWindow._shift : spotWindow._shift
            }
            // Fully tucked: click-through (only the peek strip takes input).
            // Explicit geometry (an item region doesn't reliably follow the
            // body's moves), in window coordinates incl. the tuck slide.
            mask: Region {
                x: spotWindow.tuck > 0.99 ? 0 : pillBody.x + spotWindow.contentItem.x
                y: spotWindow.tuck > 0.99 ? 0 : pillBody.y + spotWindow.contentItem.y
                width: spotWindow.tuck > 0.99 ? 0 : pillBody.width
                height: spotWindow.tuck > 0.99 ? 0 : pillBody.height
            }

            // Its widest span along the edge (the window is that size), so a
            // sidebar beside it can skip its reserved zone (PanelRegistry.insetBeside).
            readonly property var _span: root.isVertical
                ? { "edge": root.position, "from": pillLease._o.y, "to": pillLease._o.y + spotWindow._maxAlong }
                : { "edge": root.position, "from": pillLease._o.x, "to": pillLease._o.x + spotWindow._maxAlong }
            on_SpanChanged: PanelRegistry.setPillSpan(spotWindow.modelData?.name ?? "", _span)

            ConnectedSurfaceLease {
                id: pillLease
                key: "pill:" + (spotWindow.modelData?.name ?? "")
                kind: "pill"; edge: root.position; priority: 15
                immediate: true
                reserve: spotWindow.barReserve
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
                    // Connected, the pill's edge side is fused into the band:
                    // run the ring past the window there so it traces only the
                    // exposed sides, not a line along the band.
                    readonly property real _off: spotWindow.connected ? spotWindow.cornerRadius * 2 : 0
                    anchors.fill: parent
                    anchors.topMargin: root.position === "top" ? -_off : 0
                    anchors.bottomMargin: root.position === "bottom" ? -_off : 0
                    anchors.leftMargin: root.position === "left" ? -_off : 0
                    anchors.rightMargin: root.position === "right" ? -_off : 0
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
                // Content never shows outside its background.
                clip: true
                // Not rounded: rounding the animated size stepped the morph's
                // ends a pixel at a time. Positions are still pixel-snapped.
                width: spotWindow._w
                height: spotWindow._h
                x: root.position === "right" ? parent.width - width : root.position === "left" ? 0 : Math.round((parent.width - width) / 2)
                y: root.position === "bottom" ? parent.height - height : root.position === "top" ? 0 : Math.round((parent.height - height) / 2)
                radius: spotWindow.cornerRadius
                // Fused but without the frame (fullscreen): square on its edge.
                readonly property real _edgeR: spotWindow.fusedLook && !spotWindow.connected ? 0 : spotWindow.cornerRadius
                topLeftRadius: root.position === "top" || root.position === "left" ? _edgeR : spotWindow.cornerRadius
                topRightRadius: root.position === "top" || root.position === "right" ? _edgeR : spotWindow.cornerRadius
                bottomLeftRadius: root.position === "bottom" || root.position === "left" ? _edgeR : spotWindow.cornerRadius
                bottomRightRadius: root.position === "bottom" || root.position === "right" ? _edgeR : spotWindow.cornerRadius
                // Connected: the frame paints the body, but from another window
                // that learns the new size a frame or more later, so while the
                // pill moves the content led its background. While moving, the
                // pill paints the same opaque body itself (in step with its
                // content); at rest it hands back to the frame (texture, joins).
                color: spotWindow.connected
                    ? (spotWindow._paintBody ? Qt.rgba(Appearance.colors.colLayer0.r, Appearance.colors.colLayer0.g, Appearance.colors.colLayer0.b, 1) : "transparent")
                    : spotWindow.fusedLook
                    ? Qt.rgba(Appearance.colors.colLayer0.r, Appearance.colors.colLayer0.g, Appearance.colors.colLayer0.b,
                        Config.options?.appearance?.connectedCorners?.opacity ?? 1)
                    : (Appearance?.colors?.colLayer0 ?? "#1e1e2e")
                // Glass-token-driven border + opacity so static themes
                // (aurora, angel, etc.) can dial the pill's translucency.
                // Material You and "neutral" static themes leave the
                // tokens at sensible defaults and look unchanged.
                border.width: spotWindow.fusedLook ? 0 : (Appearance?.glassTokens?.borderWidth ?? 1)
                border.color: Appearance?.glassTokens?.borderColor
                            ?? Appearance?.colors?.colOutlineVariant
                            ?? "#444"
                opacity: Appearance?.glassTokens?.opacity ?? 0.96

                // Click dispatcher — catches left/right/middle on the pill background.
                // Widget MouseAreas (e.g. AnoSpotMpris wheel handler) sit above this
                // and intercept their own events; unclaimed clicks fall through here.
                // One click handler for the whole pill. A handler (not a
                // MouseArea): it doesn't take the press, so the faces' swipe
                // drag still works, and nothing else also dispatches the click.
                TapHandler {
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    enabled: !handleArea.containsMouse && !spotWindow.grown
                    // Ctrl+right-click: Customize the pill (CustomizeSheet).
                    onTapped: (point, button) => (button === Qt.RightButton && (point.modifiers & Qt.ControlModifier))
                        ? GlobalStates.customizeSurface = "pill" : root._dispatchClick(button, spotWindow)
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
                    // The leading 14 px across the pill. Placed, not anchored:
                    // switching anchor sets as the edge resolved at startup
                    // sometimes left it 36 tall, the grip over the content.
                    x: 0; y: 0
                    width: root.isVertical ? parent.width : 14
                    height: root.isVertical ? 14 : parent.height
                    color: "transparent"

                    MaterialSymbol {
                        anchors.centerIn: parent
                        // A glyph per direction: rotating drag_indicator (its box
                        // isn't square) drew it below its slot, onto the content.
                        text: root.isVertical ? "drag_handle" : "drag_indicator"
                        iconSize: 12
                        opacity: handleArea.containsMouse || handleArea.drag.active ? 0.85 : 0.5
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
                        // Grown: the grip shrinks it back (clicks inside belong to the panel).
                        onPressed: { if (spotWindow.grown) spotWindow.grownTarget = ""; else spotWindow.picking = true }
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
                    // Sequential crossfade: the outgoing layer leaves fast, the incoming
                    // one waits for it (both at once overlapped into a smear).
                    Behavior on opacity { SequentialAnimation {
                        PauseAnimation { duration: faceView.opacity < 0.5 ? AnimationConfig.scaledDuration(90) : 0 }
                        NumberAnimation { duration: AnimationConfig.scaledDuration(faceView.opacity < 0.5 ? 160 : 90) }
                    } }
                    anchors.fill: parent
                    anchors.margins: 6
                    // Reserve space for the drag handle on the leading edge
                    anchors.leftMargin: !root.isVertical && root.draggable ? 18 : 6
                    anchors.topMargin: root.isVertical && root.draggable ? 18 : 6
                    vertical: root.isVertical
                    thickness: root.heightPx
                    maxLength: Math.min(root.widthPx, spotWindow._maxAlong) - spotWindow._lead - 6
                    faces: root.faces
                    barMode: root.barMode
                }

                // Grown: the target surface's own content component.
                Loader {
                    id: grownLoader
                    active: spotWindow.grown
                    // Laid out once at the grown size, pinned to the pill's edge;
                    // the growing body (clipped) reveals it — no relayout per
                    // frame, and nothing outside its background.
                    width: spotWindow.grownW - 32
                    height: spotWindow.grownH - 32
                    x: root.position === "right" ? parent.width - width - 16 : root.position === "left" ? 16 : Math.round((parent.width - width) / 2)
                    y: root.position === "bottom" ? parent.height - height - 16 : root.position === "top" ? 16 : Math.round((parent.height - height) / 2)
                    opacity: spotWindow.grown && spotWindow._w >= spotWindow.grownW * 0.85 && spotWindow._h >= spotWindow.grownH * 0.6 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(160) } }
                    sourceComponent: ({ mediaControls: grownMedia, controlPanel: grownControl, calendar: grownCalendar, scratchpad: grownScratchpad })[spotWindow.grownTarget] ?? null
                }
                // Transient: icon + level bar (volume/brightness/mic) or label.
                GridLayout {
                    id: transientView
                    // Stacked on side edges (the capsule is narrow there).
                    columns: root.isVertical ? 1 : -1
                    rowSpacing: 6
                    visible: opacity > 0.01
                    opacity: spotWindow.transientShown ? 1 : 0
                    Behavior on opacity { SequentialAnimation {
                        PauseAnimation { duration: transientView.opacity < 0.5 ? AnimationConfig.scaledDuration(90) : 0 }
                        NumberAnimation { duration: AnimationConfig.scaledDuration(transientView.opacity < 0.5 ? 160 : 90) }
                    } }
                    anchors.centerIn: parent
                    columnSpacing: 10
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
                            recording: PillTransient.muted ? "stop_circle" : "fiber_manual_record",
                            device: PillTransient.icon || "devices"
                        })[PillTransient.kind] ?? "info"
                    }
                    Rectangle {
                        visible: transientView.level && !root.isVertical
                        implicitWidth: 120; implicitHeight: 6; radius: 3
                        color: Appearance.colors.colLayer2
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, PillTransient.value)); height: parent.height; radius: 3
                            color: PillTransient.muted ? Appearance.colors.colOutline : Appearance.colors.colPrimary
                            Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(120); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
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
                        visible: !transientView.level && !root.isVertical
                        text: PillTransient.kind === "charging" ? `${PillTransient.label} · ${Math.round(PillTransient.value * 100)}%` : PillTransient.label
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                        Layout.maximumWidth: 280
                    }
                }

                Component { id: grownMedia; MediaControlsContent { } }
                Component { id: grownControl; ControlPanelContent { onCloseRequested: spotWindow.grownTarget = "" } }
                Component { id: grownCalendar; CalendarContent { } }
                Component { id: grownScratchpad; ScratchpadContent { onCloseRequested: Scratchpad.open = false } }
            }
        }
      }
    }
}
