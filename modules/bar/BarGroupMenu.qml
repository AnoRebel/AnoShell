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
    // [{ icon, text, run: function }], or { header: "text" }, or { separator: true }
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

        // grabFocus gives it the keyboard: Esc closes it (window-wide, whatever has focus).
        Shortcut { sequence: "Escape"; enabled: root.visible; onActivated: root.visible = false }
        ColumnLayout {
            id: col
            anchors { fill: parent; margins: 6 }
            spacing: 2
            Repeater {
                model: root.entries.filter(e => e.header !== undefined)
                StyledText {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.margins: 8
                    Layout.bottomMargin: 2
                    text: modelData.header
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.maximumWidth: 260
                }
            }
            Repeater {
                model: root.entries.filter(e => e.header === undefined)
                Item {
                    id: row
                    required property var modelData
                    readonly property bool separator: !!modelData.separator
                    Layout.fillWidth: true
                    Layout.maximumWidth: 280
                    implicitWidth: row.separator ? 0 : btn.implicitWidth
                    implicitHeight: row.separator ? 9 : 32
                    Rectangle {
                        visible: row.separator
                        anchors.centerIn: parent
                        width: parent.width - 16; height: 1
                        color: Appearance?.colors.colOutlineVariant ?? "#49454F"
                    }
                    RippleButton {
                        id: btn
                        visible: !row.separator
                        anchors.fill: parent
                        buttonRadius: Appearance?.rounding.small ?? 8
                        colBackground: "transparent"
                        onClicked: { root.visible = false; row.modelData.run() }
                        contentItem: RowLayout {
                            spacing: 8
                            MaterialSymbol { text: row.modelData.icon ?? ""; iconSize: 18; Layout.leftMargin: 8 }
                            StyledText { text: row.modelData.text ?? ""; Layout.rightMargin: 10; elide: Text.ElideRight; Layout.maximumWidth: 230; Layout.fillWidth: true; horizontalAlignment: Text.AlignLeft }
                        }
                    }
                }
            }
        }
    }
}
