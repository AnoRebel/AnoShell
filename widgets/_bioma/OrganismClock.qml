pragma Singleton
import QtQuick
import qs.modules.common as Ano

// One clock for every OrganismTicker, at widgets.fps (10 by default). Tickers
// on their own timers fired at different moments, so a widget with a few of
// them (vitals: heartbeat, liquid, orbit, drops) redrew several times per
// period instead of once. Runs only while a ticker is running.
QtObject {
    id: root
    readonly property int fps: Math.max(1, Math.min(60, Ano.Config.options?.widgets?.fps ?? 10))
    readonly property real frameTime: timer.interval / 1000
    property int users: 0
    signal tick()

    readonly property Timer timer: Timer {
        interval: Math.round(1000 / root.fps)
        repeat: true
        running: root.users > 0
        onTriggered: root.tick()
    }
}
