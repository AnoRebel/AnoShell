// Spike (AnoShell task 8.6): can one MediaPlayer feed two VideoOutputs?
// Run: QT_QPA_PLATFORM=offscreen qml6 multi_sink.qml
import QtQuick
import QtMultimedia

Item {
    id: root
    width: 640; height: 180
    property int framesA: 0
    property int framesB: 0
    property int forwarded: 0
    property string forwardError: ""

    VideoOutput { id: outA; width: 320; height: 180 }
    VideoOutput { id: outB; x: 320; width: 320; height: 180 }

    MediaPlayer {
        id: player
        source: Qt.resolvedUrl("test.mp4")
        videoOutput: outA
        // Second attachment: replaces outA if only one output is allowed.
        Component.onCompleted: { player.videoOutput = outB; player.play() }
    }

    Connections { target: outA.videoSink; function onVideoFrameChanged() { root.framesA++ } }
    Connections { target: outB.videoSink; function onVideoFrameChanged() { root.framesB++ } }

    Timer {
        interval: 2500; running: true
        onTriggered: {
            console.warn(`PLAIN: outA=${root.framesA} outB=${root.framesB}`)
            // Phase 2: player -> outA, forward each frame to outB's sink.
            root.framesA = 0; root.framesB = 0
            player.stop(); player.videoOutput = outA
            fwd.enabled = true
            player.play()
            done.start()
        }
    }
    Connections {
        id: fwd
        enabled: false
        target: outA.videoSink
        function onVideoFrameChanged(frame) {
            try { outB.videoSink.setVideoFrame(frame); root.forwarded++ }
            catch (e) { root.forwardError = String(e) }
        }
    }
    Timer {
        id: done; interval: 2500
        onTriggered: {
            console.warn(`FORWARD: outA=${root.framesA} outB=${root.framesB} forwarded=${root.forwarded} error="${root.forwardError}"`)
            Qt.quit()
        }
    }
}
