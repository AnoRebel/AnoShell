import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Right-click menu for a bar group: detach/attach it, run the zone's click
 * action (the centre keeps its old right-click), or open the bar's settings.
 * A click outside dismisses it (grabFocus).
 */
PopupWindow {
    id: root
    property Item anchorItem
    property string barEdge: "top"
    // [{ icon, text, run: function }]
    property var entries: []

    function openAt(item) {
        root.anchorItem = item
        root.visible = true
    }

    grabFocus: true
    color: "transparent"
    implicitWidth: col.implicitWidth + 12
    implicitHeight: col.implicitHeight + 12
    anchor {
        item: root.anchorItem
        edges: root.barEdge === "bottom" ? Edges.Top : root.barEdge === "left" ? Edges.Right
            : root.barEdge === "right" ? Edges.Left : Edges.Bottom
        gravity: anchor.edges
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance?.rounding.normal ?? 12
        color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
        border.width: Appearance.borders.width
        border.color: Appearance.borders.color

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 6 }
            spacing: 2
            Repeater {
                model: root.entries
                RippleButton {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 32
                    buttonRadius: Appearance?.rounding.small ?? 8
                    colBackground: "transparent"
                    onClicked: { root.visible = false; modelData.run() }
                    contentItem: RowLayout {
                        spacing: 8
                        MaterialSymbol { text: modelData.icon; iconSize: 18; Layout.leftMargin: 8 }
                        StyledText { text: modelData.text; Layout.rightMargin: 10 }
                    }
                }
            }
        }
    }
}
