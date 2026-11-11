pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.modules.common
import qs.services

/**
 * Dropdown terminal (dropTerminal.*): one terminal window that drops in from a
 * side of the focused screen and goes away again, keeping its session. It is
 * your default terminal (apps.terminal) started with its own window class,
 * ano.dropterm, which needs a terminal that can set one (kitty, foot,
 * Alacritty, Ghostty, WezTerm; see assets/default-apps.json `appId`).
 *
 * Hiding and showing are the compositor's (CompositorService.backend
 * showWindowAt / hideWindow): a special workspace on Hyprland, the scratchpad
 * on sway and umbriel, the empty last workspace on niri. Where the backend
 * has neither, the window is minimized and activated through
 * foreign-toplevel, and stays where the compositor puts it.
 *
 *   qs -c ano ipc call dropTerminal toggle|open|close|status
 */
Singleton {
    id: root

    readonly property string appId: "ano.dropterm"
    readonly property var cfg: Config.options?.dropTerminal ?? ({})
    readonly property string side: cfg.side ?? "top"
    readonly property real widthFraction: Math.max(0.2, Math.min(1, cfg.width ?? 0.75))
    readonly property real heightFraction: Math.max(0.2, Math.min(1, cfg.height ?? 0.6))

    property bool shown: false
    property var _id: null          // the backend's id for the window, once seen
    property bool _launching: false

    readonly property var toplevel: Array.from(ToplevelManager.toplevels?.values ?? []).find(t => t?.appId === root.appId) ?? null
    // Backends list windows only while someone holds a lease.
    readonly property bool _exists: toplevel !== null
    on_ExistsChanged: {
        if (_exists) CompositorService.acquireWindows("dropTerminal")
        else { CompositorService.releaseWindows("dropTerminal"); root._id = null; root.shown = false }
    }

    // The backend id: Hyprland names it from the toplevel itself (hidden
    // windows leave its window list), the others from their window list.
    function _resolveId() {
        const a = root.toplevel?.HyprlandToplevel?.address
        if (a) return `0x${a}`.replace(/^0x0x/, "0x")
        const w = CompositorService.windows.find(w => w.appId === root.appId)
        return w ? w.id : root._id
    }

    // The window's place on the focused screen, in global logical pixels.
    function rect() {
        const name = CompositorService.focusedMonitorName
        const s = Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0]
        if (!s) return null
        // What the compositor reserves (Hyprland, sway), else the probe's free
        // area, counted as reserved right and bottom: niri places floats in
        // that area anyway, so only its size matters there.
        const r = CompositorService.reservedOf(s.name)
            ?? (probe.item && probe.item.screen === s ? [0, 0, s.width - probe.item.width, s.height - probe.item.height] : [0, 0, 0, 0])
        const gap = 8
        const ax = s.x + r[0] + gap, ay = s.y + r[1] + gap
        const aw = s.width - r[0] - r[2] - 2 * gap, ah = s.height - r[1] - r[3] - 2 * gap
        const w = Math.round(aw * root.widthFraction), h = Math.round(ah * root.heightFraction)
        const cx = Math.round(ax + (aw - w) / 2), cy = Math.round(ay + (ah - h) / 2)
        const pos = { top: [cx, ay], bottom: [cx, ay + ah - h], left: [ax, cy], right: [ax + aw - w, cy], center: [cx, cy] }[root.side] ?? [cx, ay]
        return { x: pos[0], y: pos[1], width: w, height: h, screen: s, reserved: r }
    }

    function show() {
        if (!root.toplevel) return root._launch()
        root._id = root._resolveId()
        const b = CompositorService.backend
        if (!b?.showWindowAt?.(root._id, root.rect(), root.side, root.appId)) {
            root.toplevel.minimized = false
            root.toplevel.activate()
        }
        root.shown = true
    }
    function hide() {
        if (!root.toplevel) { root.shown = false; return }
        root._id = root._resolveId()
        const b = CompositorService.backend
        if (!b?.hideWindow?.(root._id, root.side, root.appId)) root.toplevel.minimized = true
        root.shown = false
    }
    // Shown but not focused (another window was clicked): bring it back first.
    function toggle() {
        if (root.shown && root.toplevel && !root.toplevel.activated) return root.show()
        root.shown ? root.hide() : root.show()
    }

    // Start the terminal; it is shown (placed) once its window appears.
    function _launch() {
        if (root._launching) return
        const cmd = DefaultApps.command("terminal")
        const entry = (DefaultApps.catalog.terminal ?? []).find(a => a.command === String(cmd[0] ?? "").split("/").pop())
        if (!cmd.length || !Array.isArray(entry?.appId)) {
            Quickshell.execDetached(["notify-send", "-a", "AnoShell", "Dropdown terminal",
                `${cmd[0] ?? "No terminal"} can't set its window class; pick kitty, foot, Alacritty, Ghostty or WezTerm in Settings → Modules → Default Applications.`])
            return
        }
        const idArgs = entry.appId.map(a => a.replace("{id}", root.appId))
        let run = []
        if ((root.cfg.command ?? "").trim() !== "") {
            run = DefaultApps.terminalArgs(cmd[0], ["-e", "sh", "-c", root.cfg.command])
            if (idArgs[0] === "start" && run[0] === "start") run = run.slice(1) // WezTerm: one `start`
        }
        root._launching = true
        launchTimeout.restart()
        DefaultApps.launch(cmd.concat(idArgs, run))
    }
    Timer { id: launchTimeout; interval: 8000; onTriggered: root._launching = false }
    // The new window: place it. Backends list it a moment after the toplevel.
    Timer {
        id: placeLater
        interval: 150
        onTriggered: { root._launching = false; root.show() }
    }
    Connections {
        target: root
        function onToplevelChanged() { if (root.toplevel && root._launching) placeLater.restart() }
    }

    // The focused screen's free area (the screen less every exclusive zone):
    // an empty, click-through layer anchored to all edges is sized to it.
    // Only where the backend can't say, and only while the terminal exists.
    LazyLoader {
        id: probe
        active: root._exists && CompositorService.reservedOf(CompositorService.focusedMonitorName) === null
        PanelWindow {
            screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:dropProbe"
            color: "transparent"
            mask: Region {}
        }
    }

    IpcHandler {
        target: "dropTerminal"
        function toggle(): void { root.toggle() }
        function open(): void { root.show() }  // not show/hide: `qs ipc call x show` lists x's functions
        function close(): void { root.hide() }
        function status(): string { return root.toplevel ? (root.shown ? "shown" : "hidden") : "closed" }
    }
}
