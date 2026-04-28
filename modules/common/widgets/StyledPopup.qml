import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common

/**
 * Styled popup window anchored to a parent item. Used for bar module
 * hover popups (battery details, network list, etc.)
 * Provides consistent styling: rounded card, shadow, enter/exit animation.
 */
Item {
    id: root
    property bool shown: false
    property real popupWidth: 300
    property real popupHeight: 400
    property real popupMargin: 8
    property var anchorEdges: Edges.Top
    property var anchorGravity: Edges.Top

    default property alias content: contentContainer.data

    Loader {
        id: popupLoader
        active: root.shown
        anchors.fill: parent

        sourceComponent: PopupWindow {
            id: popupWin
            visible: root.shown
            color: "transparent"
            implicitWidth: root.popupWidth + root.popupMargin * 2
            implicitHeight: root.popupHeight + root.popupMargin * 2

            anchor {
                window: root.QsWindow.window
                item: root.parent
                edges: root.anchorEdges
                gravity: root.anchorGravity
            }

            mask: Region { item: cardBg }

            Item {
                anchors { fill: parent; margins: root.popupMargin }

                // Shadow
                Rectangle {
                    id: shadowRect
                    anchors.fill: parent; anchors.margins: -4
                    radius: cardBg.radius + 4
                    color: "#44000000"
                    z: -1
                }

                // Card
                Rectangle {
                    id: cardBg
                    anchors.fill: parent
                    radius: Appearance?.rounding.normal ?? 12
                    color: Appearance?.colors.colLayer0 ?? "#1C1B1F"
                    border.width: 1
                    border.color: Appearance?.colors.colLayer0Border ?? "#44444488"
                    clip: true

                    Item {
                        id: contentContainer
                        anchors { fill: parent; margins: 12 }
                    }
                }

                // Entry animation
                opacity: root.shown ? 1 : 0
                scale: root.shown ? 1 : 0.92
                transformOrigin: Item.Bottom

                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }
        }
    }
}
