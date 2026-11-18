pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.modules.common.functions
import "infiniteModel.js" as Model

/**
 * Workspace layouts: scrolling workspaces and the infinite desktop.
 *
 * Scrolling (scrolling.*): anod writes the rules into its managed compositor
 * file; a change here asks it to (`scrolling.refresh`, a second later: anod
 * reads the config file).
 *
 * Infinite desktop (spec scrollable-workspaces, idea from Anserin): a
 * workspace whose windows all float on a canvas the user pans. Toggle floats
 * every window where it is (and tiles them again); panning moves them all
 * together, one placement batch per frame (the backend sends only the newest).
 * Windows that leave the screen keep their canvas place here; one that would
 * show on another output (Hyprland and sway draw floats on every output they
 * overlap) is parked past all outputs until it comes back into view. Focus
 * moving to a window off screen (Super+arrows, the compositor's own focus
 * binds) pans it into view; new windows open floating at the centre.
 * State (which workspaces, parked windows) survives a shell restart in the
 * same compositor session: $XDG_STATE_HOME/anoshell/infinite-desktop.json.
 */
Singleton {
    id: root
    function load() {}

    // ── Scrolling: tell anod ─────────────────────────────────────────────
    readonly property string _scrollKey: JSON.stringify(Config.options?.scrolling ?? null)
    property string _scrollApplied: ""
    Component.onCompleted: if (Config.ready) root._scrollApplied = root._scrollKey
    Connections {
        target: Config
        function onReadyChanged() { if (Config.ready) root._scrollApplied = root._scrollKey }
    }
    on_ScrollKeyChanged: if (Config.ready && root._scrollApplied !== "") scrollSoon.restart()
    Timer {
        id: scrollSoon
        interval: 1000
        onTriggered: { root._scrollApplied = root._scrollKey; Anod.call("scrolling.refresh", {}, () => {}) }
    }

    // ── Infinite desktop ─────────────────────────────────────────────────
    readonly property bool available: CompositorService.supports.infiniteDesktop ?? false
    readonly property string unavailableReason: root.available ? "" : `${CompositorService.backendName} can't float and move windows by IPC`
    // This compositor session: state from another one is dropped.
    readonly property string instance: ({ hyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE"), niri: Quickshell.env("NIRI_SOCKET"),
        sway: Quickshell.env("SWAYSOCK"), mango: Quickshell.env("MANGO_INSTANCE_SIGNATURE") })[CompositorService.backendName] ?? ""
    // The focused workspace as canvasState names it.
    readonly property string currentKey: {
        const w = CompositorService.workspaces.find(w => w.focused)
        if (!w) return ""
        return CompositorService.backendName === "sway" ? String(w.name) : String(w.id)
    }
    property var desktops: ({})          // workspace key → { parked: { id: rect } }
    readonly property bool active: root.available && root.currentKey !== "" && root.desktops[root.currentKey] !== undefined
    property bool panning: false
    property bool panMode: false          // the pan keys are held (or pan mode is on)
    property var map: null                // { bounds, view, windows } for the overview while panning

    FileView {
        id: stateFile
        path: `${FileUtils.trimFileProtocol(Directories.state)}/anoshell/infinite-desktop.json`
        watchChanges: false
        printErrors: false
        onLoaded: {
            try {
                const s = JSON.parse(text())
                if (s.instance === root.instance && s.desktops) root.desktops = s.desktops
            } catch (e) {}
        }
    }
    function _save() {
        stateFile.setText(JSON.stringify({ instance: root.instance, desktops: root.desktops }))
    }
    function _setDesktop(key, value) {
        const d = Object.assign({}, root.desktops)
        if (value === undefined) delete d[key]
        else d[key] = value
        root.desktops = d
        root._save()
    }

    // The canvas windows: the compositor's, with parked ones at their kept place.
    function _virtual(st) {
        const parked = root.desktops[st.workspace]?.parked ?? {}
        return st.windows.map(w => parked[w.id] ? Object.assign({}, w, { x: parked[w.id].x, y: parked[w.id].y }) : w)
    }
    function _apply(st, wins, placements) {
        const parked = {}
        for (const p of placements) if (p.parked) { const w = wins.find(w => w.id === p.id); parked[w.id] = { x: w.x, y: w.y } }
        const before = JSON.stringify(root.desktops[st.workspace]?.parked ?? {})
        if (JSON.stringify(parked) !== before) root._setDesktop(st.workspace, { parked })
    }

    function toggle(): void {
        if (!root.available) return
        CompositorService.canvasState(st => {
            if (!st) return
            if (root.desktops[st.workspace] === undefined) {
                // Read every rect before floating any: floating one lets the others grow.
                CompositorService.floatWindows(st.windows.filter(w => !w.floating))
                root._setDesktop(st.workspace, { parked: {} })
            } else {
                const wins = root._virtual(st)
                // Parked ones come back into view first, then everything tiles.
                const back = wins.filter(w => root.desktops[st.workspace].parked[w.id])
                    .map(w => Object.assign({ id: w.id }, Model.centred(st.view, w.width, w.height)))
                if (back.length) CompositorService.placeWindows(back)
                CompositorService.tileWindows(wins.map(w => w.id))
                root._setDesktop(st.workspace, undefined)
            }
        })
    }

    // ── Panning: one batch per frame ─────────────────────────────────────
    property var _st: null
    property var _wins: []
    property var _sent: []
    property real _dx: 0
    property real _dy: 0
    property bool _ending: false
    function beginPan(): void {
        if (!root.active || root.panning) return
        root.panning = true
        root._st = null
        CompositorService.canvasState(st => {
            if (!root.panning) return
            if (!st) { root.panning = false; root._dx = 0; root._dy = 0; root._ending = false; return }
            root._st = st
            root._followed = String(st.windows.find(w => w.focused)?.id ?? root._followed)
            root._wins = root._virtual(st)
            root._sent = Model.place(root._wins, st.view, st.others)
            root._updateMap()
        })
    }
    function panBy(dx: real, dy: real): void {
        if (!root.panning) root.beginPan()
        root._dx += dx; root._dy += dy
        if (!frame.running) frame.start()
    }
    function endPan(): void {
        if (!root.panning) return
        root._ending = true
        if (!frame.running) frame.start()
    }
    function _flush() {
        if (!root._st) return // still reading the windows: keep the delta
        if (root._dx !== 0 || root._dy !== 0) {
            root._wins = Model.pan(root._wins, root._dx, root._dy)
            root._dx = 0; root._dy = 0
            const next = Model.place(root._wins, root._st.view, root._st.others)
            const diff = Model.changed(next, root._sent)
            if (diff.length) CompositorService.placeWindows(diff)
            root._sent = next
            root._updateMap()
        }
        if (root._ending) {
            root._ending = false
            root._apply(root._st, root._wins, root._sent)
            root.panning = false; root._st = null; root.map = null
        }
    }
    Timer {
        id: frame
        interval: 16
        repeat: true
        onTriggered: {
            root._flush()
            if (!root.panning || (root._dx === 0 && root._dy === 0 && root._st && !root._ending)) stop()
        }
    }
    function _updateMap() {
        if (!root._st) return
        root.map = { bounds: Model.bounds(root._wins, root._st.view), view: root._st.view, windows: root._wins }
    }

    // A smooth pan of (dx, dy), e.g. to bring the focused window into view.
    property real _glideX: 0
    property real _glideY: 0
    property int _glideLeft: 0
    function glide(dx: real, dy: real): void {
        if (Math.abs(dx) < 1 && Math.abs(dy) < 1) return
        root.beginPan()
        root._glideX = dx; root._glideY = dy
        root._glideLeft = Math.max(1, Math.round(AnimationConfig.scaledDuration(220) / 16))
        glider.restart()
    }
    Timer {
        id: glider
        interval: 16
        repeat: true
        onTriggered: {
            // ease-out: a shrinking share of what is left each frame, all of it on the last
            const n = root._glideLeft--
            const fx = n <= 1 ? root._glideX : root._glideX * (1 - Math.pow(1 - 1 / n, 2))
            const fy = n <= 1 ? root._glideY : root._glideY * (1 - Math.pow(1 - 1 / n, 2))
            root._glideX -= fx; root._glideY -= fy
            root.panBy(fx, fy)
            if (root._glideLeft <= 0) { stop(); root.endPan() }
        }
    }

    // ── Focus follows, new windows centred ───────────────────────────────
    Connections {
        target: ToplevelManager
        enabled: root.active
        function onActiveToplevelChanged() { if (!root.panning) followTimer.restart() }
    }
    property string _followed: ""
    Timer {
        id: followTimer
        interval: 60 // the compositor's own state settles first
        onTriggered: CompositorService.canvasState(st => {
            if (!st || root.desktops[st.workspace] === undefined || root.panning) return
            const f = root._virtual(st).find(w => w.focused)
            // Only a focus change follows (moving windows can re-announce the same one).
            if (!f || String(f.id) === root._followed) return
            root._followed = String(f.id)
            const d = Model.follow(f, st.view, 24)
            root.glide(d.dx, d.dy)
        })
    }
    Connections {
        target: CompositorService
        enabled: root.active
        function onWindowOpened(id, workspace) { root._opened = root._opened.concat([id]); openTimer.restart() }
    }
    property var _opened: []
    Timer {
        id: openTimer
        interval: 150 // mapped and sized
        onTriggered: {
            const ids = root._opened.map(String)
            root._opened = []
            CompositorService.canvasState(st => {
                if (!st || root.desktops[st.workspace] === undefined) return
                // A new window tiles at first (often the whole screen here): no larger than 60 × 70 %.
                const rects = st.windows.filter(w => ids.includes(String(w.id))).map(w => {
                    const width = Math.min(w.width, Math.round(st.view.width * 0.6)), height = Math.min(w.height, Math.round(st.view.height * 0.7))
                    return Object.assign({ id: w.id, width, height }, Model.centred(st.view, width, height))
                })
                if (rects.length) CompositorService.floatWindows(rects)
            })
        }
    }

    // Spread the windows out without overlap, around the view.
    function arrange(): void {
        if (!root.active) return
        CompositorService.canvasState(st => {
            if (!st || root.desktops[st.workspace] === undefined) return
            const wins = root._virtual(st)
            const spots = Model.arrange(wins, st.view, 24)
            const moved = wins.map(w => Object.assign({}, w, spots.find(s => s.id === w.id)))
            const placed = Model.place(moved, st.view, st.others)
            CompositorService.placeWindows(placed)
            root._apply(st, moved, placed)
        })
    }

    // ── Edge push (Hyprland: the pointer is known) ────────────────────────
    // While a window is dragged against an edge of the screen, the canvas pans
    // the other way under it (the dragged window stays under the pointer).
    property var _lastFocus: null
    Timer {
        id: edgeWatch
        interval: 100
        repeat: true
        running: root.active && (CompositorService.supports.cursorPos ?? false) && !root.panMode
        onTriggered: CompositorService.cursorPos(c => {
            if (!c) return
            CompositorService.focusedWindowGeometry(g => {
                const moved = g && root._lastFocus && (g.x !== root._lastFocus.x || g.y !== root._lastFocus.y)
                root._lastFocus = g
                const mon = Quickshell.screens.find(s => c.x >= s.x && c.x < s.x + s.width && c.y >= s.y && c.y < s.y + s.height)
                if (!mon || !moved) return
                const e = 3, step = 40
                const dx = c.x <= mon.x + e ? step : c.x >= mon.x + mon.width - 1 - e ? -step : 0
                const dy = c.y <= mon.y + e ? step : c.y >= mon.y + mon.height - 1 - e ? -step : 0
                if (dx || dy) root._edgePan(dx, dy, g)
            })
        })
    }
    function _edgePan(dx, dy, dragged) {
        CompositorService.canvasState(st => {
            if (!st || root.desktops[st.workspace] === undefined) return
            const all = root._virtual(st)
            const drag = all.find(w => w.focused)
            const others = Model.pan(all.filter(w => w !== drag), dx, dy)
            const placed = Model.place(others, st.view, st.others)
            CompositorService.placeWindows(placed)
            root._apply(st, others, placed)
        })
    }

    IpcHandler {
        target: "infiniteDesktop"
        function toggle(): void { root.toggle() }
        function arrange(): void { root.arrange() }
        // The pan keys: held (Hyprland press/release binds), or toggled elsewhere.
        function panKeys(): void { if (root.active) root.panMode = true }
        function panKeysEnd(): void { root.panMode = false }
        function panKeysToggle(): void { root.panMode = root.active && !root.panMode }
        function pan(dx: int, dy: int): void { if (root.active) root.glide(dx, dy) }
        function status(): string {
            return JSON.stringify({ available: root.available, reason: root.unavailableReason, workspace: root.currentKey,
                active: root.active, panning: root.panning, desktops: root.desktops })
        }
    }
}
