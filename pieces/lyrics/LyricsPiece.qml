import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Bundled piece: synced lyrics of the playing track (services/LyricsService,
// the same lookups as the media panel and the pill's lyrics face). The
// current line is centred and emphasised, the others dimmed by distance;
// click a line to seek there. Holds a lease on the service only while the
// desktop can be seen, so nothing is fetched under a window or the lock.
Item {
    id: root
    property var ctx
    property var settings: ({})

    ServiceLease { service: LyricsService; name: "lyricsPiece"; active: root.ctx?.live ?? false }

    readonly property bool lyricsOn:Config.options?.lyrics?.enable ?? false
    readonly property bool hasPlayer: !!LyricsService.player
    readonly property bool hasLyrics: root.lyricsOn && root.hasPlayer && LyricsService.model.count > 0
    readonly property bool showTrack: (root.settings?.track ?? true) && root.height >= 140
    readonly property real lineSize: Math.max(Appearance.font.pixelSize.small, Math.min(root.height / 9, root.width / 16, 24))

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // The track, small, above the lines.
        RowLayout {
            Layout.fillWidth: true
            visible: root.showTrack && root.hasPlayer
            spacing: 6
            MaterialSymbol { text: "lyrics"; iconSize: 18; color: Appearance.colors.colPrimary }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: `${MprisController.activeTrack?.title ?? ""} · ${MprisController.activeTrack?.artist ?? ""}`
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Empty states: off, nothing playing, looking, none found.
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width
                visible: !root.hasLyrics
                spacing: 4
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: !root.lyricsOn ? "lyrics" : !root.hasPlayer ? "music_off" : LyricsService.pending ? "manage_search" : "speaker_notes_off"
                    iconSize: 28
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: !root.lyricsOn ? "Lyrics are off (Settings → Services → Lyrics)"
                        : !root.hasPlayer ? "Nothing playing"
                        : LyricsService.pending ? "Looking for lyrics…"
                        : "No lyrics for this track"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            ListView {
                id: list
                anchors.fill: parent
                visible: root.hasLyrics
                clip: true
                interactive: false
                spacing: 4
                model: root.hasLyrics ? LyricsService.model : null
                // Before the first line, the first one waits in the middle.
                currentIndex: Math.max(0, LyricsService.currentIndex)
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: list.height / 2 - root.lineSize
                preferredHighlightEnd: list.height / 2 + root.lineSize
                highlightMoveDuration: AnimationConfig.scaledDuration(320)
                highlightMoveVelocity: -1
                delegate: StyledText {
                    id: line
                    required property int index
                    required property string lyricLine
                    required property real time
                    readonly property bool current: line.index === LyricsService.currentIndex
                    readonly property int distance: Math.abs(line.index - list.currentIndex)
                    width: list.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    text: line.lyricLine || "♪"
                    font.pixelSize: line.current ? root.lineSize : root.lineSize * 0.78
                    font.weight: line.current ? Font.DemiBold : Font.Normal
                    color: line.current ? Appearance.colors.colPrimary : Appearance.colors.colOnLayer1
                    opacity: line.current ? 1 : Math.max(0.15, 0.6 - (line.distance - 1) * 0.18)
                    Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(200) } }
                    TapHandler { onTapped: LyricsService.jumpTo(line.index, line.time) }
                }
            }
        }
    }
}
