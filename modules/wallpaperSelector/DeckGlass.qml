import QtQuick
import qs.modules.common

// A glass pill in the deck's try-on colours (WallpaperDeck.tint).
Rectangle {
    required property Item deck
    color: Qt.rgba(deck.tint.surface.r, deck.tint.surface.g, deck.tint.surface.b, 0.8)
    border.width: 1
    border.color: Qt.rgba(deck.tint.ink.r, deck.tint.ink.g, deck.tint.ink.b, 0.12)
    radius: (Appearance?.rounding.large ?? 23) * deck.u
}
