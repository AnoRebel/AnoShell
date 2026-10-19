import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Pomodoro + stopwatch (pomodoro.enable). Not focusTime: no DND, no tracking.
Rectangle {
    id: root
    implicitHeight: col.implicitHeight + 20
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1
    function mmss(s) { return `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}` }

    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            CircularProgress {
                implicitSize: 56
                value: 1 - Pomodoro.remaining / Math.max(1, Pomodoro.phaseLength)
                StyledText { anchors.centerIn: parent; text: root.mmss(Pomodoro.remaining); font.pixelSize: Appearance.font.pixelSize.smaller }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { text: ({ focus: "Focus", break: "Short break", longBreak: "Long break" })[Pomodoro.phase]; font.weight: Font.DemiBold }
                StyledText { text: `${Pomodoro.completed} done`; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            }
            ToolbarButton { iconName: Pomodoro.running ? "pause" : "play_arrow"; onClicked: Pomodoro.running ? Pomodoro.pause() : Pomodoro.start() }
            ToolbarButton { iconName: "skip_next"; toolTipText: "Next phase"; onClicked: Pomodoro.skip() }
            ToolbarButton { iconName: "restart_alt"; toolTipText: "Reset"; onClicked: Pomodoro.reset() }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            MaterialSymbol { text: "timer"; iconSize: 20; color: Appearance.colors.colOnLayer1 }
            StyledText {
                Layout.fillWidth: true
                text: { const ms = Pomodoro.swElapsed; return `${root.mmss(ms / 1000)}.${Math.floor(ms % 1000 / 100)}` }
                font.family: Appearance.font.family.numbers
            }
            ToolbarButton { iconName: Pomodoro.swRunning ? "pause" : "play_arrow"; onClicked: Pomodoro.swToggle() }
            ToolbarButton { iconName: "restart_alt"; onClicked: Pomodoro.swReset() }
        }
    }
}
