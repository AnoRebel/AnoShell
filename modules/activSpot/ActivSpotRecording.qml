import QtQuick
import QtQuick.Layouts
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

RowLayout {
    spacing: 4

    Rectangle {
        width: 8
        height: 8
        radius: 4
        color: "#f38ba8"
        SequentialAnimation on opacity {
            running: ActivSpotState.recording.active
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.3; duration: 600 }
            NumberAnimation { from: 0.3; to: 1.0; duration: 600 }
        }
    }

    StyledText {
        text: {
            const s = ActivSpotState.recording.elapsedSeconds;
            const mm = String(Math.floor(s / 60)).padStart(2, '0');
            const ss = String(s % 60).padStart(2, '0');
            return `REC ${mm}:${ss}`;
        }
        font.pixelSize: 12
        font.weight: Font.Medium
        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
    }
}
