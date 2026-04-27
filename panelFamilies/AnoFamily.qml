import QtQuick
import Quickshell
import "root:modules/common"
import "root:services"

/**
 * Ano Family (Full) — The default experience.
 * Everything enabled: bar, dock, sidebars, HUD, AI chat, overview,
 * clipboard, hot corners, all overlays.
 */
Scope {
    id: family

    // ─── Core Panels ─────────────────────────────────────────────────────
    PanelLoader { component: Loader { source: "root:modules/bar/BarManager.qml" } }
    PanelLoader { component: Loader { source: "root:modules/overview/AnoView.qml" } }
    PanelLoader { component: Loader { source: "root:modules/notificationPopup/NotificationPopup.qml" } }
    PanelLoader { component: Loader { source: "root:modules/osd/OSD.qml" } }
    PanelLoader { component: Loader { source: "root:modules/session/SessionScreen.qml" } }

    // ─── Sidebars ────────────────────────────────────────────────────────
    PanelLoader { component: Loader { source: "root:modules/sidebarLeft/SidebarLeft.qml" } }
    PanelLoader { component: Loader { source: "root:modules/sidebarRight/SidebarRight.qml" } }

    // ─── Overlays ────────────────────────────────────────────────────────
    PanelLoader { component: Loader { source: "root:modules/wallpaperSelector/WallpaperSelector.qml" } }
    PanelLoader { component: Loader { source: "root:modules/cheatsheet/Cheatsheet.qml" } }
    PanelLoader { component: Loader { source: "root:modules/settings/SettingsOverlay.qml" } }
    PanelLoader { component: Loader { source: "root:modules/clipboard/ClipboardManager.qml" } }
    PanelLoader { component: Loader { source: "root:modules/altSwitcher/AltSwitcher.qml" } }
    PanelLoader { component: Loader { source: "root:modules/search/Search.qml" } }
    PanelLoader { component: Loader { source: "root:modules/taskView/TaskView.qml" } }
    PanelLoader { component: Loader { source: "root:modules/mediaControls/MediaControls.qml" } }
    PanelLoader { component: Loader { source: "root:modules/controlPanel/ControlPanel.qml" } }
    PanelLoader { component: Loader { source: "root:modules/weather/WeatherPanel.qml" } }
    PanelLoader { component: Loader { source: "root:modules/hud/HUD.qml" } }
    PanelLoader { component: Loader { source: "root:modules/focusTime/FocusTimePanel.qml" } }
    PanelLoader { component: Loader { source: "root:modules/displayManager/DisplayManager.qml" } }

    // ─── Conditional ─────────────────────────────────────────────────────
    PanelLoader { extraCondition: Config.options?.dock?.enable ?? true; component: Loader { source: "root:modules/dock/Dock.qml" } }
    PanelLoader { extraCondition: Config.options?.screenCorners?.enable ?? false; component: Loader { source: "root:modules/screenCorners/ScreenCorners.qml" } }
    PanelLoader { extraCondition: Config.options?.anoSpot?.enable ?? false; component: Loader { source: "root:modules/anoSpot/AnoSpot.qml" } }
    PanelLoader { extraCondition: Config.options?.anoSpot?.enable ?? false; component: Loader { source: "root:modules/anoSpot/AnoSpotStashPopout.qml" } }
    PanelLoader { extraCondition: CompositorService.compositor === "niri"; component: Loader { source: "root:modules/lock/LockScreen.qml" } }
    PanelLoader { extraCondition: Config.options?.bar?.morphingPanels ?? false; component: Loader { source: "root:modules/common/widgets/TopLayerPanel.qml" } }

    // ─── Transition ──────────────────────────────────────────────────────
    PanelLoader {
        component: Loader {
            source: "root:modules/common/FamilyTransitionOverlay.qml"
            onLoaded: {
                // Wire transition signals back to shell.qml via IPC
                item.exitComplete.connect(() => {
                    Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "shell", "_applyPending"])
                })
                item.enterComplete.connect(() => {
                    Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "shell", "_finishTransition"])
                })
            }
        }
    }
}
