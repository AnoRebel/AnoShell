import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * The PipeWire output and/or input devices as a list; clicking one makes it
 * the default (Audio.setDefaultSink / setDefaultSource). Used in Settings →
 * General → Audio, the right sidebar's sliders and the control panel.
 */
ColumnLayout {
    id: root
    property bool outputs: true
    property bool inputs: false
    spacing: 2

    Repeater {
        model: [root.outputs ? true : null, root.inputs ? false : null].filter(k => k !== null)
        delegate: ColumnLayout {
            id: section
            required property bool modelData // true: outputs
            // By name: PipeWire's own order changes between runs.
            readonly property var devices: Array.from(section.modelData ? Audio.outputDevices : Audio.inputDevices)
                .sort((a, b) => Audio.friendlyDeviceName(a).localeCompare(Audio.friendlyDeviceName(b)))
            readonly property var current: section.modelData ? Audio.sink : Audio.source
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                visible: root.outputs && root.inputs
                text: section.modelData ? "Output" : "Input"
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                opacity: 0.6
                Layout.topMargin: 4
            }
            StyledText {
                visible: section.devices.length === 0
                text: section.modelData ? "No output device" : "No input device"
                font.pixelSize: Appearance?.font.pixelSize.small ?? 14
                opacity: 0.5
            }
            Repeater {
                model: section.devices
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool selected: !!section.current && row.modelData.id === section.current.id
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: Appearance?.rounding.small ?? 8
                    color: row.selected ? (Appearance?.colors.colSecondaryContainer ?? "#E8DEF8")
                         : rowMA.containsMouse ? (Appearance?.colors.colLayer1Hover ?? "#3C3947") : "transparent"
                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                        spacing: 8
                        MaterialSymbol {
                            text: section.modelData ? "speaker" : "mic"
                            iconSize: 18
                            fill: row.selected ? 1 : 0
                            color: row.selected ? (Appearance?.m3colors.m3onSecondaryContainer ?? "#1D192B")
                                                : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Audio.friendlyDeviceName(row.modelData)
                            elide: Text.ElideRight
                            color: row.selected ? (Appearance?.m3colors.m3onSecondaryContainer ?? "#1D192B")
                                                : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
                        }
                        MaterialSymbol {
                            visible: row.selected
                            text: "check"
                            iconSize: 18
                            color: Appearance?.m3colors.m3onSecondaryContainer ?? "#1D192B"
                        }
                    }
                    MouseArea {
                        id: rowMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: section.modelData ? Audio.setDefaultSink(row.modelData) : Audio.setDefaultSource(row.modelData)
                    }
                }
            }
        }
    }
}
