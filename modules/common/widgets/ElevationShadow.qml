pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell

/**
 * ElevationShadow — Material 3 rounded-rect fill + border + key/ambient shadow,
 * drawn in a single SDF fragment shader (ported from DMS's ElevationShadow +
 * elevation_rect.frag). Replaces MultiEffect/DropShadow: the blur is a
 * smoothstep band on an analytic SDF — no FBO, no layer.enabled, very cheap.
 *
 * Place BEHIND a surface's content, sized to the surface, with matching radius:
 *   ElevationShadow { anchors.fill: card; level: 3; targetRadius: card.radius
 *                     targetColor: card.color }
 *
 * Global gate: appearance.shadows.enable (default off). When off, the shadow
 * terms are zeroed and the padding collapses, so it costs nearly nothing.
 *
 * M3 elevation levels 1..5 → blur 4/8/12/16/20 px, alpha 0.2/0.25/0.3/0.3/0.3.
 */
Item {
    id: root

    // Elevation level 1..5 (M3 dp). Higher = softer/larger shadow.
    property int level: 2
    // "auto" | "top" | "bottom" | "left" | "right" — where light comes from.
    property string direction: "top"
    property real fallbackOffset: 2

    property color targetColor: "transparent"
    property real targetRadius: Appearance?.rounding.normal ?? 12
    property real topLeftRadius: targetRadius
    property real topRightRadius: targetRadius
    property real bottomLeftRadius: targetRadius
    property real bottomRightRadius: targetRadius
    property color borderColor: "transparent"
    property real borderWidth: 0

    property real sourceX: 0
    property real sourceY: 0
    property real sourceWidth: width
    property real sourceHeight: height

    readonly property bool shadowEnabled: (Config.options?.appearance?.shadows?.enable ?? false)
    readonly property real _intensity: Config.options?.appearance?.shadows?.intensity ?? 1.0
    readonly property real _opacityMult: Config.options?.appearance?.shadows?.opacity ?? 1.0

    // Per-level M3 tokens (blur px, key alpha). Spread is 0 for all M3 levels.
    readonly property var _levels: [
        { blur: 4,  alpha: 0.20 },
        { blur: 8,  alpha: 0.25 },
        { blur: 12, alpha: 0.30 },
        { blur: 16, alpha: 0.30 },
        { blur: 20, alpha: 0.30 }
    ]
    readonly property var _lvl: _levels[Math.max(0, Math.min(4, level - 1))]
    readonly property real shadowBlurPx: _lvl.blur * _intensity
    readonly property real shadowSpreadPx: 0
    readonly property real _keyAlpha: _lvl.alpha * _opacityMult

    // Light-direction → key-shadow offset. "auto"/"top" ⇒ light from top, shadow
    // falls downward. Magnitude scales with level.
    readonly property real _offMag: fallbackOffset + level * 1.0
    readonly property real shadowOffsetX: direction === "left" ? _offMag
        : direction === "right" ? -_offMag : 0
    readonly property real shadowOffsetY: (direction === "bottom") ? -_offMag
        : (direction === "left" || direction === "right") ? 0 : _offMag

    // Ambient term: no offset, wider blur, lower alpha (M3 two-shadow model).
    readonly property real _ambBlur: shadowBlurPx * 1.75
    readonly property real _ambAlpha: _keyAlpha * 0.5

    // Shadow tint (theme shadow colour, forced opaque base; alpha via params).
    readonly property color shadowColor: Appearance?.colors.colShadow ?? "#000000"

    // Padding so the shadow can bleed outside the surface bounds.
    readonly property real _pad: shadowEnabled
        ? Math.ceil(Math.max(shadowBlurPx + shadowSpreadPx + Math.max(Math.abs(shadowOffsetX), Math.abs(shadowOffsetY)), _ambBlur) + 2)
        : 0

    ShaderEffect {
        anchors.fill: parent
        anchors.margins: -root._pad
        // Quickshell.shellPath() resolves relative to the shell root (the same
        // mechanism AntiFlashbang uses for its .glsl); `root:` URLs don't resolve
        // for a ShaderEffect's fragmentShader.
        fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/elevation_rect.frag.qsb"))

        property real widthPx: width
        property real heightPx: height
        property real borderWidth: root.borderWidth
        property vector4d rectPx: Qt.vector4d(root._pad + root.sourceX, root._pad + root.sourceY, root.sourceWidth, root.sourceHeight)
        property vector4d cornerRadius: Qt.vector4d(root.topLeftRadius, root.topRightRadius, root.bottomRightRadius, root.bottomLeftRadius)
        property vector4d fillColor: Qt.vector4d(root.targetColor.r, root.targetColor.g, root.targetColor.b, root.targetColor.a)
        property vector4d borderColor: Qt.vector4d(root.borderColor.r, root.borderColor.g, root.borderColor.b, root.borderColor.a)
        property vector4d shadowColor: Qt.vector4d(root.shadowColor.r, root.shadowColor.g, root.shadowColor.b, root.shadowEnabled ? root._keyAlpha : 0)
        property vector4d shadowParam: Qt.vector4d(Math.max(0, root.shadowBlurPx), root.shadowSpreadPx, root.shadowOffsetX, root.shadowOffsetY)
        property vector4d ambientParam: Qt.vector4d(root._ambBlur, 0, root.shadowEnabled ? root._ambAlpha : 0, 0)
    }
}
