pragma ComponentBehavior: Bound
import QtQuick
import QtMultimedia
import qs.modules.common
import "deck.js" as Deck

// The deck's full-screen preview: the card in front at the size it would
// have on the desktop. From wallpaperpicker's WallpaperBackdrop.qml.
//
// Two images take turns: the one on screen (`front`) and the one loading or
// fading in over it (`back`). Only the latest request (`wanted`) fades in, and
// a running fade finishes before the next load starts (so a fading image is
// never swapped out from under its animation).
//
// Over the still, the live preview: a video (muted, looping) or an animated
// GIF/WebP, `motion` its URL. It fades in once its first frame is up and out
// before the next one loads. Loading a player stalls the shell for a moment,
// so the deck changes `motion` only while it's at rest; while it moves,
// `motionPaused` pauses the one loaded and fades it out.
Item {
    id: backdrop

    property Image front: imgA
    readonly property Image back: front === imgA ? imgB : imgA
    property Image fading: null
    property string wanted: ""
    property bool failed: false
    property bool upgrading: false        // the latest request is a full-resolution upgrade

    readonly property bool loading: back.status === Image.Loading
    readonly property real progress: back.progress

    property string motion: ""            // the live preview wanted ("" none)
    property string playing: ""           // the one loaded (catches up once the last faded out)
    property bool motionPaused: false
    readonly property Item motionItem: motionLayer
    readonly property real motionShown: motionLayer.opacity

    onMotionChanged: if (motionLayer.opacity === 0) swapMotion()

    // `upgrade`: the same wallpaper at a higher resolution, so no zoom.
    function show(url, upgrade) {
        wanted = url || ""
        failed = false
        upgrading = !!upgrade
        if (fadeIn.running) { fadeIn.stop(); settle() }
        if (!url) { back.source = ""; front.opacity = 0; return }
        if (String(front.source) === url && front.status === Image.Ready) return
        back.opacity = 0
        back.scale = upgrade ? 1 : 1.035
        back.z = 2
        front.z = 1
        back.source = url
        if (back.status === Image.Ready) reveal()
    }

    function reveal() {
        if (String(back.source) !== wanted || fadeIn.running) return
        fading = back
        fadeIn.restart()
    }

    function swapMotion() {
        if (playing === motion) return
        playing = ""
        if (motion !== "") Qt.callLater(() => { if (motionLayer.opacity === 0) playing = motion })
    }

    function settle() {
        if (!fading) return
        fading.opacity = 1
        fading.scale = 1
        if (fading !== front) {
            const old = front
            front = fading
            old.opacity = 0
            old.source = ""
        }
        fading = null
    }

    clip: true

    component Layer: Image {
        id: layerImg
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.max(1, backdrop.width), Math.max(1, backdrop.height))
        asynchronous: true
        cache: false
        smooth: true
        mipmap: true // drawn small too: a chosen card's picture is this
        opacity: 0
        onStatusChanged: {
            if (layerImg !== backdrop.back || String(source) !== backdrop.wanted) return
            if (status === Image.Ready) backdrop.reveal()
            else if (status === Image.Error) backdrop.failed = true
        }
    }

    Layer { id: imgA }
    Layer { id: imgB }

    ParallelAnimation {
        id: fadeIn
        NumberAnimation { target: backdrop.fading; property: "opacity"; to: 1; duration: AnimationConfig.scaledDuration(300); easing.type: Easing.OutCubic }
        NumberAnimation { target: backdrop.fading; property: "scale"; to: 1; duration: AnimationConfig.scaledDuration(520); easing.type: Easing.OutCubic }
        onFinished: backdrop.settle()
    }

    // ── The live preview ─────────────────────────────────────────────────
    Item {
        id: motionLayer
        readonly property bool up: !!motionLoader.item && motionLoader.item.ready
            && backdrop.playing !== "" && backdrop.playing === backdrop.motion && !backdrop.motionPaused
        anchors.fill: parent
        z: 3
        opacity: up ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(260); easing.type: Easing.OutCubic } }
        onOpacityChanged: if (opacity === 0 && backdrop.playing !== backdrop.motion) backdrop.swapMotion()

        Loader {
            id: motionLoader
            anchors.fill: parent
            sourceComponent: backdrop.playing === "" ? null : Deck.kind(backdrop.playing) === "video" ? videoMotion : animatedMotion
        }
    }

    Component {
        id: videoMotion
        Item {
            id: movie
            property bool ready: false
            readonly property bool paused: backdrop.motionPaused
            onPausedChanged: paused ? player.pause() : player.play()

            MediaPlayer {
                id: player
                source: backdrop.playing
                loops: MediaPlayer.Infinite
                videoOutput: output
                onErrorOccurred: (error, errorString) => console.warn("[WallpaperDeck] preview:", errorString)
                Component.onCompleted: if (!movie.paused) play()
            }
            VideoOutput { id: output; anchors.fill: parent; fillMode: VideoOutput.PreserveAspectCrop }
            Connections {
                target: output.videoSink
                function onVideoFrameChanged() { movie.ready = true }
            }
        }
    }

    // Frames decoded as they're shown (cache: false), not all held.
    Component {
        id: animatedMotion
        AnimatedImage {
            readonly property bool ready: status === Image.Ready
            source: backdrop.playing
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            smooth: true
            playing: true
            paused: backdrop.motionPaused
        }
    }
}
