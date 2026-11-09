import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.services

/**
 * A panel card in the active look's material: its fill (or glass), the look's
 * stroke, and its texture (looks/schema.md) under the content. Animated
 * textures move only while the card is hovered or `interacting` is set; idle,
 * the texture is one static frame.
 *
 * Glass (appearance.glass.enable, any look): the fill becomes a tint over the
 * compositor's blur, with refraction of the wallpaper at the edges and an
 * edge light; over bright wallpaper the tint thickens to keep text ≥ 4.5:1.
 *
 *   SurfaceMaterial { surface: "hud"; radius: Appearance.rounding.large; color: … }
 */
Item {
    id: root

    property string surface: ""
    property bool interacting: hover.hovered
    // Rectangle-style API: callers set these as on a Rectangle.
    property color color: Appearance.colors.colLayer0
    property real radius: 0
    property alias border: fill.border
    // Text drawn on it (for the glass contrast check).
    property color textColor: Appearance.colors.colOnLayer0

    readonly property bool glass: Glass.enabled && root.color.a > 0.05

    Rectangle {
        id: fill
        anchors.fill: parent
        radius: root.radius
        color: root.glass ? "transparent" : root.color
    }

    // ── Glass ──────────────────────────────────────────────────────────
    // Where this card is on screen, in the wallpaper's UV space.
    property vector4d _wallRect: Qt.vector4d(0, 0, 1, 1)
    function _place() {
        const w = root.QsWindow.window
        if (!root.glass || !w || !w.screen) return
        const o = PanelRegistry.windowOrigin(w)
        const p = root.mapToItem(null, 0, 0)
        root._wallRect = Glass.wallRect(o.x + p.x, o.y + p.y, root.width * root.scale, root.height * root.scale,
            w.screen.width, w.screen.height, wallImg.implicitWidth, wallImg.implicitHeight)
    }
    onXChanged: Qt.callLater(_place)
    onYChanged: Qt.callLater(_place)
    onWidthChanged: Qt.callLater(_place)
    onHeightChanged: Qt.callLater(_place)
    onGlassChanged: Qt.callLater(_place)
    Image {
        id: wallImg
        visible: false
        source: root.glass && Glass.refraction > 0 && Glass.wallpaper ? Wallpapers.fileUrl(Glass.wallpaper) : ""
        sourceSize.width: 1280
        asynchronous: true
        cache: true
        onStatusChanged: if (status === Image.Ready) root._place()
    }
    ShaderEffect {
        id: glassLayer
        anchors.fill: parent
        visible: root.glass
        fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/glass.frag.qsb"))
        property real widthPx: width
        property real heightPx: height
        property real radius: root.radius
        property real edgeLight: Glass.edgeLight
        property real refraction: wallImg.status === Image.Ready ? Glass.refraction : 0
        property real rimWidth: Math.min(22, Math.min(width, height) * 0.2)
        readonly property real _alpha: Glass.tintAlpha(Glass.tint, Glass.luminanceUnder(root._wallRect), root.color, root.textColor)
        property vector4d tint: Qt.vector4d(root.color.r, root.color.g, root.color.b, _alpha)
        readonly property color _light: ColorUtils.mix(Appearance.colors.colOnSurface, Appearance.colors.colPrimary, 0.7)
        property vector4d light: Qt.vector4d(_light.r, _light.g, _light.b, 1)
        property vector4d wallRect: root._wallRect
        property var wallpaper: wallImg
    }

    readonly property var look: Looks.forSurface(root.surface)
    readonly property var _tex: root.look.texture ?? null
    readonly property int _mode: ({ caustics: 1, paper_grain: 2, ink_bleed: 2, grid_scan: 3, clay_soft: 4 })[root._tex?.shader] ?? 0
    readonly property real _strength: { const p = root._tex?.params ?? {}; return p.strength ?? p.grain ?? p.light ?? 0.2 }
    // No texture on a see-through card (e.g. one the connected frame paints).
    readonly property bool _textured: root._mode > 0 && root._strength > 0 && root.color.a > 0.05 && (Config.options?.appearance?.lookTextures ?? true)

    // appearance.border, or the look's thicker stroke; none on a see-through
    // card (the connected frame draws the outline once around its shape).
    border.width: root.color.a > 0.05 ? Appearance.borders.forStroke(root.look.shape?.stroke) : 0
    border.color: Appearance.borders.color

    HoverHandler { id: hover }

    // Look transition: `ink_bleed` soaks the card in when it appears (it goes
    // from invisible to visible). The effect layer exists only while it runs.
    readonly property bool _inkBleed: root.look.transition === "ink_bleed" && AnimationConfig.enabled
    property real _reveal: 1
    property bool _shown: false
    function _checkShown() {
        const shown = root.visible && root.opacity > 0.01
        if (shown && !root._shown && root._inkBleed) { revealAnim.restart() }
        root._shown = shown
    }
    onOpacityChanged: _checkShown()
    onVisibleChanged: _checkShown()
    Component.onCompleted: _checkShown()
    NumberAnimation {
        id: revealAnim
        target: root; property: "_reveal"; from: 0; to: 1
        duration: AnimationConfig.scaledDuration(560); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }
    layer.enabled: revealAnim.running
    layer.effect: ShaderEffect {
        fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/ink_reveal.frag.qsb"))
        property real progress: root._reveal
        property real widthPx: root.width
        property real heightPx: root.height
    }

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
