import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.shapes
import "root:modules/common/widgets/shapes/material-shapes.js" as MaterialShapes
import "root:modules/common/widgets/shapes/shapes/corner-rounding.js" as CornerRounding
import "root:modules/common/widgets/shapes/geometry/offset.js" as Offset
import qs.services

/**
 * BarWidgetPopout — A bar module wrapper that, when clicked, expands
 * a morphing popout panel below/above the bar widget.
 *
 * This creates the hefty-hype-style effect where clicking a bar module
 * (e.g., system resources) makes a larger details panel grow seamlessly
 * out of the bar background.
 *
 * The popout uses ShapeCanvas to render a polygon that morphs from
 * a simple rectangle (the bar widget bounds) to a larger rectangle with
 * the popout area included.
 *
 * Configurable:
 *   - popupContentWidth/Height: size of the expanded popout area
 *   - collapsedRadius / expandedRadius: corner rounding in each state
 *   - morphDuration: animation duration for the shape morph
 *
 * Usage:
 *   BarWidgetPopout {
 *       popupContentWidth: 300; popupContentHeight: 200
 *       barContent: RowLayout { ... }   // what shows in the bar
 *       popoutContent: ColumnLayout { ... } // what shows when expanded
 *   }
 */
Item {
    id: root

    property bool showPopout: false
    property bool vertical: false
    property bool atBottom: false

    // Sizing
    property real popupContentWidth: 280
    property real popupContentHeight: 200
    property real collapsedRadius: Appearance?.rounding.small ?? 8
    property real expandedRadius: Appearance?.rounding.normal ?? 12
    property int morphDuration: Appearance?.animation.elementMoveEnter?.duration ?? 350

    // Content slots
    property alias barContent: barContentContainer.data
    property alias popoutContent: popoutContentContainer.data

    // Internal
    implicitWidth: barContentContainer.implicitWidth
    implicitHeight: barContentContainer.implicitHeight

    // NOTE: this component is currently UNUSED — every bar module goes through
    // BarModulePopout, which implements its own morph inline. Fixes made here
    // (stretchToFill, borderWidth) must be mirrored there to have any effect.

    // Bar content (always visible)
    Item {
        id: barContentContainer
        anchors.fill: parent

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.showPopout = !root.showPopout
        }
    }

    // Shape background that morphs between collapsed → expanded
    ShapeCanvas {
        id: morphShape
        visible: root.showPopout
        z: 100

        // Position relative to bar widget
        x: -(root.popupContentWidth - root.width) / 2
        y: root.atBottom ? -(root.popupContentHeight + 8) : root.height + 8
        width: root.popupContentWidth
        height: root.popupContentHeight

        color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
        // No border: the polygon is drawn in normalized (0..1) space and then
        // scaled up by the canvas transform, so a stroke is scaled too — the
        // hairline 0.002 became a soft, uneven outline around the popout rather
        // than a crisp 1px edge. The fill alone reads cleanly.
        borderWidth: 0

        // The polygon below is a normalized unit RECTANGLE meant to cover this
        // whole canvas, so it must stretch per-axis. With the default uniform
        // min(w,h) scaling it drew a 200×200 square inside the 280×200 surface,
        // leaving an ~80px transparent strip that the compositor blurred into the
        // halo around the popout.
        stretchToFill: true

        // Morphing polygon
        roundedPolygon: {
            const r = root.expandedRadius / Math.max(root.popupContentWidth, root.popupContentHeight)
            return MaterialShapes.customPolygon([
                new MaterialShapes.PointNRound(new Offset.Offset(1, 1), new CornerRounding.CornerRounding(r)),
                new MaterialShapes.PointNRound(new Offset.Offset(0, 1), new CornerRounding.CornerRounding(r)),
                new MaterialShapes.PointNRound(new Offset.Offset(0, 0), new CornerRounding.CornerRounding(r)),
                new MaterialShapes.PointNRound(new Offset.Offset(1, 0), new CornerRounding.CornerRounding(r)),
            ], 1)
        }

        animation: NumberAnimation {
            duration: root.morphDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: [0.42, 1.67, 0.21, 0.90, 1, 1] // M3 Expressive fast spatial
        }

        // Scale entry/exit — grows from the bar edge the popout hangs off (top for
        // a top bar, bottom for a bottom bar), with the same expressive spatial
        // spring the sidebars use, so the popout feels like it springs out of the
        // bar rather than fading in place.
        opacity: root.showPopout ? 1 : 0
        scale: root.showPopout ? 1 : 0.85
        transformOrigin: root.atBottom ? Item.Bottom : Item.Top

        Behavior on opacity {
            NumberAnimation {
                duration: (Appearance?.animationCurves.expressiveEffectsDuration ?? 200) * (Appearance?.animSpeedMultiplier ?? 1)
                easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: (Appearance?.animationCurves.expressiveFastSpatialDuration ?? 350) * (Appearance?.animSpeedMultiplier ?? 1)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance?.animationCurves.expressiveFastSpatial ?? [0.42, 1.67, 0.21, 0.90, 1, 1]
            }
        }

        // Popout content (only visible when expanded)
        Item {
            id: popoutContentContainer
            anchors { fill: parent; margins: 12 }
            visible: root.showPopout
            opacity: root.showPopout ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: root.morphDuration * 0.6; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
        }
    }

    // Close when clicking outside
    Connections {
        target: GlobalStates
        function onSidebarLeftOpenChanged() { if (GlobalStates.sidebarLeftOpen) root.showPopout = false }
        function onSidebarRightOpenChanged() { if (GlobalStates.sidebarRightOpen) root.showPopout = false }
        function onOverviewOpenChanged() { if (GlobalStates.overviewOpen) root.showPopout = false }
    }
}
