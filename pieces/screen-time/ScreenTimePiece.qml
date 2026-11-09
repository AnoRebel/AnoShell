import QtQuick
import qs.modules.sidebarRight

// Bundled piece: the sidebar's screen time card (services/ScreenTime via
// anod): today's total and the top apps as bars, as many as fit, and the
// last 7 days when tall enough. Refreshes only while the desktop can be seen.
Item {
    id: root
    property var ctx
    property var settings: ({})
    clip: true

    ScreenTimeCard {
        id: card
        readonly property real appRow: 35  // name line, bar and spacing
        width: root.width
        color: "transparent"
        live: root.ctx?.live ?? false
        showWeek: (root.settings?.week ?? true) && root.height >= 260
        maxApps: Math.max(1, Math.floor((root.height - 52 - (card.showWeek ? 72 : 0)) / card.appRow))
    }
}
