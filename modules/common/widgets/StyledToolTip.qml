import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell

/**
 * Tooltip for the item it's declared in. Drawn in a popup (xdg_popup), not
 * inside the item's window: a bar or the pill is only as tall as its row, so
 * an in-window ToolTip got pushed back over the icon it described (and took
 * its clicks). The popup goes below the item, or above/beside when the
 * compositor finds no room, and lets clicks through.
 */
Item {
    id: root
    property string text: ""
    property bool extraVisibleCondition: true
    property bool alternativeVisibleCondition: false
    property real horizontalPadding: 10
    property real verticalPadding: 5
    property font font: Qt.font({ family: Appearance.font.family.main, pixelSize: Appearance?.font.pixelSize.smaller ?? 14,
                                  hintingPreference: Font.PreferNoHinting })
    // Gap between the item and the tip.
    property real gap: 4

    // Buttons expose `hovered`, MouseAreas `containsMouse`; only a parent with
    // neither shows the tip unconditionally.
    readonly property bool internalVisibleCondition: (extraVisibleCondition && (parent?.hovered ?? parent?.containsMouse ?? true)) || alternativeVisibleCondition
    // `visible: …` on the tip still hides it, as with the old ToolTip.
    readonly property bool shown: root.visible && root.internalVisibleCondition && root.text !== ""
    width: 0
    height: 0

    Loader {
        active: root.shown && !!root.QsWindow.window
        sourceComponent: PopupWindow {
            visible: true
            anchor {
                window: root.QsWindow.window
                item: root.parent
                edges: Edges.Bottom
                gravity: Edges.Bottom
                adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
            }
            mask: Region { item: null }
            color: "transparent"
            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight + root.gap * 2

            StyledToolTipContent {
                id: content
                anchors.centerIn: parent
                text: root.text
                font: root.font
                horizontalPadding: root.horizontalPadding
                verticalPadding: root.verticalPadding
                shown: false
                Component.onCompleted: shown = true
            }
        }
    }
}
