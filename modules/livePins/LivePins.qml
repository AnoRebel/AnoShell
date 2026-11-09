import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.services

/**
 * Live pins: pick a window, drag over part of it, and that part stays on
 * screen as a live view (above windows or on the desktop). Each pin moves
 * (drag), resizes (corner), flips layer and closes from its hover buttons;
 * a double-click focuses the window it shows. Pins live until closed, the
 * window closes (the pin goes with a notice) or the shell restarts.
 *
 * Capture is window screencopy (CompositorService.supports.windowCapture:
 * Hyprland's toplevel export), one frame every 1/livePins.fps s, paused while
 * pins are hidden or their screen is covered.
 *
 *   qs -c ano ipc call livePins pick|clear|list|toggle
 */
Scope {
    id: root

    readonly property int fps: Math.max(1, Math.min(60, Config.options?.livePins?.fps ?? 10))
    readonly property string defaultLayer: Config.options?.livePins?.layer ?? "top"

    // { toplevel, title, fx, fy, fw, fh (crop, fractions of the window), aspect, screen, x, y, w, layer }
    property var pins: []
    property bool shown: true
    property bool picking: false

    function add(pin) { root.pins = root.pins.concat([pin]); root.shown = true }
    function remove(pin, note) {
        root.pins = root.pins.filter(p => p !== pin)
        if (note) Quickshell.execDetached(["notify-send", "-a", "AnoShell", "--", "Live pin closed", note])
    }

    // A pin whose window is gone closes (its capture has nothing left to show).
    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() {
            const live = ToplevelManager.toplevels.values
            for (const p of root.pins)
                if (!live.includes(p.toplevel)) root.remove(p, `"${p.title}" was closed`)
        }
    }

    IpcHandler {
        target: "livePins"
        function pick(): void { root.picking = true }
        function clear(): void { root.pins = [] }
        function toggle(): void { root.shown = !root.shown }
        function list(): string {
            return JSON.stringify(root.pins.map(p => ({ title: p.title, appId: p.toplevel?.appId ?? "",
                screen: p.screen?.name ?? "", layer: p.layer, x: p.x, y: p.y, width: p.w,
                region: [p.fx, p.fy, p.fw, p.fh].map(v => +v.toFixed(3)) })))
        }
    }

    Variants {
        model: root.pins
        delegate: LivePin {
            fps: root.fps
            shownAll: root.shown
            onCloseRequested: root.remove(modelData, "")
        }
    }

    LazyLoader {
        active: root.picking
        LivePinPicker {
            screen: Quickshell.screens.find(s => s.name === CompositorService.focusedMonitorName) ?? Quickshell.screens[0]
            onCancelled: root.picking = false
            onPicked: pin => {
                pin.layer = root.defaultLayer
                root.add(pin)
                root.picking = false
            }
        }
    }
}
