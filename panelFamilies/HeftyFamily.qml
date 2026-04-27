import QtQuick
import Quickshell
import "root:modules/common"
import "root:services"

/**
 * Hefty Family — Full experience with morphing bar panels.
 * Bars use polygon ShapeCanvas backgrounds that morph into popout detail panels.
 * This is the hefty-hype-inspired mode.
 *
 * Automatically enables bar.morphingPanels when this family is active.
 * All panels from Ano family are included plus TopLayerPanel for morphing.
 */
Scope {
    id: family

    // Enable morphing on activation
    Component.onCompleted: Config.setNestedValue("bar.morphingPanels", true)

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

    // ─── Hefty-specific: Morphing layer ──────────────────────────────────
    PanelLoader { component: Loader { source: "root:modules/common/widgets/TopLayerPanel.qml" } }

    // ─── Conditional ─────────────────────────────────────────────────────
    PanelLoader { extraCondition: Config.options?.dock?.enable ?? true; component: Loader { source: "root:modules/dock/Dock.qml" } }
    PanelLoader { extraCondition: Config.options?.screenCorners?.enable ?? false; component: Loader { source: "root:modules/screenCorners/ScreenCorners.qml" } }
    PanelLoader { extraCondition: Config.options?.activSpot?.enable ?? false; component: Loader { source: "root:modules/activSpot/ActivSpot.qml" } }
    PanelLoader { extraCondition: CompositorService.compositor === "niri"; component: Loader { source: "root:modules/lock/LockScreen.qml" } }

    // ─── Transition ──────────────────────────────────────────────────────
    PanelLoader { component: Loader { source: "root:modules/common/FamilyTransitionOverlay.qml" } }
}
