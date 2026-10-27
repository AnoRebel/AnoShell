import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * On-Screen Display — shows volume, brightness, mic, media, keyboard layout,
 * caps lock, and network indicators as a floating pill that auto-hides.
 *
 * Configurable position, timeout, and which indicators are enabled.
 */
Scope {
    id: root

    // Current OSD state
    property string currentIndicator: ""
    property real currentValue: 0
    property bool currentMuted: false
    property string currentLabel: ""
    property string currentIcon: ""

    // Config
    readonly property int timeout: Config.options?.osd?.timeout ?? 1500
    readonly property string position: Config.options?.osd?.position ?? "bottom"
    readonly property bool enableVolume: Config.options?.osd?.indicators?.volume ?? true
    readonly property bool enableBrightness: Config.options?.osd?.indicators?.brightness ?? true
    readonly property bool enableMic: Config.options?.osd?.indicators?.mic ?? true
    readonly property bool enableMedia: Config.options?.osd?.indicators?.media ?? true
    readonly property bool enableKeyboard: Config.options?.osd?.indicators?.keyboard ?? true
    readonly property bool enableNetwork: Config.options?.osd?.indicators?.network ?? true
    readonly property bool enableLockKeys: Config.options?.osd?.indicators?.lockKeys ?? true
    // Off by default: call apps' gain control moves the mic level constantly.
    readonly property bool enableMicVolume: Config.options?.osd?.indicators?.micVolume ?? false

    Timer {
        id: hideTimer
        interval: root.timeout
        onTriggered: root.currentIndicator = ""
    }

    // Services report their initial values a moment after startup; those are
    // not changes the user made, so the OSD ignores them.
    property bool _armed: false
    Timer { running: true; interval: 2000; onTriggered: root._armed = true }

    function show(indicator, value, muted, label, icon) {
        if (!root._armed) return
        // The pill shows it instead (anoSpot.transients.<kind>).
        if (PillTransient.show(indicator, value, muted, label, icon)) return
        root.currentIndicator = indicator
        root.currentValue = value ?? 0
        root.currentMuted = muted ?? false
        root.currentLabel = label ?? ""
        root.currentIcon = icon ?? ""
        hideTimer.restart()
    }

    // ═══ Volume ═══
    // A new output reports its volume as it becomes the default: that is not
    // a volume change (the device event says which output it is).
    property real _sinkSwitchedAt: 0
    Connections {
        target: Audio
        function onSinkChanged() { root._sinkSwitchedAt = Date.now() }
    }
    function _volume() {
        if (Date.now() - root._sinkSwitchedAt < 1500) return
        root.show("volume", Audio.sink.audio.volume, Audio.sink.audio.muted)
    }
    Connections {
        enabled: root.enableVolume
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() { root._volume() }
        function onMutedChanged() { root._volume() }
    }

    // ═══ Brightness ═══
    Connections {
        enabled: root.enableBrightness
        target: Brightness
        function onBrightnessChanged() {
            const focusedName = CompositorService.focusedMonitorName
            const monitor = Brightness.monitors.find(m => focusedName === m.screen.name)
            if (monitor) root.show("brightness", monitor.brightness, false)
        }
    }

    // ═══ Mic (volume and mute) ═══
    Connections {
        enabled: root.enableMic
        target: Audio.source?.audio ?? null
        function onVolumeChanged() { if (root.enableMicVolume) root.show("mic", Audio.source.audio.volume, Audio.source.audio.muted) }
        function onMutedChanged() { root.show("mic", Audio.source.audio.volume, Audio.source.audio.muted) }
    }

    // ═══ Media Track Change ═══
    Connections {
        enabled: root.enableMedia
        target: MprisController
        function onTrackChanged() {
            if (!MprisController.activeTrack) return
            root.show("media", 0, false, `${MprisController.activeTrack.title ?? ""} — ${MprisController.activeTrack.artist ?? ""}`)
        }
    }

    // ═══ Caps Lock / Num Lock ═══
    Connections {
        enabled: root.enableLockKeys
        target: LockKeys
        function onChanged(kind) {
            const on = kind === "capslock" ? LockKeys.capsLock : LockKeys.numLock
            root.show(kind, on ? 1 : 0, false, `${kind === "capslock" ? "Caps Lock" : "Num Lock"} ${on ? "on" : "off"}`)
        }
    }

    // ═══ Device events (DeviceEvents: Bluetooth, USB, audio output, displays) ═══
    Connections {
        target: DeviceEvents
        function onEvent(label, icon) { root.show("device", 0, false, label, icon) }
    }

    // ═══ Keyboard Layout ═══
    Connections {
        enabled: root.enableKeyboard && KeyboardLayoutService.layoutCodes.length > 1
        target: KeyboardLayoutService
        function onCurrentLayoutNameChanged() {
            if (KeyboardLayoutService.currentLayoutName.length > 0)
                root.show("keyboard", 0, false, KeyboardLayoutService.currentLayoutName)
        }
    }

    // ═══ Network State ═══
    Connections {
        enabled: root.enableNetwork
        target: Network
        function onWifiStatusChanged() {
            if (Network.wifiStatus === "connected" && Network.networkName)
                root.show("network", Network.networkStrength / 100, false, Network.networkName)
            else if (Network.wifiStatus === "disconnected")
                root.show("network", 0, false, "WiFi disconnected")
        }
    }

    // ═══ Per-screen instances ═══
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: osdWindow
            required property var modelData
            screen: modelData

            // Kept up until the pill has retracted, so the exit animates too.
            readonly property bool wanted: root.currentIndicator.length > 0
            property real shown: wanted ? 1 : 0
            Behavior on shown { id: shownMotion; MotionSpring { token: shownMotion.targetValue > 0.5 ? "liquid" : "settle" } }
            visible: wanted || shown > 0.001
            readonly property bool connected: PanelRegistry.enabled
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:osd"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: root.position === "top"
                bottom: root.position !== "top"
                left: true; right: true
            }
            implicitHeight: 140
            // Connected mode: flush on the edge so the frame fuses it.
            margins {
                top: root.position === "top" && !connected ? 40 : 0
                bottom: root.position !== "top" && !connected ? 40 : 0
            }

            mask: Region { item: osdBody }

            ConnectedSurfaceLease {
                key: "osd:" + (osdWindow.modelData?.name ?? "")
                kind: "osd"; edge: root.position === "top" ? "top" : "bottom"; priority: 9
                screenName: osdWindow.modelData?.name ?? ""
                active: osdWindow.visible
                progress: osdWindow.shown
                surfaceRadius: osdPill.radius
                x: ((osdWindow.screen?.width ?? 0) - osdBody.width) / 2
                y: root.position === "top" ? osdBody.y : (osdWindow.screen?.height ?? 0) - osdWindow.height + osdBody.y
                w: osdBody.width; h: osdBody.height
            }

            // The pill grows out of its edge (pinned there) and retracts into it;
            // the full-size pill inside is uncovered, not relaid out.
            Item {
                id: osdBody
                clip: true
                width: osdPill.width
                height: osdPill.height * Math.max(0, Math.min(osdWindow.shown, 1.1))
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: root.position !== "top" ? parent.bottom : undefined
                anchors.top: root.position === "top" ? parent.top : undefined

            SurfaceMaterial {
                id: osdPill
                surface: "osd"
                anchors.bottom: root.position !== "top" ? parent.bottom : undefined
                anchors.top: root.position === "top" ? parent.top : undefined

                // Width depends on whether we have a label or a progress bar
                property bool isProgressType: ["volume", "brightness", "mic"].includes(root.currentIndicator)
                property bool isLabelType: ["media", "keyboard", "network", "capslock", "numlock", "device"].includes(root.currentIndicator)

                width: isLabelType ? Math.min(labelRow.implicitWidth + 40, 420) : 280
                height: 56
                radius: 28
                color: osdWindow.connected ? "transparent" : (Appearance?.colors.colLayer0 ?? "#1C1B1F")
                border.width: osdWindow.connected ? 0 : 1
                border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
                Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                // Progress mode (volume/brightness/mic)
                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 12
                    visible: osdPill.isProgressType

                    MaterialSymbol {
                        text: {
                            if (root.currentMuted) {
                                if (root.currentIndicator === "volume") return "volume_off"
                                if (root.currentIndicator === "mic") return "mic_off"
                            }
                            switch (root.currentIndicator) {
                                case "volume":
                                    if (root.currentValue > 0.66) return "volume_up"
                                    if (root.currentValue > 0.33) return "volume_down"
                                    if (root.currentValue > 0) return "volume_mute"
                                    return "volume_off"
                                case "brightness":
                                    if (root.currentValue > 0.66) return "brightness_high"
                                    if (root.currentValue > 0.33) return "brightness_medium"
                                    return "brightness_low"
                                case "mic": return root.currentMuted ? "mic_off" : "mic"
                                default: return "info"
                            }
                        }
                        iconSize: 24; fill: 1
                        color: root.currentMuted
                            ? Appearance?.m3colors.m3error ?? "#BA1A1A"
                            : Appearance?.colors.colPrimary ?? "#65558F"
                    }

                    StyledProgressBar {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        valueBarHeight: 6
                        value: root.currentMuted ? 0 : root.currentValue
                        highlightColor: root.currentMuted
                            ? Appearance?.m3colors.m3error ?? "#BA1A1A"
                            : Appearance?.colors.colPrimary ?? "#65558F"
                    }

                    StyledText {
                        text: root.currentMuted ? "Muted" : `${Math.round(root.currentValue * 100)}%`
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        font.family: Appearance?.font.family.numbers ?? "monospace"
                        font.weight: Font.DemiBold
                        color: root.currentMuted
                            ? Appearance?.m3colors.m3error ?? "#BA1A1A"
                            : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                        Layout.preferredWidth: 50
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // Label mode (media/keyboard/network)
                RowLayout {
                    id: labelRow
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 12
                    visible: osdPill.isLabelType

                    MaterialSymbol {
                        text: {
                            switch (root.currentIndicator) {
                                case "media": return MprisController.isPlaying ? "music_note" : "pause"
                                case "keyboard": return "keyboard"
                                case "network": return Network.materialSymbol
                                case "capslock": return "keyboard_capslock"
                                case "numlock": return "dialpad"
                                case "device": return root.currentIcon || "devices"
                                default: return "info"
                            }
                        }
                        iconSize: 24; fill: 1
                        color: Appearance?.colors.colPrimary ?? "#65558F"
                    }

                    StyledText {
                        text: root.currentLabel
                        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                        font.weight: Font.DemiBold
                        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                        Layout.maximumWidth: 320
                    }
                }
            }
            }
        }
    }
}
