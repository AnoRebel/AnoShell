import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets

// Bundled widget: one picture, or a folder's pictures in turn (crossfading),
// advancing only while ctx.live.
Item {
    id: root
    property var ctx
    property var settings: ({})
    readonly property string path: {
        let p = (root.settings?.path ?? "~/Pictures").trim()
        if (p.startsWith("~")) p = Quickshell.env("HOME") + p.slice(1)
        return p.replace(/\/+$/, "")
    }
    readonly property bool isFile: /\.(jpe?g|png|webp|gif|bmp|avif)$/i.test(root.path)

    FolderListModel {
        id: folder
        folder: !root.isFile && root.path ? `file://${root.path}` : ""
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.avif", "*.bmp", "*.JPG", "*.JPEG", "*.PNG"]
        showDirs: false
    }
    property int index: 0
    function pick() {
        if (folder.count === 0) return ""
        return folder.get(root.index % folder.count, "filePath")
    }
    readonly property string shown: { void root.index; void folder.count; return root.isFile ? root.path : root.pick() }
    Timer {
        running: (root.ctx?.live ?? false) && !root.isFile && folder.count > 1
        interval: Math.max(5, root.settings?.interval ?? 30) * 1000
        repeat: true
        onTriggered: {
            root.index = (root.settings?.shuffle ?? true) ? Math.floor(Math.random() * folder.count) : root.index + 1
        }
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer1
        Image {
            id: back
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: root.width * 1.5; sourceSize.height: root.height * 1.5
        }
        Image {
            id: front
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: root.width * 1.5; sourceSize.height: root.height * 1.5
            source: root.shown ? `file://${root.shown}` : ""
            // the new picture fades in over the previous one
            onSourceChanged: { fade.stop(); opacity = 0 }
            onStatusChanged: if (status === Image.Ready) fade.restart()
            NumberAnimation on opacity { id: fade; to: 1; duration: Appearance.animation.elementMove.duration * 1.5; running: false
                onFinished: back.source = front.source }
        }
        Column {
            anchors.centerIn: parent
            visible: !root.shown
            spacing: 4
            MaterialSymbol { anchors.horizontalCenter: parent.horizontalCenter; text: "photo_library"; iconSize: 32; color: Appearance.colors.colSubtext }
            StyledText { text: "No pictures in " + root.path; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller; width: root.width - 24; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter }
        }
    }
}
