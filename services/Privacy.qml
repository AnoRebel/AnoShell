pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * What is being captured, and by whom: microphone, camera and screen
 * (spec system-integration, privacy indicator).
 *
 * - PipeWire: a capture link from a source node (not a stream, not a sink's
 *   monitor) into an app's stream, audio or video by the stream's type. Audio
 *   is the microphone; video is a camera when the source is a device
 *   (v4l2/libcamera), otherwise a screencast (the portal's node).
 * - Cameras opened directly (most apps): anod watches /dev/video*
 *   ("camera_users"; anod/internal/camera).
 * - Hyprland: its screencast events (screencopy clients, the portal), counted
 *   once a cast has lasted castDelay, so a screenshot doesn't flash it.
 *
 * uses: [{ kind: "microphone" | "camera" | "screen", app, detail }]
 */
Singleton {
    id: root

    readonly property var uses: {
        const out = [], seen = {}
        const add = (kind, app, detail) => {
            const k = `${kind}:${app}`
            if (seen[k]) return
            seen[k] = true
            out.push({ kind: kind, app: app, detail: detail })
        }
        for (const l of root._audioLinks) add("microphone", root._app(l.target), root._device(l.source))
        for (const l of root._videoLinks) {
            if (root._isCamera(l.source)) add("camera", root._app(l.target), root._device(l.source))
            else add("screen", root._app(l.target), "")
        }
        for (const h of root._cameraHolders) add("camera", h.name, h.label)
        if (root._castLive && !out.some(u => u.kind === "screen")) add("screen", "", root._castTarget)
        return out
    }
    readonly property bool micActive: root.uses.some(u => u.kind === "microphone")
    readonly property bool cameraActive: root.uses.some(u => u.kind === "camera")
    readonly property bool screenSharing: root.uses.some(u => u.kind === "screen")

    // ── PipeWire ─────────────────────────────────────────────────────────
    readonly property var _links: Pipewire.links?.values ?? []
    function _is(node, flag) { return ((node?.type ?? 0) & flag) === flag }
    // The media type comes from the app's stream: virtual sources (EasyEffects'
    // easyeffects_source) carry no type flags of their own.
    function _capture(link, media) {
        const s = link?.source, t = link?.target
        return !!s && !!t && !s.isStream && !s.isSink && t.isStream && root._is(t, media)
    }
    readonly property var _audioLinks: root._links.filter(l => root._capture(l, PwNodeType.Audio))
    readonly property var _videoLinks: root._links.filter(l => root._capture(l, PwNodeType.Video))
    // A node's properties are only filled while it is bound.
    PwObjectTracker {
        objects: root._audioLinks.concat(root._videoLinks).reduce((a, l) => a.concat([l.source, l.target]), []) // no flatMap in QML's JS
    }
    function _app(node) {
        const p = node?.properties ?? {}
        return p["application.name"] || p["node.description"] || node?.description || node?.name || ""
    }
    function _device(node) { return node?.description || node?.nickname || node?.name || "" }
    // Device video (a camera) has a device API; the portal's screencast node doesn't.
    function _isCamera(node) {
        return !!(node?.properties?.["device.api"]) || /^(v4l2|libcamera)_/.test(node?.name ?? "")
    }

    // ── Cameras opened directly (anod) ───────────────────────────────────
    property var _cameraHolders: []
    Connections {
        target: Anod
        function onEvent(name, data) { if (name === "camera_users") root._cameraHolders = data?.holders ?? [] }
        function onAvailableChanged() { root._askCameras() }
    }
    function _askCameras() {
        if (!Anod.available) { root._cameraHolders = []; return }
        Anod.call("camera.users", {}, (r, e) => { if (!e) root._cameraHolders = r?.holders ?? [] })
    }
    Component.onCompleted: root._askCameras()

    // ── Hyprland screencasts ─────────────────────────────────────────────
    // Hyprland toggles screencast 1/0 around nearly every captured frame, so
    // the events are activity pings: live once captures keep coming for
    // castDelay (a screenshot's single frame never is), over castIdle after
    // the last one.
    // ponytail: a capture paused longer than castIdle (damage-only recorders
    // on a still screen) blinks off; portal casts also show via PipeWire.
    readonly property int castDelay: 700
    readonly property int castIdle: 2000
    property double _castStart: 0
    property string _castTarget: ""
    property bool _castLive: false
    function _castPing() {
        if (!castIdleTimer.running) root._castStart = Date.now()
        castIdleTimer.restart()
        if (!root._castLive && Date.now() - root._castStart >= root.castDelay) root._castLive = true
    }
    Timer { id: castIdleTimer; interval: root.castIdle; onTriggered: root._castLive = false }
    Connections {
        target: Hyprland
        enabled: CompositorService.compositor === "hyprland"
        function onRawEvent(event) {
            if (event.name === "screencast") root._castPing()
            else if (event.name === "screencastv2") {
                // STATE,OWNER,NAME: the name (a window title) may hold commas.
                const parts = event.data.split(",")
                if (parts[0] === "1") root._castTarget = parts.slice(2).join(",")
            }
        }
    }

    IpcHandler {
        target: "privacy"
        /// What is being captured now, as JSON ([{kind, app, detail}]).
        function uses(): string { return JSON.stringify(root.uses) }
    }
}
