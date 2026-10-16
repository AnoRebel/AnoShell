import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.spectrum
import qs.services

/**
 * Media controls content (art, track, lyrics, spectrum, transport, volume, players): one source of truth shared by the standalone panel and the pill's grow-into.
 */
ColumnLayout {
    id: root
    spacing: 16

    // Album art (large, circular with vinyl spin)
    Item {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 200; Layout.preferredHeight: 200

        // Outer ring
        Rectangle {
            anchors.fill: parent; radius: 100
            color: "transparent"
            border.width: 3; border.color: Appearance?.colors.colPrimary ?? "#65558F"
        }

        // Album art
        Rectangle {
            anchors.centerIn: parent
            width: 184; height: 184; radius: 92
            color: Appearance?.colors.colLayer2 ?? "#2B2930"
            clip: true

            Image {
                id: albumArt
                anchors.fill: parent
                source: MprisController.activeTrack?.artUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true

                RotationAnimator {
                    // An animator has no `parent`; target the art by id.
                    target: albumArt; from: 0; to: 360; duration: AnimationConfig.scaledDuration(12000)
                    running: MprisController.isPlaying && AnimationConfig.continuous && (QsWindow.window?.visible ?? false)
                    loops: Animation.Infinite
                }

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle { width: 184; height: 184; radius: 92 }
                }
            }

            // Vinyl hole
            Rectangle {
                anchors.centerIn: parent
                width: 16; height: 16; radius: 8
                color: Appearance?.m3colors.m3background ?? "#1C1B1F"
            }
        }
    }

    // Track info
    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter; spacing: 4

        StyledText {
            text: MprisController.activeTrack?.title ?? "No media playing"
            font.pixelSize: Appearance?.font.pixelSize.huger ?? 22
            font.weight: Font.Bold
            elide: Text.ElideRight
            Layout.maximumWidth: root.width
            Layout.alignment: Qt.AlignHCenter
        }
        StyledText {
            text: MprisController.activeTrack?.artist ?? ""
            font.pixelSize: Appearance?.font.pixelSize.normal ?? 16
            opacity: 0.6
            elide: Text.ElideRight
            Layout.maximumWidth: root.width
            Layout.alignment: Qt.AlignHCenter
        }
        StyledText {
            text: MprisController.activeTrack?.album ?? ""
            font.pixelSize: Appearance?.font.pixelSize.small ?? 14
            opacity: 0.3
            visible: (MprisController.activeTrack?.album ?? "").length > 0
            elide: Text.ElideRight
            Layout.maximumWidth: root.width
            Layout.alignment: Qt.AlignHCenter
        }
    }

    // Lyrics — 5 lines centered on LyricsService.currentLine
    // (2 before, current bold + accent, 2 after). Visible only
    // when the user opted into lyrics AND the active track has
    // lyrics loaded. Section is gated by lyrics.visible (which
    // the user can toggle without disabling the whole service).
    Loader {
        Layout.fillWidth: true
        active: (Config.options?.lyrics?.enable ?? false)
                && (Config.options?.lyrics?.visible ?? true)
                && LyricsService.model.count > 0
        visible: active
        sourceComponent: ColumnLayout {
            spacing: 2
            readonly property int linesShown: 5
            readonly property int half: Math.floor(linesShown / 2)

            Repeater {
                model: parent.linesShown
                StyledText {
                    required property int index
                    readonly property int targetIdx:
                        LyricsService.currentIndex - parent.half + index
                    readonly property bool inRange:
                        targetIdx >= 0 && targetIdx < LyricsService.model.count
                    readonly property bool isCurrent:
                        targetIdx === LyricsService.currentIndex && targetIdx >= 0
                    Layout.fillWidth: true
                    Layout.maximumWidth: root.width
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: inRange
                        ? (LyricsService.model.get(targetIdx)?.lyricLine ?? "")
                        : ""
                    font.pixelSize: isCurrent
                        ? (Appearance?.font.pixelSize.normal ?? 16)
                        : (Appearance?.font.pixelSize.smaller ?? 12)
                    font.weight: isCurrent ? Font.DemiBold : Font.Normal
                    color: isCurrent
                        ? (Appearance?.colors.colPrimary ?? "#a6e3a1")
                        : (Appearance?.colors.colOnLayer1 ?? "#cdd6f4")
                    opacity: isCurrent ? 1
                        : (inRange
                            ? (1 - Math.abs(targetIdx - LyricsService.currentIndex) * 0.3)
                            : 0)
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(150) } }
                }
            }
        }
    }

    // Audio spectrum (if cava active)
    Loader {
        Layout.fillWidth: true; Layout.preferredHeight: 32
        active: !SpectrumService.isIdle
        visible: active
        sourceComponent: MirroredSpectrum {
            fillColor: Qt.rgba((Appearance?.colors.colPrimary ?? "#65558F").r, (Appearance?.colors.colPrimary ?? "#65558F").g, (Appearance?.colors.colPrimary ?? "#65558F").b, 0.5)
            cornerRadius: 3
        }
    }

    // Playback controls
    RowLayout {
        Layout.alignment: Qt.AlignHCenter; spacing: 20

        // Shuffle
        ToolbarButton {
            iconName: "shuffle"; iconSize: 22
            visible: MprisController.shuffleSupported
            opacity: MprisController.hasShuffle ? 1 : 0.3
            onClicked: MprisController.setShuffle(!MprisController.hasShuffle)
        }

        ToolbarButton { iconName: "skip_previous"; iconSize: 28; onClicked: MprisController.previous(); enabled: MprisController.canGoPrevious }

        // Large play/pause
        Rectangle {
            width: 56; height: 56; radius: 28
            color: Appearance?.colors.colPrimary ?? "#65558F"
            scale: playBtnMA.pressed ? 0.88 : (playBtnMA.containsMouse ? 1.08 : 1)
            Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(100); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
            MaterialSymbol {
                anchors.centerIn: parent
                text: MprisController.isPlaying ? "pause" : "play_arrow"
                iconSize: 32; fill: 1
                color: Appearance?.m3colors.m3onPrimary ?? "white"
            }
            MouseArea { id: playBtnMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: MprisController.togglePlaying() }
        }

        ToolbarButton { iconName: "skip_next"; iconSize: 28; onClicked: MprisController.next(); enabled: MprisController.canGoNext }

        // Loop
        ToolbarButton {
            iconName: MprisController.loopState === 2 ? "repeat_one" : "repeat"
            iconSize: 22
            visible: MprisController.loopSupported
            opacity: MprisController.loopState !== 0 ? 1 : 0.3
            onClicked: MprisController.setLoopState((MprisController.loopState + 1) % 3)
        }
    }

    // Volume slider
    RowLayout {
        Layout.fillWidth: true; spacing: 8
        MaterialSymbol { text: "volume_up"; iconSize: 20; opacity: 0.5 }
        StyledSlider {
            Layout.fillWidth: true
            configuration: StyledSlider.Configuration.S
            value: Audio.sink?.audio?.volume ?? 0
            onMoved: { if (Audio.sink?.audio) Audio.sink.audio.volume = value }
            stopIndicatorValues: [1]
        }
    }

    // Player switcher (if multiple)
    Loader {
        Layout.fillWidth: true
        active: MprisController.players.length > 1
        visible: active
        sourceComponent: RowLayout {
            Layout.fillWidth: true; spacing: 4
            StyledText { text: "Players:"; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4 }
            Repeater {
                model: MprisController.players
                GroupButton {
                    required property var modelData
                    label: modelData.identity ?? modelData.dbusName ?? "?"
                    toggled: MprisController.activePlayer === modelData
                    onClicked: MprisController.setActivePlayer(modelData)
                }
            }
        }
    }
}
