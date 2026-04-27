import QtQuick
import QtQuick.Layouts
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

RowLayout {
    spacing: 6

    MaterialSymbol {
        text: ActivSpotState.mpris?.playing ? "music_note" : "pause"
        iconSize: 16
        color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
    }

    StyledText {
        Layout.maximumWidth: 200
        elide: Text.ElideRight
        text: {
            const m = ActivSpotState.mpris;
            if (!m) return "";
            if (m.title && m.artist) return `${m.title} — ${m.artist}`;
            return m.title || m.artist || "";
        }
        font.pixelSize: 12
        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
    }
}
