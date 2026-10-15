import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * A panel card in the active look's material: a Rectangle that takes the
 * look's stroke and paints its texture (looks/schema.md) between the fill and
 * the content. Animated textures move only while the card is hovered or
 * `interacting` is set; idle, the texture is one static frame.
 *
 *   SurfaceMaterial { surface: "hud"; radius: Appearance.rounding.large; color: … }
 */
Rectangle {
    id: root

    property string surface: ""
    property bool interacting: hover.hovered

    readonly property var look: Looks.forSurface(root.surface)
    readonly property var _tex: root.look.texture ?? null
    readonly property int _mode: ({ caustics: 1, paper_grain: 2, ink_bleed: 2, grid_scan: 3, clay_soft: 4 })[root._tex?.shader] ?? 0
    readonly property real _strength: { const p = root._tex?.params ?? {}; return p.strength ?? p.grain ?? p.light ?? 0.2 }
    // No texture on a see-through card (e.g. one the connected frame paints).
    readonly property bool _textured: root._mode > 0 && root._strength > 0 && root.color.a > 0.05 && (Config.options?.appearance?.lookTextures ?? true)

    border.width: root.look.shape?.stroke ?? 0
    border.color: Appearance.colors.colOutlineVariant

    HoverHandler { id: hover }

    ShaderEffect {
        id: texture
        anchors.fill: parent
        visible: root._textured
        fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/look_texture.frag.qsb"))
        property real widthPx: width
        property real heightPx: height
        property real radius: root.radius
        property real mode: root._mode
        property real strength: root._strength
        property real param: root._tex?.params?.spacing ?? 24
        property real time: 0
        readonly property color _tint: ColorUtils.mix(Appearance.colors.colPrimary, Appearance.colors.colOnSurface, 0.5)
        readonly property color _shade: Appearance.m3colors.m3shadow
        property vector4d tint: Qt.vector4d(_tint.r, _tint.g, _tint.b, 1)
        property vector4d shade: Qt.vector4d(_shade.r, _shade.g, _shade.b, 1)

        FrameAnimation {
            running: texture.visible && root.interacting && root._tex?.animate === "interaction"
            onTriggered: texture.time += frameTime
        }
    }
}
