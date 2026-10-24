pragma ComponentBehavior: Bound
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

// The whole deck in one line: a segment per wallpaper in its source colour
// (sorted by hue, a spectrum), a bracket round the cards in hand, ticks over
// the favourites and a dot under the wallpaper on screen. Hover for a glimpse
// of any wallpaper; click or drag to go there.
// From wallpaperpicker's SpectrumRibbon.qml; the track is one Canvas rather
// than a Rectangle per wallpaper, so a 2,000-image folder costs one item.
Item {
    id: ribbon

    property var colors: []        // one hex per wallpaper ("" while unread)
    property var favourites: []    // indexes
    property real pos: 0           // the deck's position (fractional while it moves)
    property int span: 7           // cards shown each side of the front one
    property int activeIndex: -1   // the wallpaper on screen
    property real u: 1
    property color accent: Appearance.colors.colPrimary
    property color ink: Appearance.colors.colOnSurface
    // For the glimpse, asked only for the wallpaper under the pointer.
    property var thumbAt: index => ""
    property var nameAt: index => ""

    readonly property int count: colors.length
    readonly property real seg: count > 0 ? width / count : 0
    readonly property bool active: mouse.containsMouse || mouse.pressed

    signal scrub(real index)
    signal settle(int index)

    implicitHeight: 26 * u

    Canvas {
        id: track
        width: parent.width
        height: (ribbon.active ? 12 : 8) * ribbon.u
        anchors.verticalCenter: parent.verticalCenter
        Behavior on height { NumberAnimation { duration: AnimationConfig.scaledDuration(160); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
        onHeightChanged: requestPaint()
        onWidthChanged: requestPaint()
        Connections {
            target: ribbon
            function onColorsChanged() { track.requestPaint() }
            function onFavouritesChanged() { track.requestPaint() }
        }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const n = ribbon.count
            if (n === 0) return
            const r = height / 2, seg = width / n
            ctx.save()
            ctx.beginPath()
            ctx.roundedRect(0, 0, width, height, r, r)
            ctx.clip()
            const blank = Qt.rgba(ribbon.ink.r, ribbon.ink.g, ribbon.ink.b, 0.14)
            for (let i = 0; i < n; i++) {
                const c = ribbon.colors[i]
                ctx.fillStyle = c ? c : blank
                ctx.fillRect(Math.floor(i * seg), 0, Math.ceil(seg) + 1, height) // a hair wider: no seams
            }
            ctx.restore()
        }
    }

    // Favourites: ticks over the track.
    Repeater {
        model: ribbon.favourites
        Rectangle {
            required property int modelData
            x: (modelData + 0.5) * ribbon.seg - width / 2
            y: track.y - 5 * ribbon.u
            width: Math.max(2, Math.min(ribbon.seg - 1, 3 * ribbon.u))
            height: 3 * ribbon.u
            radius: width / 2
            color: Appearance.colors.colError
        }
    }

    // The wallpaper on screen: a dot under the track.
    Rectangle {
        visible: ribbon.activeIndex >= 0
        x: (ribbon.activeIndex + 0.5) * ribbon.seg - width / 2
        y: track.y + track.height + 3 * ribbon.u
        width: 4 * ribbon.u; height: width; radius: width / 2
        color: ribbon.ink
    }

    // The cards in hand.
    Rectangle {
        readonly property real from: Math.max(0, ribbon.pos - ribbon.span)
        readonly property real to: Math.min(ribbon.count, ribbon.pos + ribbon.span + 1)
        visible: ribbon.count > 0
        x: from * ribbon.seg - 3 * ribbon.u
        width: Math.max(6 * ribbon.u, (to - from) * ribbon.seg + 6 * ribbon.u)
        y: track.y - 4 * ribbon.u
        height: track.height + 8 * ribbon.u
        radius: (Appearance?.rounding.verysmall ?? 8) * 0.6 * ribbon.u
        color: "transparent"
        border.width: Math.max(1, 1.3 * ribbon.u)
        border.color: Qt.rgba(ribbon.ink.r, ribbon.ink.g, ribbon.ink.b, 0.55)
    }

    // The card in front.
    Rectangle {
        visible: ribbon.count > 0
        x: (ribbon.pos + 0.5) * ribbon.seg - width / 2
        y: track.y - 6 * ribbon.u
        width: Math.max(3 * ribbon.u, Math.min(ribbon.seg, 6 * ribbon.u))
        height: track.height + 12 * ribbon.u
        radius: width / 2
        color: ribbon.accent
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.35)
    }

    MouseArea {
        id: mouse
        readonly property int at: ribbon.count > 0 ? Math.max(0, Math.min(ribbon.count - 1, Math.floor(mouseX / ribbon.seg))) : -1
        anchors.fill: parent
        anchors.topMargin: -6 * ribbon.u
        anchors.bottomMargin: -6 * ribbon.u
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: mouse => ribbon.scrub(Math.max(0, Math.min(ribbon.count - 1, mouse.x / ribbon.seg - 0.5)))
        onPositionChanged: mouse => { if (pressed) ribbon.scrub(Math.max(0, Math.min(ribbon.count - 1, mouse.x / ribbon.seg - 0.5))) }
        onReleased: ribbon.settle(at)
    }

    // A glimpse of the wallpaper under the pointer.
    Rectangle {
        id: glimpse
        readonly property int index: mouse.at
        property string shown: ""        // follows the pointer once it slows down
        visible: mouse.containsMouse && !mouse.pressed && index >= 0
        x: Math.max(0, Math.min(ribbon.width - width, mouse.mouseX - width / 2))
        y: ribbon.height + 8 * ribbon.u
        width: 176 * ribbon.u
        height: glimpseCol.implicitHeight + 12 * ribbon.u
        radius: (Appearance?.rounding.small ?? 12) * ribbon.u
        color: Appearance.colors.colSurfaceContainerLow
        border.width: 1
        border.color: Qt.rgba(ribbon.ink.r, ribbon.ink.g, ribbon.ink.b, 0.16)
        onIndexChanged: glimpseTimer.restart()
        onVisibleChanged: if (visible) glimpseTimer.restart()

        Timer {
            id: glimpseTimer
            interval: 70
            onTriggered: glimpse.shown = glimpse.index >= 0 ? ribbon.thumbAt(glimpse.index) : ""
        }

        Column {
            id: glimpseCol
            x: 6 * ribbon.u; y: 6 * ribbon.u
            width: parent.width - 12 * ribbon.u
            spacing: 5 * ribbon.u

            Rectangle {
                id: glimpseFrame
                width: parent.width
                height: Math.round(width * 10 / 16)
                radius: (Appearance?.rounding.verysmall ?? 8) * ribbon.u
                clip: true
                color: glimpse.index >= 0 && ribbon.colors[glimpse.index] ? ribbon.colors[glimpse.index] : Appearance.colors.colSurfaceContainerHigh
                Image {
                    anchors.fill: parent
                    source: glimpse.shown
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(width * 1.25, height * 1.25)
                    asynchronous: true
                    smooth: true
                }
                // Rounds the picture's corners (see DeckCard).
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -border.width
                    radius: glimpseFrame.radius + border.width
                    color: "transparent"
                    border.width: 4 * ribbon.u
                    border.color: glimpse.color
                }
            }
            StyledText {
                width: parent.width
                text: glimpse.index >= 0 ? (glimpse.index + 1) + "  ·  " + ribbon.nameAt(glimpse.index) : ""
                elide: Text.ElideMiddle
                font.pixelSize: (Appearance?.font.pixelSize.smaller ?? 12) * 0.92 * ribbon.u
                color: Appearance.colors.colOnSurface
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
