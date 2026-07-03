import qs.modules.common
import qs.modules.common.widgets
import qs
import qs.services
import QtQuick

/**
 * A small pill button that toggles a sidebar.
 *
 * The same module is used on both the left and right of the bar, so it
 * resolves which sidebar to toggle from its on-screen position: a button
 * left of the screen centre toggles the left sidebar, one right of centre
 * toggles the right sidebar. Falls back to the left sidebar if geometry is
 * not yet resolved.
 */
RippleButton {
    id: root
    implicitWidth: 36
    implicitHeight: 28
    buttonRadius: Appearance?.rounding.full ?? 9999
    colBackground: "transparent"
    colBackgroundHover: Appearance?.colors.colLayer1Hover ?? "#E5DFED"

    // Resolve target side from the button centre's X in screen coordinates.
    readonly property string side: {
        const win = root.QsWindow?.window
        const screenW = win?.screen?.width ?? 0
        if (screenW <= 0)
            return "left"
        const centreX = root.mapToItem(null, root.width / 2, 0).x
        return centreX > screenW / 2 ? "right" : "left"
    }

    releaseAction: () => {
        if (root.side === "right")
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen
        else
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen
    }

    // Distinct icon per side so the two buttons don't look like a duplicated
    // "more" menu: left = utilities/AI panel, right = system/quick-settings.
    contentItem: MaterialSymbol {
        text: root.side === "right" ? "tune" : "space_dashboard"
        iconSize: Appearance?.font.pixelSize.normal ?? 18
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
    }

    StyledToolTip {
        text: root.side === "right" ? "System panel — quick settings, media, calendar" : "Utility panel — AI chat, notifications, translate"
    }
}
