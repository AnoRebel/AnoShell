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
    // Counted once, wherever the change shows up first (the changed handler
    // can also fire while initial bindings evaluate, before onCompleted).
    property bool _counted: false
    function _count(on) {
        if (on === root._counted) return
        OrganismClock.users += on ? 1 : -1
        root._counted = on
    }
    on_OnClockChanged: root._count(root._onClock)
    Component.onCompleted: root._count(root._onClock)
    Component.onDestruction: root._count(false)

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
