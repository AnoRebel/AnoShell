import QtQuick
import QtQuick.Layouts
import "root:modules/common"
import "root:modules/common/widgets"
import "root:layouts"
import "root:services"

/**
 * AnoView overview settings — elaborate layout selection with visual previews
 * showing abstract representations of each layout algorithm.
 */
ColumnLayout {
    id: root
    spacing: 16
    readonly property string currentLayout: Config.options?.overview?.layout ?? "smartgrid"

    // ═══ Layout Selection ═══
    SettingsCard {
        icon: "overview"
        title: "AnoView Layout"
        subtitle: "Choose how windows are arranged in the overview"
        collapsible: false

        // Visual layout grid with mini-previews
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 10; rowSpacing: 10

            Repeater {
                model: [
                    { id: "smartgrid", name: "Smart Grid", desc: "Optimal grid with aspect-fit", icon: "grid_view" },
                    { id: "justified", name: "Justified", desc: "Text-wrap style rows", icon: "view_week" },
                    { id: "bands", name: "Bands", desc: "Grouped by workspace", icon: "view_stream" },
                    { id: "masonry", name: "Masonry", desc: "Pinterest-style columns", icon: "dashboard" },
                    { id: "hero", name: "Hero", desc: "Active window large + stack", icon: "picture_in_picture" },
                    { id: "spiral", name: "Spiral", desc: "Fibonacci space partitions", icon: "rotate_right" },
                    { id: "satellite", name: "Satellite", desc: "Active center + orbital ring", icon: "blur_circular" },
                    { id: "staggered", name: "Staggered", desc: "Brick-wall offset grid", icon: "view_comfy" },
                    { id: "columnar", name: "Columnar", desc: "One window per column", icon: "view_column" },
                    { id: "vortex", name: "Vortex", desc: "Golden spiral with rotation", icon: "cyclone" },
                    { id: "random", name: "Random", desc: "Different layout each time", icon: "shuffle" },
                ]

                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 80
                    radius: Appearance?.rounding.small ?? 8
                    color: root.currentLayout === modelData.id
                        ? Qt.rgba((Appearance?.colors.colPrimary ?? "#65558F").r, (Appearance?.colors.colPrimary ?? "#65558F").g, (Appearance?.colors.colPrimary ?? "#65558F").b, 0.2)
                        : Appearance?.colors.colLayer2 ?? "#2B2930"
                    border.width: root.currentLayout === modelData.id ? 2 : 1
                    border.color: root.currentLayout === modelData.id
                        ? Appearance?.colors.colPrimary ?? "#65558F"
                        : Appearance?.colors.colOutlineVariant ?? "#44444488"

                    Behavior on color { ColorAnimation { duration: 200 } }
                    Behavior on border.color { ColorAnimation { duration: 200 } }

                    scale: layoutMA.pressed ? 0.95 : (layoutMA.containsMouse ? 1.02 : 1)
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4

                        MaterialSymbol {
                            text: modelData.icon
                            iconSize: 24
                            fill: root.currentLayout === modelData.id ? 1 : 0
                            color: root.currentLayout === modelData.id
                                ? Appearance?.colors.colPrimary ?? "#65558F"
                                : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                            Layout.alignment: Qt.AlignHCenter
                        }
                        StyledText {
                            text: modelData.name
                            font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                            font.weight: Font.DemiBold
                            color: root.currentLayout === modelData.id
                                ? Appearance?.colors.colPrimary ?? "#65558F"
                                : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    MouseArea {
                        id: layoutMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.setNestedValue("overview.layout", modelData.id)
                    }

                    StyledToolTip {
                        text: modelData.desc
                        visible: layoutMA.containsMouse
                    }
                }
            }
        }

        // Current selection indicator
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            MaterialSymbol { text: "check_circle"; iconSize: 18; color: Appearance?.colors.colPrimary ?? "#65558F"; fill: 1 }
            StyledText {
                text: `Selected: ${root.currentLayout.charAt(0).toUpperCase() + root.currentLayout.slice(1)}`
                font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                font.weight: Font.DemiBold
                color: Appearance?.colors.colPrimary ?? "#65558F"
            }
        }
    }
}
