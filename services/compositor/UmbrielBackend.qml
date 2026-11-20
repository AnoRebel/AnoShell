import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "UmbrielModel.js" as UmbrielModel

/**
 * Umbriel backend (written against umbriel 0.1.0; tested nested, see
 * BackendContract.md and docs/compositors.md).
 *
 * One `umbriel subscribe windows,workspaces,keyboard_layout` process drives
 * everything: it prints the whole state of a kind as a JSON line at start and
 * on every change (UmbrielModel.js). Actions are `umbriel msg <action> …`
 * argv. The CLI finds the compositor through $UMBRIEL_SOCKET, which umbriel
 * exports to everything it starts. Workspaces are per output, numbered from 1.
 * No ext-background-effect: blur comes from the layer rules in
 * external/umbriel/ano.toml.
 */
GenericBackend {
    id: root
    experimental: false // tested end to end (docs/compositors.md)

    name: "umbriel"
    supports: ({
        workspaces: true, perOutputWorkspaces: true, windowCapture: false, blurProtocol: false, layerBlurRules: false,
        outerGaps: true, cursorZoom: false, screenShader: false, dpms: true, outputConfig: false, exit: true,
        keyboardLayouts: true, moveToWorkspace: true, infiniteDesktop: true
    })

    property var _workspaces: []
    property var _windows: []

    focusedOutput: UmbrielModel.focusedOutput(root._workspaces) || (Quickshell.screens[0]?.name ?? "")
    workspaces: UmbrielModel.workspaces(root._workspaces)
    fullscreenOutputs: UmbrielModel.fullscreen(root._windows)
    coveredOutputs: UmbrielModel.covered(root._windows)
    windows: {
        if (root.windowLeases === 0) return []
        const toplevels = Array.from(ToplevelManager.toplevels?.values ?? [])
        return UmbrielModel.windows(root._windows, root._workspaces).map(w => Object.assign(w, {
            toplevel: toplevels.find(t => t.appId === w.appId && t.title === w.title) ?? null
        }))
    }

    // ── Events ───────────────────────────────────────────────────────────
    // umbriel resends a kind with nothing changed (e.g. windows on a redraw):
    // identical lines are dropped.
    property var _last: ({})
    property var _subscribe: Process {
        command: ["umbriel", "subscribe", "windows,workspaces,keyboard_layout"]
        running: true
        stdout: SplitParser {
            onRead: line => {
                const o = UmbrielModel.parse(line)
                if (!o || root._last[o.event] === line) return
                root._last[o.event] = line
                if (o.event === "workspaces" && Array.isArray(o.data)) root._workspaces = o.data
                else if (o.event === "windows" && Array.isArray(o.data)) root._windows = o.data
                else if (o.event === "keyboard_layout") {
                    const l = UmbrielModel.layouts(o.data)
                    root.keyboardLayout = l.current
                    root.keyboardLayouts = l.names
                    return
                } else return
                root.revision++
            }
        }
        // umbriel restarted, or not up yet: try again.
        onExited: (code, status) => { root._last = {}; root._retry.restart() }
    }
    property var _retry: Timer { interval: 2000; onTriggered: root._subscribe.running = true }

    // ── Actions ──────────────────────────────────────────────────────────
    function _msg(action, args, opts) {
        const argv = UmbrielModel.msg(action, args, opts)
        if (!argv) return false
        Quickshell.execDetached(argv)
        return true
    }
    function focusWorkspace(number, outputName) {
        const n = Math.round(number)
        if (n < 1) return false
        return outputName ? root._msg("workspace-switch", [n], { output: outputName }) : root._msg("workspace-switch", [n])
    }
    function focusWorkspaceRelative(delta) { return root._msg(delta < 0 ? "workspace-previous" : "workspace-next") }
    function exit() { return root._msg("session-quit", ["skip-confirmation"]) }
    function powerOffMonitors() { return root._msg("dpms-off") }
    function powerOnMonitors() { return root._msg("dpms-on") }
    // umbriel only steps forward: back is forward n-1 times.
    function switchKeyboardLayout(delta) {
        const steps = delta < 0 ? Math.max(1, root.keyboardLayouts.length - 1) : 1
        for (let i = 0; i < steps; i++) root._msg("keyboard-layout-next")
        return true
    }
    function focusedWindowGeometry(cb) {
        const w = UmbrielModel.windows(root._windows, root._workspaces).find(w => w.focused)
        cb(w ? { x: w.x, y: w.y, width: w.width, height: w.height } : null)
        return true
    }
    function focusWindowById(id) { return UmbrielModel.validId(id) ? root._msg("window-focus", [id]) : false }
    function closeWindowById(id) { return UmbrielModel.validId(id) ? root._msg("window-close", [id]) : false }
    // Outer gaps until umbriel exits: its layout.gap is inner and outer at once, so
    // the struts (which may go negative) make up the difference: outer = gap + strut.
    function setOuterGaps(px) {
        const n = Math.max(0, Math.round(px))
        if (!Number.isFinite(n)) return false
        Quickshell.execDetached(["sh", "-c", 'g=$(umbriel config get layout.gap) || exit 1; case $g in *[!0-9]*|"") exit 1;; esac; '
            + 'for s in top bottom left right; do umbriel config set "layout.struts.$s" "$(($1 - g))"; done', "sh", String(n)])
        return true
    }

    // ── Infinite desktop (services/InfiniteDesktop.qml) ─────────────────────
    // A fresh read each time (the window events may lag a move). Floating windows
    // go anywhere, off screen too (umbriel doesn't clamp); umbriel can't size a
    // window by id, so floated windows keep their size.
    property var _canvasCbs: []
    property var _canvasProc: Process {
        command: ["sh", "-c", 'umbriel windows --json && echo "@@" && umbriel outputs --json']
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("\n@@\n")
                let st = null
                try { st = UmbrielModel.canvas(JSON.parse(parts[0]), JSON.parse(parts[1])) } catch (e) { st = null }
                const cbs = root._canvasCbs; root._canvasCbs = []
                for (const cb of cbs) cb(st)
            }
        }
        onExited: code => { if (code !== 0) { const cbs = root._canvasCbs; root._canvasCbs = []; for (const cb of cbs) cb(null) } }
    }
    function canvasState(cb) {
        root._canvasCbs = root._canvasCbs.concat([cb])
        if (!root._canvasProc.running) root._canvasProc.running = true
        return true
    }
    // Moves run one batch at a time; a newer place for a window replaces a queued one.
    property var _moves: ({})   // id → [x, y, float first (1/0)]
    property var _moveProc: Process { onExited: root._flushMoves() }
    function _flushMoves() {
        if (root._moveProc.running) return
        const ids = Object.keys(root._moves)
        if (!ids.length) return
        const args = []
        for (const id of ids) args.push(id, String(root._moves[id][0]), String(root._moves[id][1]), String(root._moves[id][2] ?? 0))
        root._moves = ({})
        // In order per window: float it (when asked), then move it; every value is an argument.
        root._moveProc.command = ["sh", "-c", 'while [ $# -ge 4 ]; do [ "$4" = 1 ] && umbriel msg window-toggle-floating "$1"; '
            + 'umbriel msg window-move-to top_left "$2" "$3" --window "$1"; shift 4; done', "sh"].concat(args)
        root._moveProc.running = true
    }
    function placeWindows(list) {
        const m = Object.assign({}, root._moves)
        for (const p of list) if (UmbrielModel.validId(String(p.id))) m[p.id] = [Math.round(p.x), Math.round(p.y), (p.float || m[p.id]?.[2]) ? 1 : 0]
        root._moves = m
        root._flushMoves()
        return true
    }
    function _isFloating(id) { return !!(root._windows.find(w => String(w.id) === String(id))?.floating) }
    function floatWindows(rects) {
        return root.placeWindows(rects.map(r => ({ id: r.id, x: r.x, y: r.y, float: !root._isFloating(r.id) })))
    }
    function tileWindows(ids) {
        for (const id of ids) if (UmbrielModel.validId(String(id)) && root._isFloating(id)) root._msg("window-toggle-floating", [id])
        return true
    }
    // umbriel moves only the focused window: focus it, then move it (in order,
    // one shell; the id and number are arguments, not script text).
    function moveWindowToWorkspaceById(id, number) {
        const n = Math.round(number)
        if (!UmbrielModel.validId(id) || n < 1) return false
        Quickshell.execDetached(["sh", "-c", 'umbriel msg window-focus "$1" && umbriel msg window-move-to-workspace-silent "$2"', "sh", id, String(n)])
        return true
    }
    // Dropdown terminal (services/DropTerminal.qml): the "anodrop" scratchpad
    // (external/umbriel/ano.toml gives ano.dropterm to it). Shown: revealed
    // and focused, resized by the difference to r (umbriel resizes the focused
    // float by fractions of the working area) and anchored to `side`. The
    // three run in order in one process; the values are arguments, never
    // spliced into the script.
    // The raw entry (the window list leaves hidden scratchpad windows out).
    function _dropRaw(id, appId) { return root._windows.find(w => String(w.id) === String(id)) ?? root._windows.find(w => appId && w.app_id === appId) ?? null }
    function showWindowAt(id, r, side, appId) {
        const raw = root._dropRaw(id, appId)
        id = raw ? String(raw.id) : id
        if (!UmbrielModel.validId(id) || !r) return false
        const w = raw ? { width: raw.w, height: raw.h } : null
        const aw = r.screen.width - r.reserved[0] - r.reserved[2], ah = r.screen.height - r.reserved[1] - r.reserved[3]
        const frac = v => (Number.isFinite(v) ? v : 0).toFixed(4)
        const dw = w && aw > 0 ? frac((r.width - w.width) / aw) : "0", dh = w && ah > 0 ? frac((r.height - w.height) / ah) : "0"
        const anchor = ({ top: "top", bottom: "bottom", left: "left", right: "right" })[side] ?? "center"
        Quickshell.execDetached(["sh", "-c",
            'umbriel msg window-focus "$1" && umbriel msg window-modify-width-right "$2"; umbriel msg window-modify-height-down "$3"; umbriel msg window-move-to "$4" 0 0 --window "$1"',
            "sh", id, dw, dh, anchor])
        return true
    }
    // The toggle would show a hidden one, so only when it is shown.
    function hideWindow(id, side, appId) {
        const raw = root._dropRaw(id, appId)
        if (!raw || !UmbrielModel.validId(String(raw.id))) return false
        return raw.visible ? root._msg("scratchpad-toggle", ["anodrop"]) : true
    }
}
