import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.modules.common

/**
 * BarExclusionZone — an invisible, content-less layershell window whose only job
 * is to RESERVE the bar's strip of screen space so tiled windows don't slide
 * under the bar.
 *
 * AnoScreen hosts the bar inside a full-screen ExclusionMode.Ignore window (so it
 * can reach the screen corners), which means that window reserves nothing. This
 * companion window — one per bar, anchored to the bar's edge with a positive
 * exclusiveZone — restores the reservation, exactly like noctalia's
 * BarExclusionZone next to its MainScreen.
 *
 * It draws nothing (transparent, click-through) and matches the bar's thickness
 * + outer margin so the reserved gap equals the bar's footprint.
 */
PanelWindow {
    id: zone

    required property var screenObj      // the target QsScreen
    required property string edge        // "top" | "bottom" | "left" | "right"
    required property real thickness     // bar thickness (px)
    required property real margin        // outer bezel margin (px)
    property bool reserve: true          // false → release the space (e.g. autohide)

    screen: screenObj

    readonly property bool isVertical: edge === "left" || edge === "right"
    readonly property real reservedSize: thickness + margin

    WlrLayershell.namespace: `quickshell:barExclusion:${edge}`
    WlrLayershell.layer: WlrLayer.Bottom
    color: "transparent"
    mask: Region {} // fully click-through — reserves space only

    // Anchor to the bar's edge; hug that one screen side.
    anchors {
        top: edge === "top" || isVertical
        bottom: edge === "bottom" || isVertical
        left: edge === "left" || !isVertical
        right: edge === "right" || !isVertical
    }

    // Only the thickness axis needs a size; the length axis is spanned by the
    // 3-edge anchors above.
    implicitWidth: isVertical ? reservedSize : 0
    implicitHeight: isVertical ? 0 : reservedSize

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: reserve ? reservedSize : 0
}
