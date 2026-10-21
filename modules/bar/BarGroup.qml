import qs.modules.common
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import "."

/**
 * A rounded pill container for bar module groups.
 */
Item {
    id: root
    property bool vertical: false
    property real padding: 5
    // Background is configurable so callers tune it via properties instead
    // of injecting a child Rectangle (the default alias routes children into
    // the inner GridLayout, where anchored items are undefined behavior).
    property bool showBackground: true
    property color backgroundColor: Appearance?.colors.colLayer1 ?? "#E5E1EC"
    property real backgroundRadius: Appearance?.rounding.small ?? 8
    property real spacing: 4   // between modules along the bar
    default property alias items: gridLayout.children

    implicitWidth: gridLayout.implicitWidth + padding * 2
    implicitHeight: vertical ? (gridLayout.implicitHeight + padding * 2) : Appearance.sizes.baseBarHeight

    Rectangle {
        anchors {
            fill: parent
            topMargin: root.vertical ? 0 : 4
            bottomMargin: root.vertical ? 0 : 4
            leftMargin: root.vertical ? 4 : 0
            rightMargin: root.vertical ? 4 : 0
        }
        visible: root.showBackground
        color: root.backgroundColor
        radius: root.backgroundRadius
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        // Placed, not anchored: switching anchor sets as `vertical` changes
        // passed through left+right+horizontalCenter at once (a warning each time).
        x: root.vertical ? (root.width - width) / 2 : root.padding
        y: root.vertical ? root.padding : (root.height - height) / 2
        width: root.vertical ? implicitWidth : root.width - root.padding * 2
        height: root.vertical ? root.height - root.padding * 2 : implicitHeight
        columnSpacing: root.spacing
        rowSpacing: root.vertical ? Math.max(root.spacing, 4) : 12
    }
}
