import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Bundled widget: services/Weather (wttr.in; the city in Settings → Bar →
// Weather). Hours and days show when enabled and the card is tall enough.
Item {
    id: root
    property var ctx
    property var settings: ({})
    readonly property bool roomy: root.height > 200
    readonly property var d: Weather.data

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            MaterialSymbol {
                text: Weather.iconFor(root.d.wCode)
                iconSize: Math.min(root.height * 0.3, 64)
                fill: 1
                color: Appearance.colors.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { text: root.d.temp || "--"; font.pixelSize: Math.min(root.height * 0.22, 44); font.weight: Font.Light }
                StyledText {
                    Layout.fillWidth: true; elide: Text.ElideRight
                    text: `${root.d.city || ""} · feels ${root.d.tempFeelsLike || "--"}`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }
        }
        Row {
            visible: (root.settings?.hourly ?? true) && root.roomy && Weather.hours.length > 0
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: Weather.hours
                Column {
                    required property var modelData
                    width: parent.width / Math.max(1, Weather.hours.length)
                    spacing: 2
                    StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.time.slice(0, 2); color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest }
                    MaterialSymbol { anchors.horizontalCenter: parent.horizontalCenter; text: Weather.iconFor(modelData.code); iconSize: 18; color: Appearance.colors.colOnLayer1 }
                    StyledText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp; font.pixelSize: Appearance.font.pixelSize.smaller }
                }
            }
        }
        Repeater {
            model: (root.settings?.daily ?? true) && root.roomy ? Weather.days : []
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: 8
                StyledText { text: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd"); Layout.preferredWidth: 40; color: Appearance.colors.colSubtext }
                MaterialSymbol { text: Weather.iconFor(modelData.code); iconSize: 18; color: Appearance.colors.colOnLayer1 }
                Item { Layout.fillWidth: true }
                StyledText { text: `${modelData.min} / ${modelData.max}`; font.pixelSize: Appearance.font.pixelSize.smaller }
            }
        }
        Item { Layout.fillHeight: true }
    }
}
