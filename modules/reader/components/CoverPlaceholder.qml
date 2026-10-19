import QtQuick
import qs.modules.common
import qs.modules.common.functions

// What a cover shows until its image arrives: a flat tile that breathes while
// the image is loading and settles to a still glyph if it fails. Anchor it
// over the Image and bind `status` to the Image's status.
Rectangle {
    id: root

    property int status: Image.Null
    property int glyphSize: 32

    color: Appearance.m3colors.m3surfaceContainerHigh
    visible: root.status !== Image.Ready

    StyledText {
        anchors.centerIn: parent
        text: root.status === Image.Error ? "⊘" : "◫"
        font.pixelSize: root.glyphSize
        color: Appearance.m3colors.m3outline
        opacity: 0.25
    }

    SkeletonPulse {
        target: root
        low: 0.55
        running: root.visible && root.status === Image.Loading
    }
}
