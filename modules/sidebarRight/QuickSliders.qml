import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * Volume + Brightness sliders, inspired by ilyamiro's battery popup sliders.
 */
Rectangle {
    id: root
    property var brightnessMonitor
    property bool pickOutput: false // the device lists under the volume and mic sliders
    property bool pickInput: false

    implicitHeight: slidersColumn.implicitHeight + 16
    radius: Appearance?.rounding.normal ?? 12
    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

    ColumnLayout {
        id: slidersColumn
        anchors { fill: parent; margins: 8 }
        spacing: 8

        // Brightness
        Loader {
            Layout.fillWidth: true
            active: (Config.options?.sidebar?.quickSliders?.showBrightness ?? true) && !!root.brightnessMonitor
            visible: active
            sourceComponent: RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: "brightness_6"; iconSize: 20
                    color: Appearance?.colors.colPrimary ?? "#65558F"
                    Layout.alignment: Qt.AlignVCenter
                }
                StyledSlider {
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.M
                    trackWidth: 18; trackRadius: 6; handleHeight: 26 // slim: the handle sets the row height
                    value: root.brightnessMonitor?.brightness ?? 0
                    onMoved: root.brightnessMonitor?.setBrightness(value)
                    stopIndicatorValues: []
                }
            }
        }

        // Volume
        Loader {
            Layout.fillWidth: true
            active: Config.options?.sidebar?.quickSliders?.showVolume ?? true
            visible: active
            sourceComponent: ColumnLayout {
              spacing: 4
              RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"
                    iconSize: 20
                    color: Audio.sink?.audio?.muted ? Appearance?.m3colors.m3error ?? "#BA1A1A" : Appearance?.colors.colPrimary ?? "#65558F"
                    Layout.alignment: Qt.AlignVCenter
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Audio.toggleMute()
                    }
                }
                StyledSlider {
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.M
                    trackWidth: 18; trackRadius: 6; handleHeight: 26 // slim: the handle sets the row height
                    value: Audio.sink?.audio?.volume ?? 0
                    onMoved: { if (Audio.sink?.audio) Audio.sink.audio.volume = value }
                    stopIndicatorValues: []
                }
                ToolbarButton {
                    iconName: root.pickOutput ? "expand_less" : "expand_more"; iconSize: 18
                    toolTipText: "Output device"
                    onClicked: root.pickOutput = !root.pickOutput
                }
              }
              AudioDevicePicker { visible: root.pickOutput; Layout.fillWidth: true; outputs: true }
            }
        }

        // Mic
        Loader {
            Layout.fillWidth: true
            active: Config.options?.sidebar?.quickSliders?.showMic ?? false
            visible: active
            sourceComponent: ColumnLayout {
              spacing: 4
              RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: Audio.source?.audio?.muted ? "mic_off" : "mic"
                    iconSize: 20; color: Appearance?.colors.colPrimary ?? "#65558F"
                    Layout.alignment: Qt.AlignVCenter
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Audio.toggleMicMute() }
                }
                StyledSlider {
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.M
                    value: Audio.source?.audio?.volume ?? 0
                    onMoved: { if (Audio.source?.audio) Audio.source.audio.volume = value }
                    stopIndicatorValues: []
                }
                ToolbarButton {
                    iconName: root.pickInput ? "expand_less" : "expand_more"; iconSize: 18
                    toolTipText: "Input device"
                    onClicked: root.pickInput = !root.pickInput
                }
              }
              AudioDevicePicker { visible: root.pickInput; Layout.fillWidth: true; outputs: false; inputs: true }
            }
        }
    }
}
