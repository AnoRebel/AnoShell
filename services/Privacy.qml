pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

/**
 * What is being captured, and by whom: microphone, camera and screen
 * (spec system-integration, privacy indicator).
 *
 * - PipeWire: a capture link from a source node (not a stream, not a sink's
 *   monitor) into an app. Audio is the microphone; video is a camera when the
 *   source is a device (v4l2/libcamera), otherwise a screencast (the
 *   portal's node).
 * - Cameras opened directly (most apps): anod watches /dev/video*
 *   ("camera_users"; anod/internal/camera).
 * - Hyprland: its screencast events (screencopy clients, the portal), counted
 *   once a capture has stayed open castDelay, so a screenshot doesn't flash it.
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
    // Quickshell types audio streams but not video ones, and virtual audio
    // sources (EasyEffects' easyeffects_source) carry no flags: audio is told
    // by the app's stream, video by the source (a camera or the portal).
    function _audioCapture(link) {
        const s = link?.source, t = link?.target
        return !!s && !!t && !s.isStream && !s.isSink && t.isStream && root._is(t, PwNodeType.Audio)
    }
    function _videoCapture(link) {
        const s = link?.source
        return !!s && !!link?.target && !s.isStream && root._is(s, PwNodeType.Video | PwNodeType.Source)
    }
    readonly property var _audioLinks: root._links.filter(l => root._audioCapture(l))
    readonly property var _videoLinks: root._links.filter(l => root._videoCapture(l))
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
    // screencastv2>>STATE,OWNER,NAME opens (1) and closes (0) a capture per
    // target (a monitor, a window, a region); Hyprland sends the 0 about half
    // a second after the last frame. A capture counts once it has stayed open
    // castDelay: a screenshot (one frame, open ~0.5 s) never does, however many
    // are taken in a row. A 0 closes after castGrace unless a 1 revives it, for
    // clients that toggle around each frame.
    readonly property int castDelay: 700
    readonly property int castGrace: 300
    property var _casts: ({})         // "owner,name" → { since, closing, name }
    property double _now: Date.now()
    readonly property bool _castLive: Object.values(root._casts).some(c => !c.closing && root._now - c.since >= root.castDelay)
    // The captured monitor's name, for the tooltip ("" for a region).
    readonly property string _castTarget: Object.values(root._casts).find(c => !c.closing && c.owner === "monitor")?.name ?? ""
    function _castEvent(open, owner, name) {
        const key = `${owner},${name}`, m = Object.assign({}, root._casts)
        if (open) {
            m[key] = m[key] ? Object.assign({}, m[key], { closing: false }) : { since: Date.now(), closing: false, owner: owner, name: name }
            castCheck.restart()
        } else if (m[key]) {
            m[key] = Object.assign({}, m[key], { closing: true, closedAt: Date.now() })
            castSweep.restart()
        }
        root._casts = m
        root._now = Date.now()
    }
    // Re-evaluate once a fresh capture is old enough, and drop closed ones.
    Timer { id: castCheck; interval: root.castDelay + 10; onTriggered: root._now = Date.now() }
    Timer {
        id: castSweep; interval: root.castGrace
        onTriggered: {
            const m = {}, now = Date.now()
            for (const [k, c] of Object.entries(root._casts)) if (!c.closing || now - c.closedAt < root.castGrace) m[k] = c
            root._casts = m
            if (Object.values(m).some(c => c.closing)) castSweep.restart()
        }
    }
    Connections {
        target: CompositorService
        // Window captures are left out: the shell's own live thumbnails (pill
        // and bar previews, AnoView, the switcher) are window captures, and an
        // app sharing a window goes through the portal, which PipeWire shows.
        function onScreencast(open, owner, name) { if (owner !== "window") root._castEvent(open, owner, name) }
    }

    IpcHandler {
        target: "privacy"
        /// What is being captured now, as JSON ([{kind, app, detail}]).
        function uses(): string { return JSON.stringify(root.uses) }
    }
}
