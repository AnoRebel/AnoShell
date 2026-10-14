import QtQuick
import Quickshell
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * Compact media player card for right sidebar.
 * Shows album art, track info, playback controls, and progress.
 * Inspired by ilyamiro's MusicPopup vinyl design.
 */
Rectangle {
    id: root
    implicitHeight: contentCol.implicitHeight + 16
    radius: Appearance?.rounding.normal ?? 12
    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

    ColumnLayout {
        id: contentCol
        anchors { fill: parent; margins: 8 }
        spacing: 6

        // Source selector — shown when more than one media player is active so
        // the user can pick which one to control. Sets MprisController's tracked
        // player; the rest of the card follows MprisController.activePlayer.
        Flow {
            Layout.fillWidth: true
            spacing: 4
            visible: MprisController.players.length > 1

            Repeater {
                model: MprisController.players
                delegate: Rectangle {
                    id: srcChip
                    required property var modelData
                    readonly property bool isActive: MprisController.activePlayer === modelData
                    readonly property color fg: isActive
                        ? (Appearance?.m3colors.m3onPrimary ?? "white")
                        : (Appearance?.colors.colOnLayer2 ?? "#E6E1E5")
                    implicitWidth: srcRow.implicitWidth + 14
                    implicitHeight: 24
                    radius: height / 2
                    color: isActive
                        ? (Appearance?.colors.colPrimary ?? "#65558F")
                        : (Appearance?.colors.colLayer2 ?? "#2B2930")

                    RowLayout {
                        id: srcRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: "music_note"
                            iconSize: 13
                            color: srcChip.fg
                        }
                        StyledText {
                            text: srcChip.modelData.identity || srcChip.modelData.desktopEntry || "Player"
                            textFormat: Text.PlainText
                            font.pixelSize: Appearance?.font.pixelSize.smallest ?? 10
                            elide: Text.ElideRight
                            Layout.maximumWidth: 90
                            color: srcChip.fg
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MprisController.trackedPlayer = srcChip.modelData
                    }
                }
            }
        }

        // Track info row
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Album art (circular, spinning when playing). The spin targets ONLY
            // the artwork image — never the Layout-managed Rectangle, since
            // rotating a layout child corrupts the row's geometry and visibly
            // tilts the sibling title text. Only spins when real art is present.
            Rectangle {
                id: artHolder
                Layout.preferredWidth: 48; Layout.preferredHeight: 48
                radius: 24
                color: Appearance?.colors.colLayer2 ?? "#2B2930"
                clip: true

                readonly property bool hasArt: (MprisController.activeTrack?.artUrl ?? "").length > 0

                StyledImage {
                    id: artImage
                    anchors.fill: parent
                    source: MprisController.activeTrack?.artUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    visible: artHolder.hasArt
                    transformOrigin: Item.Center

                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: AnimationConfig.scaledDuration(8000)
                        running: MprisController.isPlaying && artHolder.hasArt && AnimationConfig.continuous && (QsWindow.window?.visible ?? false)
                        loops: Animation.Infinite
                    }
                }

                // Fallback note icon when there's no artwork.
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: !artHolder.hasArt
                    text: "music_note"
                    iconSize: 22
                    color: Appearance?.colors.colOnLayer2 ?? "#E6E1E5"
                }

                // Vinyl hole (only over real art)
                Rectangle {
                    anchors.centerIn: parent
                    visible: artHolder.hasArt
                    width: 10; height: 10; radius: 5
                    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    text: MprisController.activeTrack?.title ?? "No media"
                    font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                StyledText {
                    text: MprisController.activeTrack?.artist ?? ""
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    opacity: 0.6
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        // Controls
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12

            // Shuffle
            ToolbarButton {
                iconName: "shuffle"; iconSize: 18
                visible: MprisController.shuffleSupported
                opacity: MprisController.hasShuffle ? 1 : 0.4
                onClicked: MprisController.setShuffle(!MprisController.hasShuffle)
            }

            ToolbarButton { iconName: "skip_previous"; iconSize: 22; onClicked: MprisController.previous(); enabled: MprisController.canGoPrevious }

            // Play/Pause button (prominent)
            Rectangle {
                width: 40; height: 40; radius: 20
                color: Appearance?.colors.colPrimary ?? "#65558F"
                scale: playMA.pressed ? 0.9 : (playMA.containsMouse ? 1.05 : 1)
                Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(150); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: MprisController.isPlaying ? "pause" : "play_arrow"
                    iconSize: 24; fill: 1
                    color: Appearance?.m3colors.m3onPrimary ?? "white"
                }
                MouseArea {
                    id: playMA; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MprisController.togglePlaying()
                }
            }

            ToolbarButton { iconName: "skip_next"; iconSize: 22; onClicked: MprisController.next(); enabled: MprisController.canGoNext }

            // Loop
            ToolbarButton {
                iconName: MprisController.loopState === 2 ? "repeat_one" : "repeat"
                iconSize: 18
                visible: MprisController.loopSupported
                opacity: MprisController.loopState !== 0 ? 1 : 0.4
                onClicked: MprisController.setLoopState((MprisController.loopState + 1) % 3)
            }
        }
    }
}
