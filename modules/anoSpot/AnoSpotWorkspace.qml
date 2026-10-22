import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * The pill's workspace chip: the active workspace's name or number. Click
 * opens AnoView; hovering a moment shows the windows of this screen's
 * workspace (or of every workspace, anoSpot.workspaceHoverPreview.allWorkspaces)
 * as live thumbnails in a popout under the chip; clicking one focuses it.
 */
Item {
    id: wsRow
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    visible: Config.options?.anoSpot?.showWorkspace ?? true

    readonly property int wsIndex: CompositorService.activeWorkspaceIndex
    readonly property string wsName: CompositorService.activeWorkspaceName
    readonly property var _preview: Config.options?.anoSpot?.workspaceHoverPreview
    readonly property bool hoverPreviewEnabled: _preview?.enable ?? true
    readonly property bool allWorkspaces: _preview?.allWorkspaces ?? false
    readonly property string screenName: QsWindow.window?.screen?.name ?? ""

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 4
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
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
            color: Appearance?.colors?.colOnLayer0 ?? "#cdd6f4"
        }
    }

    // Hover dwells openDelayMs before the preview opens (no flicker on passes
    // across the pill); the popout keeps itself open while the pointer travels
    // onto it.
    property bool _open: false
    Timer {
        id: openDelayTimer
        interval: wsRow._preview?.openDelayMs ?? 200
        onTriggered: wsRow._open = wsRow.hoverPreviewEnabled && wsHoverArea.hovered
    }
    HoverHandler {
        id: wsHoverArea
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (hovered) openDelayTimer.restart()
            else { openDelayTimer.stop(); wsRow._open = false }
        }
    }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: { popout.dismiss(); GlobalStates.overviewOpen = !GlobalStates.overviewOpen }
    }

    BarModulePopout {
        id: popout
        shown: wsRow._open
        closeDelay: wsRow._preview?.closeDelayMs ?? 300
        popupWidth: strip.implicitWidth + 24
        popupHeight: strip.implicitHeight + 24
        WindowStrip {
            id: strip
            active: popout.effectiveShown
            maxWidth: (wsRow.QsWindow.window?.screen?.width ?? 1280) * 0.8
            thumbW: wsRow._preview?.thumbnailWidth ?? 180
            thumbH: wsRow._preview?.thumbnailHeight ?? 110
            showWorkspace: wsRow.allWorkspaces
            // Kept as-is while the popout retracts (no "No windows" flash).
            Binding on windows {
                when: strip.active
                restoreMode: Binding.RestoreNone
                value: wsRow.allWorkspaces
                    ? CompositorService.windows.slice().sort((a, b) => a.workspace - b.workspace)
                    : CompositorService.windowsOnOutput(wsRow.screenName)
            }
            onActivated: popout.dismiss()
        }
    }
}
