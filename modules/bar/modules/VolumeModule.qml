import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Volume icon. Hover: a popout with the output volume slider; left-click pins
 * it open with the output and input device lists; middle-click mutes.
 */
Item {
    id: root
    property bool vertical: false
    implicitWidth: icon.implicitWidth + 8
    implicitHeight: vertical ? icon.implicitHeight + 8 : Appearance.sizes.barHeight
    property bool hovered: volMA.containsMouse
    property bool pinned: false
    readonly property real volume: Audio.sink?.audio?.volume ?? 0
    readonly property bool muted: Audio.sink?.audio?.muted ?? false

    MaterialSymbol {
        id: icon; anchors.centerIn: parent
        text: root.muted ? "volume_off" : root.volume <= 0.001 ? "volume_mute" : root.volume < 0.5 ? "volume_down" : "volume_up"
        iconSize: Appearance?.font.pixelSize.larger ?? 20
        color: root.muted ? (Appearance?.m3colors.m3error ?? "#BA1A1A") : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
    }

    MouseArea {
        id: volMA; anchors.fill: parent; hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) Audio.toggleMute()
            else root.pinned = !root.pinned
        }
    }

    BarModulePopout {
        shown: root.hovered || root.pinned
        popupWidth: 300; popupHeight: volPopupCol.implicitHeight + 24

        ColumnLayout {
            id: volPopupCol; anchors.fill: parent; spacing: 8

            RowLayout {
                spacing: 10
                MaterialSymbol { text: icon.text; iconSize: 24; fill: 1; color: Appearance?.colors.colPrimary ?? "#65558F" }
                StyledText {
                    text: Audio.friendlyDeviceName(Audio.sink)
                    font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.DemiBold
                    elide: Text.ElideRight; Layout.fillWidth: true
                }
                StyledText { text: root.muted ? "Muted" : `${Math.round(root.volume * 100)}%`; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.6 }
            }

            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: root.muted ? "volume_off" : "volume_up"; iconSize: 18
                    color: root.muted ? (Appearance?.m3colors.m3error ?? "#BA1A1A") : (Appearance?.colors.colPrimary ?? "#65558F")
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Audio.toggleMute() }
                }
                StyledSlider {
                    Layout.fillWidth: true
                    configuration: StyledSlider.Configuration.S
                    value: root.volume
                    onMoved: { if (Audio.sink?.audio) Audio.sink.audio.volume = value }
                    stopIndicatorValues: [1]
                }
            }

            StyledText {
                visible: !root.pinned
                text: "Click for devices · middle-click mutes"
                font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.4
                Layout.alignment: Qt.AlignHCenter
            }

            Loader {
                Layout.fillWidth: true
                active: root.pinned
                visible: active
                sourceComponent: AudioDevicePicker { outputs: true; inputs: true }
            }
        }
    }
}
