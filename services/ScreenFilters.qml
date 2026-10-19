pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Eye-care screen filters (backends with supports.screenShader, Hyprland
 * today): grayscale, sepia, high contrast, and protan/deutan/tritan colour
 * correction. One screen shader at a time, so it takes over from the
 * anti-flashbang shader and back. The choice is kept (screenFilter.mode) and
 * re-applied on start; the shader is cleared when the shell exits.
 *
 *   qs -c ano ipc call screenFilter set sepia   (none to clear)
 */
Singleton {
    id: root
    readonly property var modes: [
        { id: "none", label: "None", icon: "visibility" },
        { id: "grayscale", label: "Grayscale", icon: "filter_b_and_w" },
        { id: "sepia", label: "Sepia", icon: "photo_filter" },
        { id: "high-contrast", label: "High contrast", icon: "contrast" },
        { id: "protan", label: "Protan", icon: "palette" },
        { id: "deutan", label: "Deutan", icon: "palette" },
        { id: "tritan", label: "Tritan", icon: "palette" }
    ]
    readonly property bool supported: CompositorService.supports?.screenShader ?? false
    readonly property string mode: Config.options?.screenFilter?.mode ?? "none"
    property string _applied: ""
    // Last real filter, for the quick toggle.
    readonly property string lastMode: Config.options?.screenFilter?.last ?? "grayscale"

    function set(m) {
        if (!root.modes.some(x => x.id === m)) return
        if (m !== "none") Config.setNestedValue("screenFilter.last", m)
        Config.setNestedValue("screenFilter.mode", m)
    }
    function toggle() { root.set(root.mode === "none" ? root.lastMode : "none") }

    function _apply() {
        if (!root.supported || !Config.ready) return
        if (root.mode === "none") {
            if (root._applied !== "" && !AntiFlashbang.enabled) CompositorService.setScreenShader("")
            root._applied = ""
            return
        }
        if (AntiFlashbang.enabled) AntiFlashbang.enabled = false // one screen shader at a time
        if (CompositorService.setScreenShader(Quickshell.shellPath(`services/screenFilters/${root.mode}.glsl`)))
            root._applied = root.mode
    }
    onModeChanged: _apply()
    Connections { target: Config; function onReadyChanged() { root._apply() } }
    Component.onCompleted: _apply()
    // Never leave a filter on the screen after the shell is gone.
    Component.onDestruction: if (root._applied !== "") CompositorService.setScreenShader("")

    IpcHandler {
        target: "screenFilter"
        function set(mode: string): void { root.set(mode) }
        function toggle(): void { root.toggle() }
    }
}
