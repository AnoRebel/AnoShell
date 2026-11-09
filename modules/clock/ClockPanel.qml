import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

/**
 * Clock panel: alarms, world clocks, timer and stopwatch. A card like the
 * calendar's, on the primary screen.
 *
 * Alarms and zones live in services/Chrono (which rings with this panel
 * closed or switched off); the timer and stopwatch are services/Pomodoro's.
 * Open: `qs -c ano ipc call clock toggle`, or middle-click the bar clock.
 */
Scope {
    id: root

    readonly property bool open: GlobalStates.clockOpen
    property string tab: "alarms" // alarms | world | timer | stopwatch
    // Opened on a tab (the pill's timer activity).
    Connections {
        target: GlobalStates
        function onClockTabChanged() { if (GlobalStates.clockTab) { root.tab = GlobalStates.clockTab; GlobalStates.clockTab = "" } }
    }

    function hms(s) {
        s = Math.max(0, Math.floor(s))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
        return (h ? `${h}:${String(m).padStart(2, "0")}` : `${m}`) + `:${String(sec).padStart(2, "0")}`
    }

    Variants {
        model: root.open && GlobalStates.primaryScreen ? [GlobalStates.primaryScreen] : []

        PanelWindow {
            id: panel
            required property var modelData
            screen: modelData
            visible: root.open
            color: "transparent"
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:clock"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

            // Non-modal: input only on the card.
            mask: Region { x: card.x; y: card.y; width: card.width; height: card.height }

            PanelDragHandle { panelCard: card; key: "clock" }

            SurfaceMaterial {
                id: card
                surface: "clock"
                anchors.centerIn: parent
                width: 380
                height: Math.min(content.implicitHeight + 24, parent.height * 0.85)
                radius: Appearance?.rounding.normal ?? 14
                color: Appearance?.m3colors.m3background ?? "#1C1B1F"
                border.width: 1; border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
                scale: root.open ? 1 : 0.95
                Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(180); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
                focus: true
                Keys.onPressed: event => { if (event.key === Qt.Key_Escape) GlobalStates.clockOpen = false }

                ColumnLayout {
                    id: content
                    anchors { fill: parent; margins: 12 }
                    spacing: 10

                    // Header: tabs + close
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        ButtonGroup {
                            Layout.fillWidth: true
                            buttons: [
                                GroupButton { iconName: "alarm"; label: "Alarms"; toggled: root.tab === "alarms"; onClicked: root.tab = "alarms"; Layout.fillWidth: true },
                                GroupButton { iconName: "public"; label: "World"; toggled: root.tab === "world"; onClicked: root.tab = "world"; Layout.fillWidth: true },
                                GroupButton { iconName: "hourglass_bottom"; label: "Timer"; toggled: root.tab === "timer"; onClicked: root.tab = "timer"; Layout.fillWidth: true },
                                GroupButton { iconName: "timer"; showLabel: false; toggled: root.tab === "stopwatch"; onClicked: root.tab = "stopwatch"; Layout.fillWidth: true }
                            ]
                        }
                        ToolbarButton { iconName: "close"; toolTipText: "Close"; onClicked: GlobalStates.clockOpen = false }
                    }

                    // Ringing alarm
                    Rectangle {
                        Layout.fillWidth: true
                        visible: Chrono.ringing !== null
                        implicitHeight: ringRow.implicitHeight + 16
                        radius: Appearance?.rounding.small ?? 8
                        color: Appearance?.colors.colPrimaryContainer ?? "#EADDFF"
                        RowLayout {
                            id: ringRow
                            anchors { fill: parent; margins: 8 }
                            MaterialSymbol { text: "alarm"; iconSize: 22; color: Appearance?.colors.colOnPrimaryContainer ?? "#21005D" }
                            StyledText { Layout.fillWidth: true; text: Chrono.ringing?.label ?? ""; elide: Text.ElideRight; color: Appearance?.colors.colOnPrimaryContainer ?? "#21005D"; font.weight: Font.DemiBold }
                            RippleButton { buttonText: `Snooze ${Chrono.snoozeMinutes} min`; implicitHeight: 30; onClicked: Chrono.snooze() }
                            RippleButton { buttonText: "Dismiss"; implicitHeight: 30; onClicked: Chrono.dismiss() }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        sourceComponent: ({ alarms: alarmsTab, world: worldTab, timer: timerTab, stopwatch: stopwatchTab })[root.tab]
                    }
                }
            }
        }
    }

    // ── Alarms ────────────────────────────────────────────────────────
    Component {
        id: alarmsTab
        ColumnLayout {
            id: alarmsCol
            spacing: 6
            property var editing: null // the alarm being edited, {} for a new one

            EmptyState {
                Layout.fillWidth: true
                visible: Chrono.alarms.length === 0 && alarmsCol.editing === null
                icon: "alarm_off"; title: "No alarms"; hint: "They ring even with this panel closed"
            }
            Repeater {
                model: alarmsCol.editing === null ? Chrono.alarms : []
                delegate: RippleButton {
                    id: alarmRow
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 52
                    onClicked: alarmsCol.editing = modelData
                    contentItem: RowLayout {
                        spacing: 8
                        StyledText {
                            text: Chrono.fmtTime(alarmRow.modelData.h, alarmRow.modelData.m)
                            font.pixelSize: Appearance.font.pixelSize.huge; font.family: Appearance.font.family.numbers
                            opacity: alarmRow.modelData.on ? 1 : 0.45
                        }
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 0
                            StyledText { Layout.fillWidth: true; text: alarmRow.modelData.label || "Alarm"; elide: Text.ElideRight; opacity: alarmRow.modelData.on ? 1 : 0.45 }
                            StyledText {
                                Layout.fillWidth: true; elide: Text.ElideRight
                                text: Chrono.daysText(alarmRow.modelData.days) + (Chrono.snoozes[alarmRow.modelData.id] ? " · snoozed" : "")
                                font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext
                            }
                        }
                        StyledSwitch {
                            checked: alarmRow.modelData.on
                            onClicked: Chrono.setAlarmOn(alarmRow.modelData.id, checked)
                        }
                    }
                }
            }
            RippleButtonWithIcon {
                visible: alarmsCol.editing === null
                Layout.alignment: Qt.AlignHCenter
                iconName: "add"; buttonText: "Add alarm"
                onClicked: alarmsCol.editing = ({})
            }

            // Editor
            ColumnLayout {
                visible: alarmsCol.editing !== null
                Layout.fillWidth: true
                spacing: 8
                property var days: alarmsCol.editing?.days ?? []
                id: editor
                readonly property var parsed: {
                    const m = /^(\d{1,2}):?(\d{2})$/.exec(timeIn.text.trim())
                    return m && Number(m[1]) < 24 && Number(m[2]) < 60 ? { h: Number(m[1]), m: Number(m[2]) } : null
                }
                onVisibleChanged: if (visible) {
                    const e = alarmsCol.editing
                    timeIn.text = e?.id ? `${String(e.h).padStart(2, "0")}:${String(e.m).padStart(2, "0")}` : ""
                    labelIn.text = e?.label ?? ""
                    editor.days = e?.days ?? []
                }
                RowLayout {
                    Layout.fillWidth: true
                    ConfigTextInput { id: timeIn; Layout.preferredWidth: 90; placeholderText: "07:30"; validator: t => editor.parsed ? "" : "HH:MM" }
                    ConfigTextInput { id: labelIn; Layout.fillWidth: true; placeholderText: "Label" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        // Monday first; Sunday = 0
                        model: [1, 2, 3, 4, 5, 6, 0]
                        delegate: RippleButton {
                            required property int modelData
                            Layout.fillWidth: true
                            implicitHeight: 32
                            buttonRadius: 16
                            toggled: editor.days.includes(modelData)
                            colBackgroundToggled: Appearance.colors.colSecondaryContainer
                            buttonText: Qt.locale().dayName(modelData, Locale.NarrowFormat)
                            onClicked: editor.days = toggled ? editor.days.filter(d => d !== modelData) : editor.days.concat([modelData])
                        }
                    }
                }
                StyledText {
                    text: Chrono.daysText(editor.days)
                    font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext
                }
                RowLayout {
                    Layout.fillWidth: true
                    RippleButtonWithIcon {
                        visible: !!alarmsCol.editing?.id
                        iconName: "delete"; buttonText: "Delete"
                        onClicked: { Chrono.deleteAlarm(alarmsCol.editing.id); alarmsCol.editing = null }
                    }
                    Item { Layout.fillWidth: true }
                    RippleButton { buttonText: "Cancel"; implicitHeight: 32; onClicked: alarmsCol.editing = null }
                    RippleButtonWithIcon {
                        enabled: editor.parsed !== null
                        iconName: "check"; buttonText: "Save"
                        onClicked: {
                            Chrono.saveAlarm({ id: alarmsCol.editing?.id ?? "", label: labelIn.text, h: editor.parsed.h, m: editor.parsed.m, days: editor.days, on: true })
                            alarmsCol.editing = null
                        }
                    }
                }
            }
        }
    }

    // ── World clocks ──────────────────────────────────────────────────
    Component {
        id: worldTab
        ColumnLayout {
            id: worldCol
            spacing: 6
            // Seconds aren't shown: the minute is enough.
            readonly property real now: Chrono.now
            readonly property int localOffset: -new Date(now).getTimezoneOffset()
            EmptyState {
                Layout.fillWidth: true
                visible: Chrono.zones.length === 0
                icon: "public"; title: "No world clocks"; hint: "Add a time zone like Asia/Tokyo"
            }
            Repeater {
                model: Chrono.zones
                delegate: RowLayout {
                    id: zoneRow
                    required property string modelData
                    readonly property bool known: Chrono.offsets[modelData] !== undefined
                    readonly property int diff: (Chrono.offsets[modelData] ?? 0) - worldCol.localOffset
                    Layout.fillWidth: true
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        StyledText { Layout.fillWidth: true; text: Chrono.zoneName(zoneRow.modelData); elide: Text.ElideRight }
                        StyledText {
                            Layout.fillWidth: true; elide: Text.ElideRight
                            font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext
                            text: !zoneRow.known ? zoneRow.modelData
                                : zoneRow.diff === 0 ? "Same time"
                                : `${zoneRow.diff > 0 ? "+" : "−"}${Math.floor(Math.abs(zoneRow.diff) / 60)}${Math.abs(zoneRow.diff) % 60 ? `:${String(Math.abs(zoneRow.diff) % 60).padStart(2, "0")}` : ""} h`
                                  + ` · ${Qt.locale().toString(Chrono.zoneDate(zoneRow.modelData, Chrono.now), "ddd")}`
                        }
                    }
                    StyledText {
                        text: zoneRow.known ? Qt.locale().toString(Chrono.zoneDate(zoneRow.modelData, Chrono.now), Config.options?.time?.format ?? "hh:mm") : "…"
                        font.pixelSize: Appearance.font.pixelSize.huge; font.family: Appearance.font.family.numbers
                    }
                    ToolbarButton { iconName: "close"; toolTipText: "Remove"; onClicked: Chrono.removeZone(zoneRow.modelData) }
                }
            }
            ConfigTextInput {
                id: zoneIn
                Layout.fillWidth: true
                placeholderText: "Add a time zone (Europe/Paris)"
                iconAction: "add"
                onIconClicked: { Chrono.addZone(zoneIn.text); zoneIn.text = "" }
                onEditingFinished: if (zoneIn.text.trim()) { Chrono.addZone(zoneIn.text); zoneIn.text = "" }
            }
            StyledText {
                visible: Chrono.zoneError !== ""
                Layout.fillWidth: true; wrapMode: Text.Wrap
                text: Chrono.zoneError
                font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colError
            }
        }
    }

    // ── Timer (Pomodoro's countdown) ──────────────────────────────────
    Component {
        id: timerTab
        ColumnLayout {
            spacing: 10
            CircularProgress {
                Layout.alignment: Qt.AlignHCenter
                implicitSize: 140; lineWidth: 6
                value: 1 - Pomodoro.cdLeft / Math.max(1, Pomodoro.cdLength * 1000)
                StyledText {
                    anchors.centerIn: parent
                    text: root.hms(Math.ceil(Pomodoro.cdLeft / 1000))
                    font.pixelSize: 30; font.family: Appearance.font.family.numbers
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                Repeater {
                    model: [1, 5, 10, 25]
                    RippleButton {
                        required property int modelData
                        enabled: !Pomodoro.cdRunning
                        implicitHeight: 30; implicitWidth: 44; buttonRadius: 15
                        buttonText: `${modelData}m`
                        onClicked: Pomodoro.cdSet(modelData * 60)
                    }
                }
                ConfigTextInput {
                    id: minIn
                    enabled: !Pomodoro.cdRunning
                    Layout.preferredWidth: 70
                    placeholderText: "min"
                    validator: /^\d{1,3}$/
                    onEditingFinished: if (minIn.valid && Number(minIn.text) > 0) Pomodoro.cdSet(Number(minIn.text) * 60)
                }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                RippleButtonWithIcon {
                    iconName: Pomodoro.cdRunning ? "pause" : "play_arrow"
                    buttonText: Pomodoro.cdRunning ? "Pause" : "Start"
                    onClicked: Pomodoro.cdToggle()
                }
                RippleButtonWithIcon { iconName: "restart_alt"; buttonText: "Reset"; onClicked: Pomodoro.cdReset() }
            }
        }
    }

    // ── Stopwatch (Pomodoro's) ────────────────────────────────────────
    Component {
        id: stopwatchTab
        ColumnLayout {
            spacing: 10
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16; Layout.bottomMargin: 16
                text: `${root.hms(Pomodoro.swElapsed / 1000)}.${Math.floor(Pomodoro.swElapsed % 1000 / 100)}`
                font.pixelSize: 44; font.family: Appearance.font.family.numbers
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                RippleButtonWithIcon {
                    iconName: Pomodoro.swRunning ? "pause" : "play_arrow"
                    buttonText: Pomodoro.swRunning ? "Pause" : "Start"
                    onClicked: Pomodoro.swToggle()
                }
                RippleButtonWithIcon { iconName: "restart_alt"; buttonText: "Reset"; onClicked: Pomodoro.swReset() }
            }
        }
    }
}
