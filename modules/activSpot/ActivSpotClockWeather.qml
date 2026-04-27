import QtQuick
import QtQuick.Layouts
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

RowLayout {
    spacing: 6

    StyledText {
        text: ActivSpotState.clockWeather.time
        font.pixelSize: 12
        font.weight: Font.Medium
        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
    }

    StyledText {
        visible: text.length > 0
        text: {
            const t = ActivSpotState.clockWeather.weatherTemp;
            return t ? `· ${t}` : "";
        }
        font.pixelSize: 12
        color: Appearance?.colors?.colOnLayer0Subtle ?? "#a6adc8"
    }
}
