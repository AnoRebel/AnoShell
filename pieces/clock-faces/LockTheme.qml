pragma Singleton
import QtQuick
import Quickshell
import qs.modules.common

// Stand-in for dhrruvsharma's LockTheme: alpha() and the faces' fonts, each
// the author's when installed, else AnoShell's.
Singleton {
    readonly property var _have: Qt.fontFamilies()
    readonly property string sans: _have.includes("Adwaita Sans") ? "Adwaita Sans" : Appearance.font.family.main
    readonly property string mono: _have.includes("Iosevka Nerd Font") ? "Iosevka Nerd Font" : Appearance.font.family.monospace
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
    // AnoShell's clock format (time.format): 12-hour when it has am/pm.
    readonly property bool twelve: /a/i.test(Config.options?.time?.format ?? "hh:mm")
    function hm(d) { return twelve ? Qt.formatDateTime(d, "h:mm AP").replace(/\s*[AP]M$/i, "") : Qt.formatDateTime(d, "hh:mm") }
    function ap(d) { return twelve ? Qt.formatDateTime(d, "AP") : "" }
}
