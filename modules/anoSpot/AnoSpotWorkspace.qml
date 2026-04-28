import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services

RowLayout {
    id: wsRow
    spacing: 4

    visible: Config.options?.anoSpot?.showWorkspace ?? true

    readonly property int wsIndex: CompositorService.activeWorkspaceIndex
    readonly property string wsName: CompositorService.activeWorkspaceName

    MaterialSymbol {
        text: "view_carousel"
        iconSize: 14
        color: Appearance?.colors?.colSecondary ?? "#cba6f7"
    }

    StyledText {
        text: {
            // Show name if non-empty and non-numeric; otherwise the index.
            if (wsRow.wsName && isNaN(parseInt(wsRow.wsName))) return wsRow.wsName;
            return String(wsRow.wsIndex);
        }
        font.pixelSize: 12
        font.weight: Font.Medium
        color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
    }

    // Click on the workspace widget opens AnoView (overview)
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: Quickshell.execDetached(["qs", "-c", "ano", "ipc", "call", "anoview", "toggle"])
    }
}
