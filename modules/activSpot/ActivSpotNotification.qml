import QtQuick
import QtQuick.Layouts
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

RowLayout {
    spacing: 6

    MaterialSymbol {
        text: "notifications"
        iconSize: 16
        color: Appearance?.colors?.colSecondary ?? "#f9e2af"
    }

    StyledText {
        Layout.fillWidth: true
        elide: Text.ElideRight
        text: {
            const n = ActivSpotState.latestNotification;
            if (!n) return "";
            if (n.summary && n.body) return `${n.summary}: ${n.body}`;
            return n.summary || n.body || n.appName || "";
        }
        font.pixelSize: 12
        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
    }
}
