import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * Calendar content (month grid, day/upcoming events list): shared by the standalone panel and the pill's grow-into.
 */
ColumnLayout {
    id: root

    // What date the events list is filtered to.
    property date filterDate: new Date()
    property bool showingUpcoming: true
    spacing: 8

    // ─── Header ──────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        MaterialSymbol {
            text: "calendar_month"; iconSize: 18
            color: Appearance?.colors.colPrimary ?? "#a6e3a1"
        }
        StyledText {
            text: "Calendar"
            font.pixelSize: 15; font.weight: Font.DemiBold
            Layout.fillWidth: true
        }
        StyledText {
            text: CalendarSync.fetching
                ? "syncing…"
                : (CalendarSync.ready
                    ? `${CalendarSync.events.length} event${CalendarSync.events.length === 1 ? "" : "s"}`
                    : "no feeds")
            font.pixelSize: 10
            opacity: 0.5
        }
    }

    // ─── Month grid ─────────────────────────────────
    CalendarView {
        id: grid
        Layout.fillWidth: true
        Layout.preferredHeight: 250
        showEventDots: true
        onDateClicked: clickedDate => {
            root.filterDate = clickedDate
            root.showingUpcoming = false
        }
    }

    // ─── Events list ────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        StyledText {
            text: root.showingUpcoming
                ? "Upcoming"
                : Qt.locale().toString(root.filterDate, "dddd, MMM d")
            font.pixelSize: 13
            font.weight: Font.DemiBold
            Layout.fillWidth: true
        }
        RippleButton {
            visible: !root.showingUpcoming
            implicitHeight: 22
            buttonRadius: 6
            contentItem: StyledText {
                text: "Upcoming"; font.pixelSize: 10
                anchors.leftMargin: 8; anchors.rightMargin: 8
            }
            onClicked: root.showingUpcoming = true
        }
    }

    ListView {
        id: eventList
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 4

        readonly property var sourceEvents: root.showingUpcoming
            ? CalendarSync.getUpcomingEvents(Config.options?.calendar?.upcomingDays ?? 7)
            : CalendarSync.getEventsForDate(root.filterDate)

        model: sourceEvents

        // Same expressive transitions as the notification list,
        // gated on the same flag so users have one knob.
        readonly property bool expressive: Config.options?.notifications?.expressiveAnimations ?? true
        add: Transition {
            enabled: eventList.expressive
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: AnimationConfig.scaledDuration(180); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: AnimationConfig.scaledDuration(180); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
            }
        }
        displaced: Transition {
            enabled: eventList.expressive
            NumberAnimation { property: "y"; duration: AnimationConfig.scaledDuration(180); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
        }

        delegate: Rectangle {
            required property var modelData
            width: ListView.view ? ListView.view.width : 0
            implicitHeight: rowCol.implicitHeight + 12
            radius: 8
            color: Appearance?.colors.colLayer1 ?? "#2b2930"
            border.width: 1
            border.color: Appearance?.colors.colOutlineVariant ?? "#44444466"

            // Source-color stripe on the left edge
            Rectangle {
                width: 3
                height: parent.height - 8
                anchors.left: parent.left
                anchors.leftMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                radius: 1.5
                color: modelData.sourceColor || (Appearance?.colors.colPrimary ?? "#a6e3a1")
            }

            ColumnLayout {
                id: rowCol
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                anchors.topMargin: 6
                anchors.bottomMargin: 6
                spacing: 2

                StyledText {
                    text: modelData.title || "(untitled)"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                RowLayout {
                    spacing: 6
                    Layout.fillWidth: true
                    StyledText {
                        text: {
                            const start = new Date(modelData.startDate)
                            if (modelData.allDay) return "All day"
                            return Qt.locale().toString(start, "ddd MMM d · h:mm AP")
                        }
                        font.pixelSize: 10; opacity: 0.65
                    }
                    StyledText {
                        visible: !!modelData.location
                        text: modelData.location ? `· ${modelData.location}` : ""
                        font.pixelSize: 10; opacity: 0.5
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
                StyledText {
                    visible: !!modelData.description && modelData.description.length > 0
                    text: modelData.description ?? ""
                    font.pixelSize: 10
                    opacity: 0.5
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ─── Empty state ────────────────────────────────
    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 8
        spacing: 4
        visible: eventList.count === 0
        MaterialSymbol {
            text: root.showingUpcoming ? "event_busy" : "event_available"
            iconSize: 28; opacity: 0.3
            Layout.alignment: Qt.AlignHCenter
        }
        StyledText {
            text: root.showingUpcoming
                ? (CalendarSync.events.length === 0
                    ? "No calendar feeds configured. Add one in Settings → Services → Calendar sync."
                    : `No upcoming events in the next ${Config.options?.calendar?.upcomingDays ?? 7} days`)
                : "No events on this day"
            font.pixelSize: 11
            opacity: 0.55
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            Layout.maximumWidth: 320
        }
    }
}
