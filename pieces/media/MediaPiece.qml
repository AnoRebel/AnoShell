import QtQuick
import qs.modules.sidebarRight

// Bundled piece: the sidebar's media card (MprisController), filling the cell.
Item {
    property var ctx
    CompactMediaPlayer { anchors.fill: parent; color: "transparent" }
}
