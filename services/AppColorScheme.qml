pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

/**
 * Light/dark for your apps, independent of the shell
 * (appearance.theme.appColorScheme: follow | light | dark). Sets the
 * freedesktop color-scheme (GTK 4/libadwaita, and Qt apps through the portal)
 * and, if you use adw-gtk3, its light/dark variant for GTK 3, whenever the choice or the shell's mode
 * changes.
 */
Singleton {
    id: root

    readonly property string setting: Config.options?.appearance?.theme?.appColorScheme ?? "follow"
    readonly property bool dark: root.setting === "dark" || (root.setting !== "light" && Appearance.m3colors.darkmode)

    function apply() {
        if (!Config.ready) return
        proc.exec(["sh", "-c", 'command -v gsettings >/dev/null || exit 0; ' +
            'gsettings set org.gnome.desktop.interface color-scheme "$1"; ' +
            // Only flip adw-gtk3 <-> adw-gtk3-dark; a GTK theme you chose is left alone.
            'case "$(gsettings get org.gnome.desktop.interface gtk-theme)" in' +
            ' "\'adw-gtk3"*) gsettings set org.gnome.desktop.interface gtk-theme "$2";; esac',
            "sh", root.dark ? "prefer-dark" : "prefer-light", root.dark ? "adw-gtk3-dark" : "adw-gtk3"])
    }
    onDarkChanged: apply()
    Connections { target: Config; function onReadyChanged() { root.apply() } }

    Process { id: proc }
}
