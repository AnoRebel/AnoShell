import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import "swatches.js" as S

// Bundled piece: the current Material palette (Appearance.m3colors, made
// from the wallpaper), as swatches. Roomy: a row per family (primary,
// secondary, tertiary, surface, error); tight: the key colours. Click one to
// copy its hex (wl-copy); a tick says so. Nothing ticks or polls.
Item {
    id: root
    property var ctx
    property var settings: ({})

    readonly property int gap: 6
    readonly property int minSwatch: 40
    readonly property var rows: S.layout(Math.floor((root.width + root.gap) / (root.minSwatch + root.gap)),
                                         Math.floor((root.height + root.gap) / (root.minSwatch + root.gap)))
    readonly property int perRow: Math.max(1, ...root.rows.map(r => r.length))
    readonly property real swatchW: (root.width - root.gap * (root.perRow - 1)) / root.perRow
    readonly property real swatchH: (root.height - root.gap * (root.rows.length - 1)) / Math.max(1, root.rows.length)
    readonly property bool showHex: (root.settings?.hex ?? true) && root.swatchW >= 68 && root.swatchH >= 30

    property string copied: ""
    Timer { id: copiedTimer; interval: 1200; onTriggered: root.copied = "" }
    function copy(key, hex) {
        Quickshell.execDetached(["wl-copy", "--", hex])
        root.copied = key
        copiedTimer.restart()
    }

    Column {
        spacing: root.gap
        Repeater {
            model: root.rows
            Row {
                id: row
                required property var modelData
                spacing: root.gap
                Repeater {
                    model: row.modelData
                    Rectangle {
                        id: sw
                        required property string modelData
                        readonly property color c: Appearance.m3colors[sw.modelData] ?? "transparent"
                        readonly property string hex: S.hex(sw.c.r, sw.c.g, sw.c.b)
                        readonly property color ink: S.onDark(sw.c.r, sw.c.g, sw.c.b) ? "#ffffff" : "#000000"
                        width: root.swatchW
                        height: root.swatchH
                        radius: Appearance.rounding.small
                        color: sw.c
                        border.width: 1
                        border.color: Qt.rgba(sw.ink.r, sw.ink.g, sw.ink.b, area.containsMouse ? 0.5 : 0.08)

                        StyledText {
                            anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
                            visible: root.showHex && root.copied !== sw.modelData
                            text: sw.hex.toUpperCase()
                            color: sw.ink
                            opacity: 0.75
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                        }
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "check"
                            iconSize: Math.min(22, sw.height * 0.6)
                            color: sw.ink
                            opacity: root.copied === sw.modelData ? 1 : 0
                            scale: root.copied === sw.modelData ? 1 : 0.6
                            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(150) } }
                            Behavior on scale { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.OutBack } }
                        }
                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.copy(sw.modelData, sw.hex)
                            StyledToolTip { text: `${S.label(sw.modelData)} · ${sw.hex} (click to copy)` }
                        }
                    }
                }
            }
        }
    }
}
