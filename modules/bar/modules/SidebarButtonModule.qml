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

    // Which bar section this button lives in — set explicitly by BarContent's
    // section loader (onLoaded → barSection = "left"/"right"). This is reliable;
    // the old pixel-X guess resolved before layout settled and made BOTH buttons
    // read "left". Falls back to pixel detection only if barSection is unset.
    property string barSection: ""

    function resolveSide() {
        if (barSection === "left" || barSection === "right") return barSection
        const win = root.QsWindow?.window
        const winW = win?.width ?? win?.screen?.width ?? 0
        if (winW <= 0) return "left"
        const centreX = root.mapToItem(null, root.width / 2, 0).x
        return centreX > winW / 2 ? "right" : "left"
    }
    readonly property string side: (root.barSection, root.x, root.width, resolveSide())

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

    // Tooltip attached to a hover-only overlay that does NOT accept buttons, so
    // it never swallows the click meant for the RippleButton beneath it.
    // (A StyledToolTip as a direct Button child rendered permanently and blocked
    // the button.)
    MouseArea {
        id: ttHover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        StyledToolTip {
            // parent (the MouseArea) has no `hovered`, which would make the tip
            // permanently visible — gate explicitly on containsMouse instead.
            extraVisibleCondition: ttHover.containsMouse
            text: root.side === "right" ? "System panel — quick settings, media, calendar" : "Utility panel — AI chat, notifications, translate"
        }
    }
}
