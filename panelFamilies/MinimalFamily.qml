import QtQuick
import Quickshell
import "root:modules/common"
import "root:services"

/**
 * Minimal Family — Lightweight shell.
 * Bar + essential overlays only. No dock, no sidebars, no HUD, no hot corners.
 * For users who want a minimal setup or use external tools for sidebars/launchers.
 */
Scope {
    id: family

    // ─── Core Panels ─────────────────────────────────────────────────────
    PanelLoader { component: Loader { source: "root:modules/bar/BarManager.qml" } }
    PanelLoader { component: Loader { source: "root:modules/overview/AnoView.qml" } }
    PanelLoader { component: Loader { source: "root:modules/notificationPopup/NotificationPopup.qml" } }
    PanelLoader { component: Loader { source: "root:modules/osd/OSD.qml" } }
    PanelLoader { component: Loader { source: "root:modules/session/SessionScreen.qml" } }

    // ─── Essential Overlays ──────────────────────────────────────────────
    PanelLoader { component: Loader { source: "root:modules/settings/SettingsOverlay.qml" } }
    PanelLoader { component: Loader { source: "root:modules/search/Search.qml" } }
    PanelLoader { component: Loader { source: "root:modules/altSwitcher/AltSwitcher.qml" } }

    // ─── Conditional ─────────────────────────────────────────────────────
    PanelLoader { extraCondition: CompositorService.compositor === "niri"; component: Loader { source: "root:modules/lock/LockScreen.qml" } }

    // ─── Transition ──────────────────────────────────────────────────────
    PanelLoader { component: Loader { source: "root:modules/common/FamilyTransitionOverlay.qml" } }
}
