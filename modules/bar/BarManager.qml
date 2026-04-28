import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.services

/**
 * BarManager — Creates and manages N bars per monitor.
 * Reads bar definitions from config.json "bars" array.
 * Each bar can be on any edge (top/bottom/left/right) and has its own module set.
 * Falls back to a single default bar if no "bars" array is configured.
 */
Scope {
    id: root

    // Default bar definition when no explicit bars are configured
    readonly property var defaultBars: [{
        "id": "main",
        "edge": "top",
        "modules": {
            "left": ["sidebarButton", "activeWindow"],
            "center": ["workspaces"],
            "right": ["clock", "battery", "network", "bluetooth", "tray", "sidebarButton"]
        },
        "autoHide": false,
        "showBackground": true
    }]

    readonly property var barDefinitions: Config.options?.bars ?? defaultBars

    // Per-screen bar instances
    Variants {
        model: {
            const screens = Quickshell.screens
            const screenList = Config.options?.bar?.screenList ?? []
            if (!screenList || screenList.length === 0) return screens
            return screens.filter(screen => screenList.includes(screen.name))
        }

        Scope {
            id: screenScope
            required property var modelData

            // Create one BarWindow per bar definition, per screen
            Repeater {
                model: root.barDefinitions

                LazyLoader {
                    id: barLoader
                    required property var modelData
                    required property int index
                    // Skip bars that use morphingPanel — those are rendered by TopLayerPanel
                    active: GlobalStates.barOpen && !GlobalStates.screenLocked && !(barLoader.modelData?.morphingPanel ?? false)

                    component: BarWindow {
                        screen: screenScope.modelData
                        barConfig: barLoader.modelData
                        barIndex: barLoader.index
                    }
                }
            }
        }
    }

    // IPC
    IpcHandler {
        target: "bar"
        function toggle(): void { GlobalStates.barOpen = !GlobalStates.barOpen }
        function close(): void { GlobalStates.barOpen = false }
        function open(): void { GlobalStates.barOpen = true }
    }

    // GlobalShortcuts (Hyprland only)
    Loader {
        active: CompositorService.compositor === "hyprland"
        sourceComponent: Item {
            GlobalShortcut { name: "barToggle"; description: "Toggle bar"; onPressed: GlobalStates.barOpen = !GlobalStates.barOpen }
            GlobalShortcut { name: "barOpen"; description: "Open bar"; onPressed: GlobalStates.barOpen = true }
            GlobalShortcut { name: "barClose"; description: "Close bar"; onPressed: GlobalStates.barOpen = false }
        }
    }
}
