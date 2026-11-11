import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.I3
import "SwayModel.js" as SwayModel

/**
 * Sway backend (written against sway 1.12; tested headless, see BackendContract.md).
 *
 * Workspaces come from ext-workspace-v1 like the generic backend (sway has it
 * since 1.12); Quickshell.I3 gives the focused output and runs commands; the
 * tree (which workspaces hold windows, fullscreen, the window list) and the
 * keyboard layouts come from `swaymsg -t get_tree` / `get_inputs`, refreshed
 * on window, workspace and input events. Commands: sway(5), sway-input(5),
 * sway-output(5).
 */
GenericBackend {
    id: root
    experimental: false // tested end to end (docs/compositors.md)

    name: "sway"
    supports: ({
        workspaces: true, perOutputWorkspaces: false, windowCapture: false, blurProtocol: false, layerBlurRules: false,
        outerGaps: true, cursorZoom: false, screenShader: false, dpms: true, outputConfig: false, exit: true,
        keyboardLayouts: true
    })
    focusedOutput: I3.focusedMonitor?.name ?? (Quickshell.screens[0]?.name ?? "")

    // ── Tree ─────────────────────────────────────────────────────────────
    property var _tree: null
    property var _occupied: ({})
    function occupiedOf(e) { return !!e.set.active || !!root._occupied[e.set.name] }
    fullscreenOutputs: root._tree ? SwayModel.fullscreen(root._tree) : ({})
    // Sway has no maximised state: only fullscreen covers an output.
    coveredOutputs: root.fullscreenOutputs
    // A workspace without a leading number has num -1 in the tree: number
    // the windows like the workspace list does (by name, from ext-workspace).
    windows: {
        if (root.windowLeases === 0 || !root._tree) return []
        const numOf = {}
        for (const e of root._sets) numOf[e.set.name] = e.number
        return SwayModel.windows(root._tree).map(w => Object.assign({}, w, { workspace: numOf[w.workspaceName] ?? w.workspace }))
    }

    property bool _treeAgain: false
    property var _treeProc: Process {
        command: ["swaymsg", "-r", "-t", "get_tree"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root._tree = JSON.parse(text)
                    root._occupied = SwayModel.occupied(root._tree)
                    root.revision++
                } catch (e) {}
            }
        }
        onExited: if (root._treeAgain) { root._treeAgain = false; running = true }
    }
    // Bursts of events (a window opening sends several) make one request,
    // 50 ms after the first: a trailing debounce never fired while a title
    // kept changing.
    property var _treeTimer: Timer {
        interval: 50
        onTriggered: { if (root._treeProc.running) root._treeAgain = true; else root._treeProc.running = true }
    }

    // ── Keyboard layouts ─────────────────────────────────────────────────
    function _setLayouts(l) {
        if (!l) return
        root.keyboardLayout = l.current
        if (l.names.length > 0) root.keyboardLayouts = l.names
    }
    property var _inputsProc: Process {
        command: ["swaymsg", "-r", "-t", "get_inputs"]
        stdout: StdioCollector {
            onStreamFinished: { try { root._setLayouts(SwayModel.layouts(JSON.parse(text))) } catch (e) {} }
        }
    }

    property var _events: I3IpcListener {
        subscriptions: ["window", "workspace", "input"]
        onIpcEvent: event => {
            if (event.type === "input") {
                let data = null
                try { data = JSON.parse(event.data) } catch (e) { return }
                const l = SwayModel.layoutsFromEvent(data)
                if (l) root._setLayouts(l)
                else if (data?.change === "added" || data?.change === "removed") root._inputsProc.running = true
            } else {
                // Titles only matter to the window list.
                if (event.type === "window" && root.windowLeases === 0) {
                    let change = ""
                    try { change = JSON.parse(event.data).change } catch (e) {}
                    if (change === "title") return
                }
                if (!root._treeTimer.running) root._treeTimer.start()
            }
        }
    }
    Component.onCompleted: { root._treeProc.running = true; root._inputsProc.running = true }

    // ── Actions ──────────────────────────────────────────────────────────
    function _run(cmd) { I3.dispatch(cmd); return true }
    // Sway numbers workspaces globally; `outputName` doesn't change the number.
    // Through the workspace's ext-workspace handle (a named workspace has no
    // number sway would know); `workspace number N` when there is none.
    function focusWorkspace(number, outputName) {
        const n = Math.round(number)
        const e = root._sets.find(s => s.number === n && (!outputName || s.output === outputName)) ?? root._sets.find(s => s.number === n)
        if (e) { e.set.activate(); return true }
        return root._run(`workspace number ${n}`)
    }
    function focusWorkspaceRelative(delta) { return root._run(delta < 0 ? "workspace prev_on_output" : "workspace next_on_output") }
    function exit() { return root._run("exit") }
    function powerOffMonitors() { return root._run("output * power off") }
    function powerOnMonitors() { return root._run("output * power on") }
    function setOuterGaps(px) { return root._run(`gaps outer all set ${Math.max(0, Math.round(px))}`) }
    function switchKeyboardLayout(delta) { return root._run(`input type:keyboard xkb_switch_layout ${delta < 0 ? "prev" : "next"}`) }
    // From the last tree (refreshed on focus changes); layout coordinates.
    function focusedWindowGeometry(cb) {
        const w = root._tree ? SwayModel.windows(root._tree).find(w => w.focused) : null
        cb(w ? { x: w.x, y: w.y, width: w.width, height: w.height } : null)
        return true
    }
    function focusWindowById(id) { return Number.isInteger(id) ? root._run(`[con_id=${id}] focus`) : false }
    function reservedOf(outputName) { return root._tree ? SwayModel.reserved(root._tree, outputName) : null }
    // Dropdown terminal (services/DropTerminal.qml): sway's scratchpad. By
    // app id: the window list leaves scratchpad windows out, so a hidden one
    // has no id after a reload.
    function _dropCriteria(id, appId) {
        if (/^[\w.-]+$/.test(appId ?? "")) return `[app_id="^${String(appId).replace(/\./g, "\\.")}$"]`
        return Number.isInteger(id) ? `[con_id=${id}]` : ""
    }
    function showWindowAt(id, r, side, appId) {
        const c = root._dropCriteria(id, appId)
        if (!c || !r) return false
        return root._run(`${c} move scratchpad, scratchpad show, resize set width ${Math.round(r.width)} px height ${Math.round(r.height)} px, move absolute position ${Math.round(r.x)} px ${Math.round(r.y)} px, focus`)
    }
    function hideWindow(id, side, appId) { const c = root._dropCriteria(id, appId); return c ? root._run(`${c} move scratchpad`) : false }
    function closeWindowById(id) { return Number.isInteger(id) ? root._run(`[con_id=${id}] kill`) : false }
}
