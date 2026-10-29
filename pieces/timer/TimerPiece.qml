import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Bundled piece: one of services/Pomodoro's timers (the sidebar's Pomodoro
// card shows the same state). Holds the service on while placed. The time
// keeps running while the desktop is covered; only the display waits.
Item {
    id: root
    property var ctx
    property var settings: ({})
    readonly property string mode: root.settings?.mode ?? "focus"
    Component.onCompleted: Pomodoro.hold(true)
    Component.onDestruction: Pomodoro.hold(false)

    function clock(s) {
        s = Math.max(0, Math.floor(s))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
        return (h ? `${h}:${String(m).padStart(2, "0")}` : `${m}`) + `:${String(sec).padStart(2, "0")}`
    }
    readonly property real progress: root.mode === "focus" ? 1 - Pomodoro.remaining / Math.max(1, Pomodoro.phaseLength)
        : root.mode === "countdown" ? 1 - Pomodoro.cdLeft / Math.max(1, Pomodoro.cdLength * 1000) : 0
    readonly property bool running: root.mode === "focus" ? Pomodoro.running : root.mode === "stopwatch" ? Pomodoro.swRunning : Pomodoro.cdRunning
    readonly property string time: root.mode === "focus" ? root.clock(Pomodoro.remaining)
        : root.mode === "stopwatch" ? `${root.clock(Pomodoro.swElapsed / 1000)}.${Math.floor(Pomodoro.swElapsed % 1000 / 100)}`
        : root.clock(Math.ceil(Pomodoro.cdLeft / 1000))
    readonly property string label: root.mode === "focus" ? ({ focus: "Focus", break: "Short break", longBreak: "Long break" })[Pomodoro.phase] + ` · ${Pomodoro.completed} done`
        : root.mode === "stopwatch" ? "Stopwatch" : "Countdown"

    RowLayout {
        anchors.fill: parent
        spacing: 12
        CircularProgress {
            visible: root.mode !== "stopwatch"
            implicitSize: Math.min(root.height * 0.8, root.width * 0.35)
            value: root.progress
            MaterialSymbol { anchors.centerIn: parent; text: root.mode === "focus" ? "self_improvement" : "hourglass_bottom"; iconSize: 22; color: Appearance.colors.colOnLayer1 }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText { text: root.time; font.pixelSize: Math.min(root.height * 0.3, 40); font.family: Appearance.font.family.numbers }
            StyledText { text: root.label; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
            RowLayout {
                spacing: 2
                ToolbarButton {
                    iconName: root.running ? "pause" : "play_arrow"
                    onClicked: root.mode === "focus" ? (Pomodoro.running ? Pomodoro.pause() : Pomodoro.start())
                        : root.mode === "stopwatch" ? Pomodoro.swToggle() : Pomodoro.cdToggle()
                }
                ToolbarButton { visible: root.mode === "focus"; iconName: "skip_next"; toolTipText: "Next phase"; onClicked: Pomodoro.skip() }
                ToolbarButton {
                    iconName: "restart_alt"; toolTipText: "Reset"
                    onClicked: root.mode === "focus" ? Pomodoro.reset() : root.mode === "stopwatch" ? Pomodoro.swReset() : Pomodoro.cdReset()
                }
                Repeater {
                    model: root.mode === "countdown" && !Pomodoro.cdRunning ? [1, 5, 10, 25] : []
                    RippleButton {
                        required property int modelData
                        implicitHeight: 28; implicitWidth: 34; buttonRadius: 14
                        buttonText: `${modelData}m`
                        onClicked: Pomodoro.cdSet(modelData * 60)
                    }
                }
            }
        }
    }
}
