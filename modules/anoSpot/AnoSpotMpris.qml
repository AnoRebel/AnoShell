import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

RowLayout {
    id: mprisRow
    spacing: 6

    readonly property string scrollAction: Config.options?.anoSpot?.actions?.scrollOnMpris ?? "audio"
    // Show lyrics inline when the user opted into lyrics-in-AnoSpot AND
    // LyricsService has a current line for the active track. Falls back
    // to title/artist when either condition is false.
    readonly property bool showLyrics:
        (Config.options?.anoSpot?.showLyrics ?? false)
        && (Config.options?.lyrics?.enable ?? false)
        && LyricsService.model.count > 0
        && LyricsService.currentIndex >= 0
    readonly property string currentLyric: showLyrics
        ? (LyricsService.model.get(LyricsService.currentIndex)?.lyricLine ?? "")
        : ""

    MaterialSymbol {
        text: showLyrics ? "lyrics" : (AnoSpotState.mpris?.playing ? "music_note" : "pause")
        iconSize: 16
        color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
    }

    // The flexible part of the pill: shrinks and elides so the clock and
    // battery always fit.
    StyledText {
        Layout.fillWidth: true
        Layout.minimumWidth: 40
        Layout.maximumWidth: 200
        elide: Text.ElideRight
        text: {
            // Prefer the current lyric line when available; the user
            // explicitly turned on activSpot.showLyrics so they'd rather
            // see what's playing right now than the static metadata.
            if (mprisRow.showLyrics && mprisRow.currentLyric.length > 0)
                return mprisRow.currentLyric;
            const m = AnoSpotState.mpris;
            if (!m) return "";
            if (m.title && m.artist) return `${m.title} — ${m.artist}`;
            return m.title || m.artist || "";
        }
        font.pixelSize: 12
        font.italic: mprisRow.showLyrics && mprisRow.currentLyric.length > 0
        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
        Behavior on text { PropertyAnimation { duration: AnimationConfig.scaledDuration(150) } }
    }

    // Wheel-to-volume. A handler, not an anchored MouseArea (this is a
    // layout), and the Audio service directly instead of spawning `qs ipc`.
    WheelHandler {
        enabled: mprisRow.scrollAction === "audio"
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (event.angleDelta.y > 0) Audio.incrementVolume()
            else if (event.angleDelta.y < 0) Audio.decrementVolume()
            event.accepted = true
        }
    }
}
