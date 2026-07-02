import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * ConnectedBackground — rounded screen frame.
 *
 * One full-screen, click-through, bottom-layer window per screen that rounds off
 * the four OUTER screen corners, so the desktop reads as living inside a rounded
 * frame — the base of the "flows from one shell" look. Uses the proven
 * RoundCorner widget (a filled square minus a quarter-circle) at each corner
 * rather than hand-drawn Shape paths.
 *
 * Opt-in via appearance.connectedCorners.enable. Excluded from compositor blur
 * (see the connectedBg layer rule) so only the corner pieces show.
 *
 * Panels (bar/sidebars/popups) connecting concavely into this frame is the next
 * layer; for now the panels keep their own backgrounds.
 */
Scope {
    id: root

    readonly property bool enabled: Config.options?.appearance?.connectedCorners?.enable ?? false
    readonly property int radius: Math.max(1, Config.options?.appearance?.connectedCorners?.radius ?? 18)
    // Match the screen-edge to the wallpaper-derived shadow/frame tone. Using a
    // near-black keeps corners subtle; colLayer0 ties it to the shell surface.
    readonly property color frameColor: Appearance?.colors.colLayer0 ?? "#1C1B1F"

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            WlrLayershell.namespace: "quickshell:connectedBg"
            // MUST be Top (above the wallpaper AND windows) — on Bottom the
            // corners render behind the wallpaper and are invisible. Noctalia's
            // MainScreen and caelestia's ContentWindow both draw their corners on
            // WlrLayer.Top with ExclusionMode.Ignore + all-4 anchors to span the
            // whole screen. NOTE: while a legacy bar (e.g. waybar) is running it
            // reserves top space and this window is pushed down; in the real ano
            // setup nothing reserves that space (ano's bar uses Ignore too), so
            // this spans the full output and reaches the screen corners.
            WlrLayershell.layer: WlrLayer.Top
            exclusiveZone: 0
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region {} // fully click-through — decorative only

            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.enabled

            RoundCorner {
                anchors.top: parent.top
                anchors.left: parent.left
                implicitSize: root.radius
                color: root.frameColor
                corner: RoundCorner.CornerEnum.TopLeft
            }
            RoundCorner {
                anchors.top: parent.top
                anchors.right: parent.right
                implicitSize: root.radius
                color: root.frameColor
                corner: RoundCorner.CornerEnum.TopRight
            }
            RoundCorner {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                implicitSize: root.radius
                color: root.frameColor
                corner: RoundCorner.CornerEnum.BottomLeft
            }
            RoundCorner {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                implicitSize: root.radius
                color: root.frameColor
                corner: RoundCorner.CornerEnum.BottomRight
            }
        }
    }
}
