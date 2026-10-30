pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

// Stand-in for dhrruvsharma's matugen Colors singleton: the names the faces
// use, read from AnoShell's current colours.
Singleton {
    readonly property color on_surface: Appearance.m3colors.m3onSurface
    readonly property color primary: Appearance.m3colors.m3primary
    readonly property color tertiary: Appearance.m3colors.m3tertiary
    readonly property color on_tertiary: Appearance.m3colors.m3onTertiary
    readonly property color background: Appearance.m3colors.m3background
    function withAlpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
}
