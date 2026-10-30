import QtQuick

// Clock faces from dhrruvsharma's dotfiles (GPL-3.0): the chosen face, drawn
// at its own size and scaled to fit the piece. None shows seconds, so the
// time steps on each minute boundary, only while ctx.live.
Item {
    id: root
    property var ctx
    property var settings: ({})
    readonly property string face: ["Zen", "Plain", "Terminal", "Cosmos"].includes(root.settings?.face) ? root.settings.face : "Zen"

    property date now: new Date()
    Timer {
        running: root.ctx?.live ?? false
        repeat: true
        triggeredOnStart: true
        interval: 60000 - (root.now.getSeconds() * 1000 + root.now.getMilliseconds())
        onTriggered: root.now = new Date()
    }

    Loader {
        id: faceLoader
        anchors.centerIn: parent
        source: `${root.face}Face.qml`
        onLoaded: item.now = Qt.binding(() => root.now)
        // Scaled as a whole (the faces are drawn at one size), never above 1.
        scale: item ? Math.min(1, root.width / Math.max(1, item.implicitWidth), root.height / Math.max(1, item.implicitHeight)) : 1
    }
}
