import QtQuick
import Quickshell
import "root:modules/common"
import "root:services"

/**
 * Clean Family — Focused middle ground.
 * Bar + sidebars + essentials. No dock, no hot corners, no HUD.
 * For distraction-free work.
 */
Scope {
    id: family

    // Disable morphing on activation
    Component.onCompleted: Config.setNestedValue("bar.morphingPanels", false)

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
    PanelLoader { component: Loader { source: "root:modules/settings/SettingsOverlay.qml" } }
    PanelLoader { component: Loader { source: "root:modules/clipboard/ClipboardManager.qml" } }
    PanelLoader { component: Loader { source: "root:modules/search/Search.qml" } }
    PanelLoader { component: Loader { source: "root:modules/altSwitcher/AltSwitcher.qml" } }
    PanelLoader { component: Loader { source: "root:modules/cheatsheet/Cheatsheet.qml" } }

    // ─── Conditional ─────────────────────────────────────────────────────
    PanelLoader { extraCondition: Config.options?.anoSpot?.enable ?? false; component: Loader { source: "root:modules/anoSpot/AnoSpot.qml" } }
    PanelLoader { extraCondition: Config.options?.anoSpot?.enable ?? false; component: Loader { source: "root:modules/anoSpot/AnoSpotStashPopout.qml" } }
    PanelLoader { component: Loader { source: "root:modules/calendar/CalendarPanel.qml" } }
    PanelLoader { extraCondition: CompositorService.compositor === "niri"; component: Loader { source: "root:modules/lock/LockScreen.qml" } }

    // ─── Transition ──────────────────────────────────────────────────────
    PanelLoader { component: Loader { source: "root:modules/common/FamilyTransitionOverlay.qml" } }
}
