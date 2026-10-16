pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.services

/**
 * Shell-drawn wallpaper (background.engine: shell; experimental until it
 * matches awww — design D8). One background-layer window per screen showing
 * the wallpaper anod applied (it skips awww in this mode), with shader
 * transitions (fade / wipe / grow), stills, GIFs and video.
 *
 * Video: one MediaPlayer feeds one output (spike 8.6), so only the focused
 * screen decodes (background.video.allScreens: false); the others show a still
 * of it. Decoding — and GIF animation — pause while the screen is covered by a
 * maximised or fullscreen window.
 */
Scope {
    id: root

    readonly property var bg: Config.options?.background ?? ({})
    readonly property string resize: bg.resize ?? "fit"
    readonly property bool allScreens: bg.video?.allScreens ?? false
    readonly property string transitionType: (bg.transition?.enable ?? true) ? (bg.transition?.type ?? "fade") : "none"
    readonly property int transitionMs: bg.transition?.duration ?? 800

    // Per-screen images from anod's announcements ("*" = every screen).
    property var images: ({ "*": bg.wallpaperPath ?? "" })
    Connections {
        target: Anod
        function onEvent(name, data) {
            if (name !== "wallpaper_changed" || !data?.wallpaper) return
            const m = Object.assign({}, root.images)
            const outs = data.outputs ?? []
            if (outs.length === 0) { for (const k in m) delete m[k]; m["*"] = data.wallpaper }
            else for (const o of outs) m[o] = data.wallpaper
            root.images = m
        }
    }
    // Set without anod (or before its first announcement).
    Connections {
        target: Config.options?.background ?? null
        function onWallpaperPathChanged() {
            if (!Object.values(root.images).includes(root.bg.wallpaperPath))
                root.images = Object.assign({}, root.images, { "*": root.bg.wallpaperPath })
        }
    }
    function imageFor(name) { return root.images[name] ?? root.images["*"] ?? "" }

    function isVideo(p) { return /\.(mp4|mkv|webm|mov|avi|m4v|ogv)$/i.test(p) }
    function isAnimated(p) { return /\.gif$/i.test(p) }
    readonly property int fillMode: ({ crop: Image.PreserveAspectCrop, fit: Image.PreserveAspectFit, stretch: Image.Stretch, no: Image.Pad })[root.resize] ?? Image.PreserveAspectFit

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            color: "black"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:background"
            anchors { top: true; bottom: true; left: true; right: true }

            readonly property string path: root.imageFor(modelData.name)
            readonly property bool covered: CompositorService.isCovered(modelData.name)
            readonly property bool decodes: root.allScreens || CompositorService.focusedMonitorName === "" || CompositorService.focusedMonitorName === modelData.name

            // Two slots: `current` is shown; a new path loads into `next`,
            // which is masked in by the transition, then swaps.
            property string currentPath: ""
            property string nextPath: ""
            property real progress: 1
            onPathChanged: {
                if (!path || path === currentPath) return
                nextPath = path
            }
            Component.onCompleted: currentPath = path

            NumberAnimation {
                id: trans
                target: win; property: "progress"; from: 0; to: 1
                duration: root.transitionType === "none" ? 1 : root.transitionMs
                easing.type: Easing.InOutCubic
                onFinished: { win.currentPath = win.nextPath; win.nextPath = ""; win.progress = 1 }
            }

            Media {
                id: current
                anchors.fill: parent
                path: win.currentPath
                playing: !win.covered && win.decodes
            }
            Media {
                id: next
                anchors.fill: parent
                path: win.nextPath
                playing: !win.covered && win.decodes
                onReadyChanged: if (ready && win.nextPath) trans.restart()
            }
            // `next` is drawn only through the transition shader.
            ShaderEffectSource {
                id: nextTex
                sourceItem: next
                hideSource: true
                live: true
                visible: false
            }
            ShaderEffect {
                anchors.fill: parent
                visible: win.nextPath !== "" && next.ready
                fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/bg_transition.frag.qsb"))
                property var source: nextTex
                property real progress: win.progress
                property real mode: ({ wipe: 1, right: 1, left: 1, grow: 2, center: 2, outer: 2 })[root.transitionType] ?? 0
                property real aspect: width / Math.max(1, height)
            }
        }
    }

    // One wallpaper: a still, a GIF or a video (a still of it when this screen
    // doesn't decode).
    component Media: Item {
        id: media
        property string path: ""
        property bool playing: true
        readonly property bool video: root.isVideo(path)
        // Ready to be shown — or settled without a picture (a missing file, or
        // no still for a video), so a transition never waits forever.
        readonly property bool ready: videoLoader.active ? (videoLoader.item?.ready ?? false) : (imageLoader.item?.settled ?? false)

        Loader {
            id: imageLoader
            anchors.fill: parent
            active: media.path !== "" && (!media.video || !media.playing)
            sourceComponent: root.isAnimated(media.path) ? gif : still
        }
        Component {
            id: still
            Image {
                // A video's still comes from anod (palette.get → still).
                property string _still: ""
                property bool _noStill: false
                readonly property bool settled: status === Image.Ready || status === Image.Error || _noStill
                source: media.video ? (_still ? "file://" + _still : "") : "file://" + media.path
                fillMode: root.fillMode
                asynchronous: true
                cache: false
                sourceSize: Qt.size(media.width, media.height)
                Component.onCompleted: if (media.video) Anod.call("palette.get", { path: media.path }, (res) => { if (res?.still) _still = res.still; else _noStill = true })
            }
        }
        Component {
            id: gif
            AnimatedImage {
                readonly property bool settled: status === Image.Ready || status === Image.Error
                source: "file://" + media.path
                fillMode: root.fillMode
                playing: media.playing
                asynchronous: true
                cache: false
            }
        }
        Loader {
            id: videoLoader
            anchors.fill: parent
            active: media.path !== "" && media.video && media.playing
            sourceComponent: Item {
                property bool ready: player.mediaStatus === MediaPlayer.BufferedMedia || player.mediaStatus === MediaPlayer.LoadedMedia
                MediaPlayer {
                    id: player
                    source: "file://" + media.path
                    loops: MediaPlayer.Infinite
                    videoOutput: vout
                    Component.onCompleted: play()
                }
                VideoOutput {
                    id: vout
                    anchors.fill: parent
                    fillMode: root.fillMode === Image.PreserveAspectCrop ? VideoOutput.PreserveAspectCrop : root.fillMode === Image.Stretch ? VideoOutput.Stretch : VideoOutput.PreserveAspectFit
                }
            }
        }
    }
}
