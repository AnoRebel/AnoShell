import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Clock bar module with morph-capable popout showing calendar, uptime, weather summary.
 * Middle-click opens the Clock panel; the popout shows the next alarm.
 */
Item {
    id: root
    property bool showDate: Config.options?.bar?.verbose ?? true
    // Vertical bars stack the time (hours over minutes) and drop the date.
    property bool vertical: false
    implicitWidth: rowLayout.implicitWidth
    implicitHeight: vertical ? rowLayout.implicitHeight + 8 : Appearance.sizes.barHeight
    property bool hovered: clockMA.containsMouse

    GridLayout {
        id: rowLayout
        anchors.centerIn: parent; columnSpacing: 4; rowSpacing: -4
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        Repeater {
            // "22:32" → ["22", "32"] when stacked; any AM/PM suffix stays on the minutes.
            model: root.vertical ? [DateTime.time.split(":")[0], DateTime.time.split(":").slice(1).join(":")] : [DateTime.time]
            StyledText {
                required property string modelData
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.large; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; text: modelData
            }
        }
        StyledText { visible: root.showDate && !root.vertical; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; text: "•" }
        StyledText { visible: root.showDate && !root.vertical; font.pixelSize: Appearance.font.pixelSize.small; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; text: DateTime.date }
    }

    // Middle-click: the Clock panel (alarms, world clocks, timer).
    MouseArea {
        id: clockMA; anchors.fill: parent; hoverEnabled: true
        acceptedButtons: PanelGate.enabled("anoClock") ? Qt.MiddleButton : Qt.NoButton
        onClicked: GlobalStates.clockOpen = !GlobalStates.clockOpen
    }

    BarModulePopout {
        shown: root.hovered
        popupWidth: 300; popupHeight: popoutCol.implicitHeight + 24

        ColumnLayout {
            id: popoutCol
            anchors.fill: parent; spacing: 12

            // Large clock
            StyledText {
                text: DateTime.time
                font.pixelSize: 36; font.weight: Font.Bold
                font.family: Appearance?.font.family.numbers ?? "monospace"
                Layout.alignment: Qt.AlignHCenter
            }
            StyledText {
                text: DateTime.collapsedCalendarFormat
                font.pixelSize: Appearance?.font.pixelSize.normal ?? 16
                opacity: 0.5; Layout.alignment: Qt.AlignHCenter
            }

            // Mini calendar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: calView.implicitHeight + 16
                radius: Appearance?.rounding.small ?? 8
                color: Appearance?.colors.colLayer2 ?? "#2B2930"

                CalendarView {
                    id: calView
                    anchors { fill: parent; margins: 8 }
                }
            }

            // Uptime + weather summary
            RowLayout {
                Layout.fillWidth: true; spacing: 12
                RowLayout {
                    spacing: 4
                    MaterialSymbol { text: "schedule"; iconSize: 14; opacity: 0.4 }
                    StyledText { text: `Up ${DateTime.uptime}`; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4 }
                }
                RowLayout {
                    spacing: 4
                    visible: Chrono.nextAlarmText !== ""
                    MaterialSymbol { text: "alarm"; iconSize: 14; opacity: 0.4 }
                    StyledText { text: Chrono.nextAlarmText; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4 }
                }
                Item { Layout.fillWidth: true }
                Loader {
                    active: (Config.options?.bar?.weather?.enable ?? false) && (Weather.data.temp ?? "").length > 0
                    visible: active
                    sourceComponent: RowLayout {
                        spacing: 4
                        MaterialSymbol { text: "thermostat"; iconSize: 14; color: Appearance?.colors.colPrimary ?? "#65558F" }
                        StyledText { text: Weather.data.temp; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" }
                    }
                }
            }
        }
    }
}
