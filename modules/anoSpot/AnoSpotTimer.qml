import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "root:services/anoSpotLogic.js" as AnoSpotLogic

/**
 * Live activity: the running countdown, pomodoro or stopwatch
 * (services/Pomodoro, the same state the timer piece, the sidebar card and
 * the Clock panel show). Tap opens where it's controlled: the Clock panel's
 * timer or stopwatch tab, or the sidebar's Pomodoro card.
 */
RowLayout {
    id: root
    spacing: 4
    property bool vertical: false

    readonly property var activity: AnoSpotLogic.timer({
        enabled: Pomodoro.enabled, running: Pomodoro.running, phase: Pomodoro.phase, remaining: Pomodoro.remaining,
        cdRunning: Pomodoro.cdRunning, cdLeft: Pomodoro.cdLeft, swRunning: Pomodoro.swRunning, swElapsed: Pomodoro.swElapsed
    })
    readonly property bool active: activity !== null

    function open() {
        const mode = root.activity?.mode ?? ""
        if (mode === "focus" && (Config.options?.pomodoro?.enable ?? false)) { GlobalStates.sidebarRightOpen = true; return }
        GlobalStates.clockTab = mode === "stopwatch" ? "stopwatch" : "timer"
        GlobalStates.clockOpen = true
    }

    MaterialSymbol {
        Layout.alignment: Qt.AlignHCenter
        text: root.activity?.icon ?? "timer"
        iconSize: 15; fill: 1
        color: Appearance.colors.colTertiary
    }
    StyledText {
        visible: !root.vertical
        text: root.activity?.text ?? ""
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.family: Appearance.font.family.numbers
        font.weight: Font.Medium
        color: Appearance.colors.colOnLayer0
    }

    HoverHandler { cursorShape: Qt.PointingHandCursor }
    // Exclusive on press, so the pill's own click (left-click action) doesn't
    // also fire; a swipe along the pill can still take the press over.
    TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onTapped: root.open() }
}
