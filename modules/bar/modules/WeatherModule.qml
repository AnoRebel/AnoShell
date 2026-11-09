import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Weather bar module with morph-capable popout showing detailed conditions.
 */
Item {
    id: root
    visible: Config.options?.bar?.weather?.enable ?? false
    implicitWidth: visible ? row.implicitWidth + 12 : 0
    implicitHeight: Appearance.sizes.barHeight
    property bool hovered: weatherMA.containsMouse

    RowLayout {
        id: row; anchors.centerIn: parent; spacing: 4
        MaterialSymbol { text: "thermostat"; iconSize: Appearance?.font.pixelSize.normal ?? 18; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; Layout.alignment: Qt.AlignVCenter }
        StyledText { text: Weather.data.temp || "--"; font.pixelSize: Appearance?.font.pixelSize.small ?? 14; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; Layout.alignment: Qt.AlignVCenter }
        // An official warning is in force (the most severe one's colour).
        MaterialSymbol {
            visible: Weather.shownAlerts.length > 0
            text: "warning"; fill: 1
            iconSize: Appearance?.font.pixelSize.small ?? 14
            color: Weather.alertColor(["extreme", "severe", "moderate", "minor"].find(s => Weather.shownAlerts.some(a => a.severity === s)) ?? "minor")
            Layout.alignment: Qt.AlignVCenter
        }
    }

    MouseArea {
        id: weatherMA; anchors.fill: parent; hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onClicked: GlobalStates.weatherPanelOpen = !GlobalStates.weatherPanelOpen
    }

    BarModulePopout {
        shown: root.hovered
        popupWidth: 280; popupHeight: wPopupCol.implicitHeight + 24

        ColumnLayout {
            id: wPopupCol; anchors.fill: parent; spacing: 8

            // Hero temperature
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 2
                StyledText { text: Weather.data.temp || "--"; font.pixelSize: 36; font.weight: Font.Bold; font.family: Appearance?.font.family.numbers ?? "monospace"; Layout.alignment: Qt.AlignHCenter }
                StyledText { text: `Feels like ${Weather.data.tempFeelsLike || "--"}`; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.5; Layout.alignment: Qt.AlignHCenter }
                StyledText { text: Weather.data.city || ""; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4; Layout.alignment: Qt.AlignHCenter }
            }

            // Quick stats
            GridLayout {
                Layout.fillWidth: true; columns: 3; columnSpacing: 8; rowSpacing: 6
                Repeater {
                    model: [
                        { icon: "water_drop", value: Weather.data.humidity || "--" },
                        { icon: "air", value: `${Weather.data.wind || "--"} ${Weather.data.windDir || ""}` },
                        { icon: "wb_sunny", value: `UV ${Weather.data.uv ?? "--"}` },
                    ]
                    RowLayout {
                        required property var modelData; spacing: 4; Layout.fillWidth: true
                        MaterialSymbol { text: modelData.icon; iconSize: 14; color: Appearance?.colors.colPrimary ?? "#65558F" }
                        StyledText { text: modelData.value; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" }
                    }
                }
            }

            // Sunrise/sunset
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                RowLayout { spacing: 4
                    MaterialSymbol { text: "wb_twilight"; iconSize: 14; color: Appearance.colors.colWarning }
                    StyledText { text: Weather.data.sunrise || "--"; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" } }
                RowLayout { spacing: 4
                    MaterialSymbol { text: "wb_twilight"; iconSize: 14; color: Appearance.colors.colTertiary; rotation: 180 }
                    StyledText { text: Weather.data.sunset || "--"; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" } }
            }

            // Official warnings
            Repeater {
                model: Weather.shownAlerts
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 6
                    MaterialSymbol { text: "warning"; fill: 1; iconSize: 14; color: Weather.alertColor(modelData.severity) }
                    StyledText { text: modelData.headline || modelData.event; elide: Text.ElideRight; Layout.fillWidth: true; font.pixelSize: Appearance.font.pixelSize.smaller }
                }
            }

            StyledText { text: "Click for full weather"; font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.3; Layout.alignment: Qt.AlignHCenter }
        }
    }
}
