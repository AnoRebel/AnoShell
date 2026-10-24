pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.modules.common
import qs.modules.common.widgets
import "deck.js" as Deck

// One wallpaper as a paint-chip card in the deck: the card wears colours
// made from the wallpaper's source colour (anod palette.scan), its chips the
// tones that colour gives, with their hex codes. A Wallhaven result wears
// the colours Wallhaven reports for the image instead (chips without names).
// Without a palette yet, the card wears the shell's own colours.
// From wallpaperpicker's SwatchCard.qml.
Item {
    id: card

    property var entry: null              // a deck entry (WallpaperDeck.displayed)
    property string picture: ""           // what the card shows (a video's still, not the video)
    property var dress: null              // deck.js dressFrom(), or null for the shell's colours
    property var chips: []                // [{ label, fill }]
    property real u: 1                    // pixels per design pixel
    property real front: 0                // how far this card is in front, 0..1
    property real dim: 0                  // shade over a card further back (lifted on hover)
    property bool current: false          // the wallpaper on screen
    property bool favourite: false
    property bool saved: false            // a Wallhaven result already in the folder
    property real download: -1            // 0..1 while it downloads
    property string title: ""
    property string meta: ""
    // Drawn from a texture over the plain picture: the video playing in the
    // preview, or the preview's sharper image on a card shown large.
    property var art: null
    property real artAspect: 16 / 10
    property real artOpacity: 1
    property real shine: -1               // a band of light across `art` (0..1; -1 none)

    readonly property alias hovered: mouse.containsMouse
    signal clicked
    signal doubleClicked

    readonly property real pad: 9 * u
    readonly property real radius: (Appearance?.rounding.normal ?? 17) * u
    readonly property real thumbRadius: (Appearance?.rounding.small ?? 12) * 0.85 * u
    readonly property real chipHeight: 22 * u
    readonly property rect pictureRect: Qt.rect(thumbBase.x, thumbBase.y, thumbBase.width, thumbBase.height)

    readonly property color colSurface: dress ? dress.surface : Appearance.colors.colSurfaceContainer
    readonly property color colRaised: dress ? dress.raised : Appearance.colors.colSurfaceContainerHigh
    readonly property color colInk: dress ? dress.ink : Appearance.colors.colOnSurface
    readonly property color colMuted: dress ? dress.muted : Appearance.colors.colOnSurfaceVariant
    readonly property color colLine: dress ? dress.line : Appearance.colors.colOutlineVariant
    readonly property color colAccent: dress ? dress.accent : Appearance.colors.colPrimary
    readonly property color colAccentInk: dress ? dress.accentInk : Appearance.colors.colOnPrimary

    function popTag() { pop.restart() }

    implicitWidth: 212 * u
    implicitHeight: pad + Math.round((implicitWidth - pad * 2) * 10 / 16) + 8 * u + chipHeight * 5 + 9 * u
        + titleText.height + 2 * u + metaText.height + pad + 2 * u

    RectangularShadow {
        anchors.fill: body
        offset.y: (8 + 10 * card.front) * card.u
        blur: (22 + 18 * card.front) * card.u
        radius: body.radius
        color: Qt.rgba(0, 0, 0, 0.42 + 0.18 * card.front)
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: card.radius
        antialiasing: true
        color: card.colSurface
        border.width: Math.max(1, card.u * (1 + card.front * 0.6))
        border.color: Qt.tint(Qt.rgba(card.colLine.r, card.colLine.g, card.colLine.b, 0.85),
            Qt.rgba(card.colAccent.r, card.colAccent.g, card.colAccent.b, card.front * 0.85))

        // ── The wallpaper ────────────────────────────────────────────────
        Rectangle {
            id: thumbBase
            x: card.pad; y: card.pad
            width: parent.width - card.pad * 2
            height: Math.round(width * 10 / 16)
            color: card.colRaised
            antialiasing: true
            radius: card.thumbRadius

            MaterialSymbol {
                anchors.centerIn: parent
                visible: thumb.status !== Image.Ready
                text: thumb.status === Image.Error ? "broken_image" : Deck.kind(card.entry?.name ?? "") === "video" && !card.entry?.item ? "movie" : "image"
                iconSize: 22 * card.u
                color: card.colMuted
                opacity: 0.5
            }
        }

        Image {
            id: thumb
            anchors.fill: thumbBase
            source: card.picture
            fillMode: Image.PreserveAspectCrop
            // Room for the card in front, which is drawn larger.
            sourceSize: Qt.size(Math.ceil(thumbBase.width * 1.3), Math.ceil(thumbBase.height * 1.3))
            asynchronous: true
            smooth: true
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(220) } }
        }

        Loader {
            anchors.fill: thumbBase
            active: !!card.art
            visible: card.artOpacity > 0
            opacity: card.artOpacity
            sourceComponent: CardPicture { source: card.art; sourceAspect: card.artAspect; shine: card.shine }
        }

        // Rounds the picture's corners: a frame in the card's colour whose
        // inside edge is the rounded corner (cheaper than a mask).
        Rectangle {
            x: thumbBase.x - border.width; y: thumbBase.y - border.width
            width: thumbBase.width + border.width * 2
            height: thumbBase.height + border.width * 2
            radius: card.thumbRadius + border.width
            antialiasing: true
            color: "transparent"
            border.width: 5 * card.u
            border.color: card.colSurface
        }

        // The wallpaper on screen now.
        Rectangle {
            id: currentTag
            x: thumbBase.x + 7 * card.u
            y: thumbBase.y + thumbBase.height - height - 7 * card.u
            visible: card.current
            width: currentRow.implicitWidth + 12 * card.u
            height: 19 * card.u
            radius: height / 2
            color: card.colAccent
            transformOrigin: Item.Left

            Row {
                id: currentRow
                anchors.centerIn: parent
                spacing: 3 * card.u
                MaterialSymbol { anchors.verticalCenter: parent.verticalCenter; text: "check"; iconSize: 12 * card.u; color: card.colAccentInk }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "current"
                    font.pixelSize: (Appearance?.font.pixelSize.smallest ?? 10) * card.u
                    font.weight: Font.Bold
                    color: card.colAccentInk
                }
            }

            SequentialAnimation {
                id: pop
                NumberAnimation { target: currentTag; property: "scale"; from: 0.4; to: 1.12; duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                NumberAnimation { target: currentTag; property: "scale"; to: 1; duration: AnimationConfig.scaledDuration(160); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.standard }
            }
        }

        Rectangle {
            visible: card.favourite
            x: thumbBase.x + thumbBase.width - width - 6 * card.u
            y: thumbBase.y + 6 * card.u
            width: 24 * card.u; height: width; radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.42)
            MaterialSymbol { anchors.centerIn: parent; text: "favorite"; fill: 1; iconSize: 14 * card.u; color: Appearance.colors.colError }
        }

        Rectangle {
            visible: card.saved
            x: thumbBase.x + thumbBase.width - width - 6 * card.u
            y: thumbBase.y + thumbBase.height - height - 6 * card.u
            width: 24 * card.u; height: width; radius: width / 2
            color: Qt.rgba(0, 0, 0, 0.5)
            MaterialSymbol { anchors.centerIn: parent; text: "download_done"; iconSize: 14 * card.u; color: Qt.rgba(1, 1, 1, 1) }
        }

        // Download progress along the foot of the picture.
        Rectangle {
            visible: card.download >= 0
            x: thumbBase.x
            y: thumbBase.y + thumbBase.height - height
            width: thumbBase.width * Math.max(0.02, card.download)
            height: 3 * card.u
            color: card.colAccent
            Behavior on width { NumberAnimation { duration: AnimationConfig.scaledDuration(200) } }
        }

        // ── The chips ────────────────────────────────────────────────────
        Column {
            id: chipColumn
            x: card.pad
            y: thumbBase.y + thumbBase.height + 8 * card.u
            width: thumbBase.width

            Repeater {
                model: 5
                Rectangle {
                    id: chip
                    required property int index
                    readonly property var spec: card.chips[index] ?? null
                    readonly property real r: card.thumbRadius * 0.7
                    readonly property color ink: spec && Deck.inkOn(spec.fill) === "dark" ? Qt.rgba(0, 0, 0, 0.78) : Qt.rgba(1, 1, 1, 0.9)

                    width: chipColumn.width
                    height: card.chipHeight
                    topLeftRadius: index === 0 ? r : 0
                    topRightRadius: index === 0 ? r : 0
                    bottomLeftRadius: index === 4 ? r : 0
                    bottomRightRadius: index === 4 ? r : 0
                    // Not read yet: a quiet ramp of the card's own colour.
                    color: spec ? spec.fill : Qt.tint(card.colRaised, Qt.rgba(1, 1, 1, 0.02 + 0.025 * (4 - index)))

                    StyledText {
                        anchors { left: parent.left; leftMargin: 8 * card.u; verticalCenter: parent.verticalCenter }
                        visible: !!chip.spec && chip.spec.label !== ""
                        text: chip.spec ? chip.spec.label.toUpperCase() : ""
                        font.pixelSize: (Appearance?.font.pixelSize.smallest ?? 10) * 0.85 * card.u
                        font.weight: Font.Bold
                        font.letterSpacing: 1.1 * card.u
                        color: chip.ink
                        opacity: 0.85
                    }
                    StyledText {
                        anchors { right: parent.right; rightMargin: 8 * card.u; verticalCenter: parent.verticalCenter }
                        visible: !!chip.spec
                        text: chip.spec ? String(chip.spec.fill).toUpperCase() : ""
                        font.family: Appearance?.font.family.mono ?? "monospace"
                        font.pixelSize: (Appearance?.font.pixelSize.smallest ?? 10) * 0.95 * card.u
                        color: chip.ink
                    }
                }
            }
        }

        // ── Name and details ─────────────────────────────────────────────
        StyledText {
            id: titleText
            x: card.pad + 2 * card.u
            y: chipColumn.y + chipColumn.height + 9 * card.u
            width: thumbBase.width - 4 * card.u
            text: card.title
            elide: Text.ElideRight
            font.pixelSize: (Appearance?.font.pixelSize.smallie ?? 13) * card.u
            font.weight: Font.DemiBold
            color: card.colInk
        }
        StyledText {
            id: metaText
            x: titleText.x
            y: titleText.y + titleText.height + 2 * card.u
            width: titleText.width
            text: card.meta
            elide: Text.ElideRight
            font.pixelSize: (Appearance?.font.pixelSize.smallest ?? 10) * card.u
            color: card.colMuted
        }

        Rectangle {
            anchors.fill: parent
            visible: opacity > 0
            opacity: card.hovered ? 0 : card.dim
            radius: parent.radius
            color: Qt.rgba(0, 0, 0, 1)
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.clicked()
        onDoubleClicked: card.doubleClicked()
    }
}
