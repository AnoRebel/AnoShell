import QtQuick
import QtQuick.Layouts
import Quickshell
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

RowLayout {
    id: mprisRow
    spacing: 6

    readonly property string scrollAction: Config.options?.anoSpot?.actions?.scrollOnMpris ?? "audio"

    MaterialSymbol {
        text: AnoSpotState.mpris?.playing ? "music_note" : "pause"
        iconSize: 16
        color: Appearance?.colors?.colPrimary ?? "#a6e3a1"
    }

    StyledText {
        Layout.maximumWidth: 200
        elide: Text.ElideRight
        text: {
            const m = AnoSpotState.mpris;
            if (!m) return "";
            if (m.title && m.artist) return `${m.title} — ${m.artist}`;
            return m.title || m.artist || "";
        }
        font.pixelSize: 12
        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
    }

    // Wheel-to-volume overlay. Sits above the row so wheel events are intercepted
    // here rather than falling through to the pill's click MouseArea.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        propagateComposedEvents: true
        enabled: mprisRow.scrollAction === "audio"
        onWheel: wheel => {
            if (wheel.angleDelta.y > 0)
                Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "audio", "increment"]);
            else if (wheel.angleDelta.y < 0)
                Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "audio", "decrement"]);
            wheel.accepted = true;
        }
    }
}
