import QtQuick
import Quickshell

// A picture in the deck drawn from a texture (the preview's own image, or a
// ShaderEffectSource of the video playing in it), filling the item the way
// Image.PreserveAspectCrop does, with rounded corners and an optional band
// of light sweeping across (shaders/frag/card_picture.frag).
// From wallpaperpicker's CardPicture.qml.
ShaderEffect {
    id: picture

    property var source
    property real sourceAspect: 1        // the texture's width over its height
    property real radius: 0              // in the item's own units
    property real pixelScale: 1          // screen pixels per unit (smooth edges when scaled)
    property real shine: -1              // 0..1 across; none outside about -0.3..1.3

    readonly property real aspect: width / Math.max(1, height)
    readonly property vector4d crop: aspect > sourceAspect
        ? Qt.vector4d(0, (1 - sourceAspect / aspect) / 2, 1, sourceAspect / aspect)
        : Qt.vector4d((1 - aspect / sourceAspect) / 2, 0, aspect / sourceAspect, 1)
    readonly property vector2d pixels: Qt.vector2d(width * pixelScale, height * pixelScale)
    readonly property real radiusPx: radius * pixelScale

    fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/card_picture.frag.qsb"))
}
