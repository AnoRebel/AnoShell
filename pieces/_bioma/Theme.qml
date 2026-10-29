pragma Singleton

import QtQuick
import Quickshell
import qs.modules.common as Ano

// Bioma's Theme for the ported organisms (Bioma, GPL-3.0; core/Theme.qml),
// its four interface roles taken from AnoShell's palette instead of Bioma's
// palette files. The state colours, derived surfaces, outline family and
// gradients are Bioma's own.
Singleton {
    id: root

    // ---- Interface roles (theme source) ----------------------------------
    //
    // The palette as loaded is one thing and the palette on screen is another:
    // a theme change crosses every surface together over `Timing.theme`, so
    // what cells bind to is the colour in transit. The target is kept beside it
    // for the one thing that needs the destination rather than the journey —
    // the theme cell's chips, which have to arrive one at a time and cannot do
    // that while chasing the shell's own transition.

    // AnoShell: the four roles follow the shell's palette (wallpaper or theme).
    property color backgroundTarget: Ano.Appearance.colors.colLayer0
    property color textTarget: Ano.Appearance.colors.colOnLayer0
    property color primaryTarget: Ano.Appearance.colors.colPrimary
    property color secondaryTarget: Ano.Appearance.colors.colSecondary

    property color background: root.backgroundTarget
    property color text: root.textTarget
    property color primary: root.primaryTarget
    property color secondary: root.secondaryTarget

    // ---- State roles (fixed, never from matugen) --------------------------

    readonly property color calm: isDark ? stateDark.calm : stateLight.calm
    readonly property color active: isDark ? stateDark.active : stateLight.active
    readonly property color alert: isDark ? stateDark.alert : stateLight.alert

    readonly property var stateDark: Config.get("theme.state.dark", {
        "calm": "#6EE7A6",
        "active": "#F2C14E",
        "alert": "#FF6B5D"
    })
    readonly property var stateLight: Config.get("theme.state.light", {
        "calm": "#2E9C6A",
        "active": "#B37414",
        "alert": "#C43A2E"
    })

    // Load is measured, so it speaks in state colours. A scale the user moves —
    // volume, brightness, colour temperature — is a control and stays primary
    // for its whole travel: red on a slider would mean "past threshold", and
    // turning the volume up is not an alarm.
    //
    // Three states, two boundaries, no dead zone. Flicker around a boundary is
    // cured upstream on the reading — values arrive already smoothed — never
    // with hysteresis here.
    readonly property real thresholdCalm: 0.30
    readonly property real thresholdAlert: 0.80

    function stateFor(load) {
        if (load >= root.thresholdAlert)
            return root.alert;
        if (load >= root.thresholdCalm)
            return root.active;
        return root.calm;
    }

    // ---- Light or dark ----------------------------------------------------

    // Inferred from the background, never configured.
    readonly property real backgroundLuminance: luminance(background)
    readonly property bool isDark: backgroundLuminance < 0.5

    // ---- Derived surfaces -------------------------------------------------

    // Lightness steps away from the background, in the background's own hue:
    // a tinted surface family rather than a grey one laid over a colour.
    readonly property color surface: lift(background, 0.045)
    readonly property color elevated: lift(background, 0.045)
    readonly property color cell: lift(background, 0.075)
    readonly property color wellSurface: lift(background, 0.02)

    // Only for a secondary label nobody presses, or an option not chosen.
    // Never for an enabled control, a title, or a setting's name or value:
    // muted, those read as disabled (STYLE_GUIDE.md, Interface).
    readonly property color textMuted: Qt.alpha(text, 0.56)
    readonly property color textFaint: Qt.alpha(text, 0.38)
    readonly property color border: Qt.alpha(text, isDark ? 0.09 : 0.14)

    // The shadow of an invoked or expanded cell. A function too, because
    // niri's focused window carries the same one (services/Templates.qml).
    function shadowOf(dark) {
        return Qt.alpha("#000000", dark ? 0.45 : 0.22);
    }
    readonly property color shadow: shadowOf(isDark)
    readonly property color shadowFloat: Qt.alpha("#000000", isDark ? 0.60 : 0.30)

    // ---- The outline family ----------------------------------------------
    //
    // Outlines, threads, nodes and the rim are one family at three lightnesses:
    // the line recedes, the node marks an attachment, the rim is the single
    // light source on the top edge. They follow the background's hue — that is
    // what keeps them reading as structure rather than as accent — and borrow
    // the primary's only when the background has no hue of its own.

    readonly property real structuralHue: hueOf(background, primary)
    readonly property real structuralSaturation: saturationOf(background, primary)

    readonly property color line: structural(isDark ? 0.32 : 0.72)
    readonly property color node: structural(isDark ? 0.43 : 0.62)
    readonly property color rim: structural(isDark ? 0.55 : 0.50)

    function hueOf(bg, accent) {
        return bg.hslSaturation > 0.05 && bg.hslHue >= 0 ? bg.hslHue : Math.max(0, accent.hslHue);
    }

    function saturationOf(bg, accent) {
        return Math.max(Math.min(bg.hslSaturation + 0.04, 0.40),
                        Math.min(accent.hslSaturation * 0.33, 0.28));
    }

    function structuralWith(bg, accent, lightness) {
        return Qt.hsla(root.hueOf(bg, accent), root.saturationOf(bg, accent), lightness, 1);
    }

    function structural(lightness) {
        return root.structuralWith(root.background, root.primary, lightness);
    }

    // ---- Gradients --------------------------------------------------------
    //
    // The gradient simulates light: one source, from above, identical across
    // the shell — fixed 165°, two tones of the same hue, the top lighter and
    // the bottom darker and more saturated. It goes on indicators, value
    // digits, header icons and selected controls; never on a fill, a thread,
    // a thin line icon, and never as a glow.

    readonly property real gradientAngle: 165

    function gradientTop(base) {
        return Qt.hsla(Math.max(0, base.hslHue),
                       Math.min(1, base.hslSaturation + 0.14),
                       Math.min(1, base.hslLightness + 0.16),
                       base.a);
    }

    function gradientBottom(base) {
        return Qt.hsla(Math.max(0, base.hslHue),
                       Math.max(0, base.hslSaturation - 0.15),
                       Math.max(0, base.hslLightness - 0.15),
                       base.a);
    }

    // ---- Helpers ----------------------------------------------------------

    function luminance(colour) {
        // Rec. 709 relative luminance, good enough to pick a side.
        return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b;
    }

    // Moves a colour away from the background's side: lighter on a dark theme,
    // darker on a light one, keeping hue and saturation.
    function lift(colour, amount) {
        return root.liftAway(colour, amount, root.isDark);
    }

    function liftAway(colour, amount, dark) {
        const step = dark ? amount : -amount;
        return Qt.hsla(Math.max(0, colour.hslHue),
                       colour.hslSaturation,
                       Math.max(0, Math.min(1, colour.hslLightness + step)),
                       colour.a);
    }
}
