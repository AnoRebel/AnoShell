pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Anti-Flashbang Shader Service (backends with supports.screenShader).
 * Applies a GLSL shader that darkens bright screens to prevent eye strain at night.
 * Ported from end-4/ii.
 */
Singleton {
    id: root

    readonly property string shaderPath: Quickshell.shellPath("services/antiFlashbang/anti-flashbang.glsl")
    property bool enabled: false

    // (The old `hyprctl keyword` calls are rejected by Hyprland's Lua config.)
    function enable(): void {
        if (ScreenFilters.mode !== "none") ScreenFilters.set("none"); // one screen shader at a time
        if (CompositorService.setScreenShader(root.shaderPath)) root.enabled = true;
        else console.warn(`[AntiFlashbang] not available on ${CompositorService.compositor}: it has no screen shader`);
    }

    function disable(): void {
        CompositorService.setScreenShader("");
        root.enabled = false;
    }

    function toggle(): void {
        if (root.enabled) disable();
        else enable();
    }

    IpcHandler {
        target: "antiFlashbang"
        function toggle(): void { root.toggle() }
        function enable(): void { root.enable() }
        function disable(): void { root.disable() }
    }
}
