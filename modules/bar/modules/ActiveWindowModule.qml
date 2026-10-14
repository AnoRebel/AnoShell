import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

/**
 * Active window title bar module.
 */
Item {
    id: root
    // Vertical bars run the title along the bar, rotated, capped in length.
    property bool vertical: false
    implicitWidth: vertical ? title.implicitHeight + 8 : title.implicitWidth
    implicitHeight: vertical ? Math.min(title.implicitWidth, 160) : Appearance.sizes.barHeight
    Layout.fillWidth: !vertical

    readonly property var activeToplevel: ToplevelManager.activeToplevel
    readonly property string windowTitle: activeToplevel?.title ?? ""
    readonly property string appId: activeToplevel?.appId ?? ""

    StyledText {
        id: title
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
        width: Math.min(root.vertical ? root.height : root.width, 300)
        rotation: root.vertical ? (PanelRegistry.windowEdge(root.QsWindow.window) === "right" ? 90 : -90) : 0
        horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
        text: root.windowTitle || root.appId || ""
        // Window titles are arbitrary external strings; render verbatim so a
        // '<' or '<img …>' in a title isn't parsed as HTML (which logs
        // "Invalid base url in img tag").
        textFormat: Text.PlainText
        font.pixelSize: Appearance?.font.pixelSize.small ?? 14
        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
        elide: Text.ElideRight
    }
}
