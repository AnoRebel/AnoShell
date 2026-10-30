import QtQuick
import Quickshell
import qs.modules.common
import "../../pieces/_bioma"

// Bioma's lock screen (the "gate": a large clock with a minute dial, your
// picture and name, one field), ported from Bioma (GPL-3.0). Gate reads a
// lock state of Bioma's shape; `gate` below is that shape over AnoShell's
// ctx (docs/lockscreens.md): it only draws and calls ctx.submit().
Item {
    id: root
    property var ctx

    QtObject {
        id: gate
        property string active: root.ctx?.screen?.name ?? ""
        property string password: ""
        readonly property bool checking: root.ctx?.busy ?? false
        property bool failed: false
        readonly property string reason: root.ctx?.error || "Wrong password"
        readonly property bool leaving: false
        readonly property string fullName: root.ctx?.user ?? ""
        readonly property url avatar: root.ctx?.avatar ?? ""
        property bool hasAvatar: true
        function avatarFailed() { gate.hasAvatar = false }
        readonly property string wallpaperMode: "fill"
        function wallpaperFor(screenName) { return (root.ctx?.wallpaper ?? "").replace(/^file:\/\//, "") }
        readonly property string density: "normal"
        readonly property bool twentyFourHour: !/a/i.test(Config.options?.time?.format ?? "hh:mm")
        function submit() { if (gate.password.length) root.ctx?.submit(gate.password) }
    }
    Connections {
        target: root.ctx
        // Bioma keeps the wrong password, selected: the next key replaces it.
        function onFailed() { gate.failed = true }
    }

    Rectangle { anchors.fill: parent; color: Theme.background }
    Gate {
        id: g
        gate: gate
        screen: root.ctx?.screen ?? null
        movable: false
    }
    Component.onCompleted: g.focusField()
}
