import QtQuick

// How far through the current minute the wall clock is, 0 to 1, moving
// continuously rather than once a second.
//
// The clock's disc used to be fed the seconds: a value that changed once a
// second, eased for a fifth of it and then still, which read as a tick
// (Akusen, 2026-09-27). This runs the minute as one linear animation on Qt's
// own frame clock, from wherever the minute is when it starts, and sets
// itself against the system time again every minute, so it never drifts
// further than one minute's worth of frame timing.
//
// It is still a live value: the disc is where the second hand is, not at a
// rate chosen to look alive.
Item {
    id: root

    property real value: 0

    // AnoShell: where the second hand is, read from the clock at pieces.fps
    // (Bioma swept it with an animation at the display's rate).
    function sync() {
        const now = new Date();
        root.value = (now.getSeconds() * 1000 + now.getMilliseconds()) / 60000;
    }
    property bool running: true
    // once a second: a second hand
    OrganismTicker {
        interval: 1000
        running: root.running
        onTriggered: root.sync()
    }

    Component.onCompleted: root.sync()
}
