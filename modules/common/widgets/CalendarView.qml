import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

/**
 * A simple month calendar grid view.
 */
Item {
    id: root
    property date displayDate: new Date()
    property date selectedDate: new Date()
    property int firstDayOfWeek: 1 // Monday

    signal dateClicked(date clickedDate)

    implicitWidth: 280
    implicitHeight: column.implicitHeight

    function prevMonth() {
        displayDate = new Date(displayDate.getFullYear(), displayDate.getMonth() - 1, 1)
    }
    function nextMonth() {
        displayDate = new Date(displayDate.getFullYear(), displayDate.getMonth() + 1, 1)
    }

    ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: 4

        // Header: month/year + nav
        RowLayout {
            Layout.fillWidth: true
            ToolbarButton { iconName: "chevron_left"; onClicked: root.prevMonth() }
            StyledText {
                text: Qt.locale().toString(root.displayDate, "MMMM yyyy")
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
            ToolbarButton { iconName: "chevron_right"; onClicked: root.nextMonth() }
        }

        // Day headers
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: 7
                StyledText {
                    required property int index
                    text: Qt.locale().dayName((index + root.firstDayOfWeek) % 7, Locale.NarrowFormat)
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                    opacity: 0.5
                    Layout.fillWidth: true
                }
            }
        }

        // Day grid
        Grid {
            id: dayGrid
            columns: 7
            Layout.fillWidth: true
            spacing: 2

            property int year: root.displayDate.getFullYear()
            property int month: root.displayDate.getMonth()
            property int daysInMonth: new Date(year, month + 1, 0).getDate()
            property int startDay: {
                const d = new Date(year, month, 1).getDay()
                return (d - root.firstDayOfWeek + 7) % 7
            }

            Repeater {
                model: dayGrid.startDay + dayGrid.daysInMonth
                Item {
                    required property int index
                    width: (dayGrid.width - 12) / 7
                    height: 32
                    visible: index >= dayGrid.startDay

                    property int dayNum: index - dayGrid.startDay + 1
                    property date thisDate: new Date(dayGrid.year, dayGrid.month, dayNum)
                    property bool isToday: {
                        const now = new Date()
                        return dayNum === now.getDate() && dayGrid.month === now.getMonth() && dayGrid.year === now.getFullYear()
                    }
                    property bool isSelected: dayNum === root.selectedDate.getDate() && dayGrid.month === root.selectedDate.getMonth() && dayGrid.year === root.selectedDate.getFullYear()

                    Rectangle {
                        anchors.centerIn: parent
                        width: 28; height: 28
                        radius: 14
                        color: isSelected ? Appearance?.colors.colPrimary ?? "#65558F"
                            : isToday ? Appearance?.colors.colSecondaryContainer ?? "#E8DEF8"
                            : "transparent"

                        StyledText {
                            anchors.centerIn: parent
                            text: parent.parent.dayNum
                            color: isSelected ? Appearance?.m3colors.m3onPrimary ?? "white"
                                : Appearance?.m3colors.m3onBackground ?? "black"
                            font.weight: isToday ? Font.Bold : Font.Normal
                            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 13
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedDate = parent.parent.thisDate
                                root.dateClicked(parent.parent.thisDate)
                            }
                        }
                    }
                }
            }
        }
    }
}
