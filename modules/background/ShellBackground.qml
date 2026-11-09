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
    // Set without anod. With anod its per-screen announcements decide (a
    // pick for one screen must not switch the others).
    Connections {
        target: Config.options?.background ?? null
        function onWallpaperPathChanged() {
            if (!Anod.available && !Object.values(root.images).includes(root.bg.wallpaperPath))
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

            // Two slots, A and B. The front one is shown; a new path loads
            // into the back one, which the transition masks in, and then the
            // two swap roles (nothing reloads, so no black frame or video
            // restart).
            property bool aFront: true
            property string aPath: ""
            property string bPath: ""
            readonly property string frontPath: aFront ? aPath : bPath
            readonly property string backPath: aFront ? bPath : aPath
            readonly property Item back: aFront ? slotB : slotA
            property real progress: 1
            onPathChanged: {
                if (!path || path === frontPath) return
                // Mid-transition: land the one in flight first, so the slot
                // being shown isn't reloaded under the shader (flash/black).
                if (trans.running) { trans.stop(); win.finish() }
                if (path === frontPath) return
                if (aFront) bPath = path; else aPath = path
            }
            // The back slot becomes the front; the old front unloads. A second
            // call (finished after stop) finds no back path and does nothing.
            function finish() {
                if (!win.backPath) return
                win.aFront = !win.aFront
                if (win.aFront) win.bPath = ""; else win.aPath = ""
                win.progress = 1
            }
            Component.onCompleted: aPath = path
            function backReady() { if (win.backPath && win.back.ready) trans.restart() }

            NumberAnimation {
                id: trans
                target: win; property: "progress"; from: 0; to: 1
                duration: root.transitionType === "none" ? 1 : root.transitionMs
                easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard
                onFinished: win.finish()
            }

            Media {
                id: slotA
                anchors.fill: parent
                path: win.aPath
                playing: !win.covered && win.decodes
                onReadyChanged: if (!win.aFront) win.backReady()
            }
            Media {
                id: slotB
                anchors.fill: parent
                path: win.bPath
                playing: !win.covered && win.decodes
                onReadyChanged: if (win.aFront) win.backReady()
            }
            // The back slot is drawn only through the transition shader.
            ShaderEffectSource {
                id: nextTex
                sourceItem: win.back
                hideSource: true
                live: true
                visible: false
            }
            ShaderEffect {
                anchors.fill: parent
                visible: win.backPath !== "" && win.back.ready
                fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/bg_transition.frag.qsb"))
                property var source: nextTex
                property real progress: win.progress
                property real mode: ({ wipe: 1, right: 1, left: 1, top: 1, bottom: 1, slideRight: 1, grow: 2, center: 2, outer: 2, zoom: 2 })[root.transitionType] ?? 0
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
                source: media.video ? Wallpapers.fileUrl(_still) : Wallpapers.fileUrl(media.path)
                fillMode: root.fillMode
                asynchronous: true
                cache: false
                sourceSize: Qt.size(media.width, media.height)
                // Refetched when the slot's video changes (the item is reused).
                readonly property string _for: media.video ? media.path : ""
                on_ForChanged: _fetch()
                Component.onCompleted: _fetch()
                function _fetch() {
                    _still = ""; _noStill = false
                    if (!_for) return
                    const want = _for
                    Anod.call("palette.get", { path: want }, (res) => {
                        if (want !== _for) return
                        if (res?.still) _still = res.still; else _noStill = true
                    })
                }
            }
        }
        Component {
            id: gif
            AnimatedImage {
                readonly property bool settled: status === Image.Ready || status === Image.Error
                source: Wallpapers.fileUrl(media.path)
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
                    source: Wallpapers.fileUrl(media.path)
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
