import QtQuick

// Drop-in for FrameAnimation in the ported organisms: the same running,
// frameTime and triggered, at widgets.fps (10 by default) instead of every
// frame. The widget layer is a full-screen surface, so each tick redraws it;
// at the display's rate a few moving organisms cost ~20% of a core.
// All tickers share OrganismClock, so they fire in the same turn and a widget
// redraws once per tick. An explicit interval (a once-a-second hand) keeps its
// own timer.
QtObject {
    id: root
    property bool running: false
    property int interval: 0
    readonly property real frameTime: root.interval > 0 ? root.interval / 1000 : OrganismClock.frameTime
    signal triggered()

    readonly property bool _onClock: root.running && root.interval <= 0
    on_OnClockChanged: OrganismClock.users += root._onClock ? 1 : -1
    Component.onCompleted: if (root._onClock) OrganismClock.users++
    Component.onDestruction: if (root._onClock) OrganismClock.users--

    readonly property Connections _clock: Connections {
        target: OrganismClock
        enabled: root._onClock
        function onTick() { root.triggered() }
    }
    readonly property Timer _own: Timer {
        interval: Math.max(1, root.interval)
        repeat: true
        running: root.running && root.interval > 0
        onTriggered: root.triggered()
    }
}
