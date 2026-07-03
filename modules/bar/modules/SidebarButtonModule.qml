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

    // Resolve which side this button is on from its centre's X, mapped to the
    // window. Computed FRESH on each click (a cached readonly binding resolved
    // before layout settled → both buttons saw x≈0 → both said "left"). Depends
    // on x/width so the icon/tooltip also stay correct after relayout.
    function resolveSide() {
        const win = root.QsWindow?.window
        const winW = win?.width ?? win?.screen?.width ?? 0
        if (winW <= 0) return "left"
        const centreX = root.mapToItem(null, root.width / 2, 0).x
        return centreX > winW / 2 ? "right" : "left"
    }
    readonly property string side: (root.x, root.width, resolveSide())

    releaseAction: () => {
        if (root.resolveSide() === "right")
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
