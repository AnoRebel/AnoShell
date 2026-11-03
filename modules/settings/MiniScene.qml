import QtQuick
import qs.modules.common

/**
 * A tiny desktop drawn in a given palette and look, for theme and look tiles
 * (settings-wiring "Interactive previews in Settings"): a bar with a pill
 * accent, a popup (title, text, progress, buttons) and a notification.
 * Static: nothing animates or runs.
 *
 *   tokens:  theme tokens by their JSON names (background, surface_container,
 *            primary, on_surface, …); missing ones fall back to the shell's.
 *   look:    a look object (looks/schema.md) for shape, material and type.
 */
Item {
    id: root
    property var tokens: ({})
    property var look: ({})
    implicitHeight: 92

    function c(key, fallback) { return root.tokens?.[key] ?? fallback }
    readonly property color bg: c("background", Appearance.m3colors.m3background)
    readonly property color surface: c("surface_container", Appearance.colors.colLayer1)
    readonly property color surfaceHigh: c("surface_container_high", Appearance.colors.colLayer2)
    readonly property color onSurface: c("on_surface", Appearance.m3colors.m3onSurface)
    readonly property color onSurfaceVariant: c("on_surface_variant", Appearance.m3colors.m3onSurfaceVariant)
    readonly property color primary: c("primary", Appearance.m3colors.m3primary)
    readonly property color onPrimary: c("on_primary", Appearance.m3colors.m3onPrimary)
    readonly property color secondaryContainer: c("secondary_container", Appearance.m3colors.m3secondaryContainer)
    readonly property color onSecondaryContainer: c("on_secondary_container", Appearance.m3colors.m3onSecondaryContainer)
    readonly property color outline: c("outline_variant", Appearance.m3colors.m3outlineVariant)

    readonly property real r: 7 * (look?.shape?.radiusScale ?? 1)
    readonly property bool stroked: (look?.shape?.stroke ?? 0) > 0
    readonly property bool glass: look?.material?.glass ?? false
    readonly property string material: look?.material?.kind ?? "solid"
    readonly property string texture: look?.texture?.shader ?? ""
    function _font(role) {
        const v = root.look?.typography?.[role]
        const f = Config.options?.appearance?.fonts ?? {}
        return !v ? (Appearance.font.family.main) : v === "@main" ? f.main : v === "@mono" ? f.monospace
            : v === "@reading" ? f.reading : v === "@expressive" ? f.expressive : v
    }
    readonly property string fontMain: _font("main")
    readonly property string fontTitle: _font("title")

    // A surface in this look: its material's fill, an outline when stroked.
    component Panel: Rectangle {
        radius: root.r
        color: root.glass ? Qt.rgba(root.surface.r, root.surface.g, root.surface.b, 0.82) : root.surface
        border.width: root.stroked ? 1 : 0
        border.color: root.outline
        // Clay: a soft light from the top; paper: a faint warm wash.
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: root.material === "clay" || root.material === "paper"
            gradient: Gradient {
                GradientStop { position: 0; color: root.material === "clay" ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 0.95, 0.85, 0.05) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.bg
        clip: true

        // Neo-tech's grid, faintly.
        Repeater {
            model: root.texture === "grid_scan" ? Math.ceil(root.width / 14) : 0
            Rectangle { x: index * 14; width: 1; height: root.height; color: root.outline; opacity: 0.25 }
        }

        // The bar.
        Panel {
            id: bar
            x: 5; y: 5; width: parent.width - 10; height: 12
            radius: Math.min(root.r, 6)
            Rectangle { x: 5; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 6; radius: 3; color: root.primary }
            Row {
                anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                spacing: 3
                Repeater { model: 3; Rectangle { width: 4; height: 4; radius: 2; color: root.onSurfaceVariant } }
            }
        }

        // A popup.
        Panel {
            x: 5; y: 21; width: parent.width * 0.58; height: parent.height - 26
            color: root.glass ? Qt.rgba(root.surfaceHigh.r, root.surfaceHigh.g, root.surfaceHigh.b, 0.85) : root.surfaceHigh
            Column {
                anchors { fill: parent; margins: 6 }
                spacing: 3
                Text { text: "Aa Title"; color: root.onSurface; font.family: root.fontTitle; font.pixelSize: 10; font.weight: Font.DemiBold }
                Text { text: "Body text"; color: root.onSurfaceVariant; font.family: root.fontMain; font.pixelSize: 8 }
                Rectangle {
                    width: parent.width; height: 3; radius: 1.5; color: root.outline
                    Rectangle { width: parent.width * 0.6; height: parent.height; radius: parent.radius; color: root.primary }
                }
                Row {
                    spacing: 4
                    Rectangle {
                        width: 26; height: 11; radius: Math.min(root.r, 5.5); color: root.primary
                        Text { anchors.centerIn: parent; text: "OK"; color: root.onPrimary; font.pixelSize: 7; font.family: root.fontMain }
                    }
                    Rectangle {
                        width: 26; height: 11; radius: Math.min(root.r, 5.5); color: "transparent"
                        border.width: 1; border.color: root.outline
                    }
                }
            }
        }

        // A notification.
        Rectangle {
            anchors { right: parent.right; rightMargin: 5; bottom: parent.bottom; bottomMargin: 5 }
            width: parent.width * 0.36; height: 26
            radius: root.r
            color: root.secondaryContainer
            border.width: root.stroked ? 1 : 0
            border.color: root.outline
            Column {
                anchors { left: parent.left; leftMargin: 5; verticalCenter: parent.verticalCenter }
                spacing: 2
                Rectangle { width: 28; height: 3; radius: 1.5; color: root.onSecondaryContainer }
                Rectangle { width: 18; height: 3; radius: 1.5; color: root.onSecondaryContainer; opacity: 0.6 }
            }
        }
    }
}
