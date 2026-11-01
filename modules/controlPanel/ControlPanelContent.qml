import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.spectrum
import qs.services

/**
 * Control panel content (header, toggles, sliders, media, capture, tray,
 * system row): shared by the standalone panel and the pill's grow-into.
 */
ColumnLayout {
    id: root
    // Its host (the standalone panel, or the pill) closes on this.
    signal closeRequested()

    // User + time header
    RowLayout {
        Layout.fillWidth: true; spacing: 10
        StyledText {
            text: DateTime.time
            font.pixelSize: Appearance?.font.pixelSize.huger ?? 24
            font.weight: Font.Bold
            font.family: Appearance?.font.family.numbers ?? "monospace"
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: DateTime.shortDate
            font.pixelSize: Appearance?.font.pixelSize.small ?? 14
            opacity: 0.5
        }
    }

    // Quick toggles (compact 2x3 grid)
    GridLayout {
        Layout.fillWidth: true
        columns: 3; columnSpacing: 6; rowSpacing: 6

        // Right-click opens the Network Orbit panel when network.panelStyle is "orbit".
        CPToggle { iconName: Network.materialSymbol; label: Network.wifi ? Network.networkName : "WiFi"; active: Network.wifi; onClicked: Network.toggleWifi()
            onSecondaryClicked: if (GlobalStates.networkOrbitStyle) { root.closeRequested(); GlobalStates.openNetworkOrbit("wifi") } }
        CPToggle { iconName: BluetoothStatus.connected ? "bluetooth_connected" : "bluetooth"; label: "Bluetooth"; active: BluetoothStatus.connected; visible: BluetoothStatus.available
            onSecondaryClicked: if (GlobalStates.networkOrbitStyle) { root.closeRequested(); GlobalStates.openNetworkOrbit("bt") } }
        CPToggle { iconName: Notifications.silent ? "notifications_paused" : "notifications_active"; label: Notifications.silent ? "Silent" : "Alerts"; active: Notifications.silent; onClicked: Notifications.silent = !Notifications.silent }
        CPToggle { iconName: Idle.inhibit ? "coffee" : "coffee_maker"; label: Idle.inhibit ? "Awake" : "Idle"; active: Idle.inhibit; onClicked: Idle.toggleInhibit() }
        CPToggle { iconName: "dark_mode"; label: "Night"; active: false }
        CPToggle { iconName: "settings"; label: "Settings"; active: false; onClicked: { root.closeRequested(); GlobalStates.settingsOpen = true } }
    }

    // Sliders
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: sliderCol.implicitHeight + 16
        radius: Appearance?.rounding.normal ?? 12
        color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

        ColumnLayout {
            id: sliderCol
            anchors { fill: parent; margins: 8 }
            spacing: 10

            RowLayout {
                spacing: 8
                MaterialSymbol { text: "brightness_6"; iconSize: 18; color: Appearance?.colors.colPrimary ?? "#65558F" }
                StyledSlider { Layout.fillWidth: true; configuration: StyledSlider.Configuration.S; value: Brightness.monitors[0]?.brightness ?? 0; onMoved: Brightness.monitors[0]?.setBrightness(value); stopIndicatorValues: [] }
            }
            RowLayout {
                spacing: 8
                MaterialSymbol {
                    text: Audio.sink?.audio?.muted ? "volume_off" : "volume_up"; iconSize: 18
                    color: Audio.sink?.audio?.muted ? Appearance?.m3colors.m3error ?? "#BA1A1A" : Appearance?.colors.colPrimary ?? "#65558F"
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Audio.toggleMute() }
                }
                StyledSlider { Layout.fillWidth: true; configuration: StyledSlider.Configuration.S; value: Audio.sink?.audio?.volume ?? 0; onMoved: { if (Audio.sink?.audio) Audio.sink.audio.volume = value }
                stopIndicatorValues: [1] }
            }
        }
    }

    // Media (if playing)
    Loader {
        Layout.fillWidth: true
        active: MprisController.activePlayer != null; visible: active
        sourceComponent: Rectangle {
            implicitHeight: mediaRow.implicitHeight + 16
            radius: Appearance?.rounding.normal ?? 12
            color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
            RowLayout {
                id: mediaRow; anchors { fill: parent; margins: 8 }
                spacing: 10
                MaterialSymbol { text: MprisController.isPlaying ? "music_note" : "pause"; iconSize: 20; fill: 1; color: Appearance?.colors.colPrimary ?? "#65558F" }
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 1
                    StyledText { text: MprisController.activeTrack?.title ?? ""; font.pixelSize: Appearance.font.pixelSize.smallie; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.fillWidth: true }
                    StyledText { text: MprisController.activeTrack?.artist ?? ""; font.pixelSize: Appearance.font.pixelSize.smaller; opacity: 0.4; elide: Text.ElideRight; Layout.fillWidth: true }
                }
                ToolbarButton { iconName: "skip_previous"; iconSize: 18; onClicked: MprisController.previous() }
                ToolbarButton { iconName: MprisController.isPlaying ? "pause" : "play_arrow"; iconSize: 20; onClicked: MprisController.togglePlaying() }
                ToolbarButton { iconName: "skip_next"; iconSize: 18; onClicked: MprisController.next() }
            }
        }
    }

    // Capture (controlPanel.capture): each closes the panel first.
    Rectangle {
        visible: Config.options?.controlPanel?.capture ?? true
        Layout.fillWidth: true
        implicitHeight: captureRow.implicitHeight + 12
        radius: Appearance?.rounding.normal ?? 12
        color: Appearance?.colors.colLayer1 ?? "#E5E1EC"
        RowLayout {
            id: captureRow
            anchors { fill: parent; leftMargin: 10; rightMargin: 6; topMargin: 6; bottomMargin: 6 }
            spacing: 4
            MaterialSymbol { text: "screenshot_region"; iconSize: 18; color: Appearance?.colors.colPrimary ?? "#65558F" }
            StyledText { text: "Capture"; font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.DemiBold; Layout.fillWidth: true }
            CaptureButton { iconName: "crop"; label: "Shot"; onClicked: { root.closeRequested(); Screenshot.capture("region", 0) } }
            CaptureButton { iconName: "match_case"; label: "Text"; onClicked: { root.closeRequested(); Screenshot.capture("ocr", 0) } }
            CaptureButton {
                visible: RecorderStatus.available
                iconName: RecorderStatus.isRecording ? "stop_circle" : "radio_button_checked"
                label: RecorderStatus.isRecording ? "Stop" : "Rec"
                onClicked: { root.closeRequested(); RecorderStatus.toggle("region") }
            }
        }
    }

    // System tray (controlPanel.tray)
    ControlPanelTray { Layout.fillWidth: true }

    // System gauges (compact)
    RowLayout {
        Layout.fillWidth: true; spacing: 8
        CombinedCircularProgress {
            implicitSize: 40; outerLineWidth: 3; innerLineWidth: 3
            outerValue: ResourceUsage.cpuUsage; innerValue: ResourceUsage.memoryUsedPercentage
        }
        ColumnLayout {
            Layout.fillWidth: true; spacing: 0
            StyledText { text: `CPU ${Math.round(ResourceUsage.cpuUsage * 100)}% • RAM ${Math.round(ResourceUsage.memoryUsedPercentage * 100)}%`; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" }
            StyledText { text: `Up ${DateTime.uptime}`; font.pixelSize: Appearance.font.pixelSize.smallest; opacity: 0.3 }
        }
        Loader {
            active: Battery.available; visible: active
            sourceComponent: RowLayout {
                spacing: 4
                CircularProgress { implicitSize: 24; lineWidth: 2; value: Battery.percentage; colPrimary: Battery.isCharging ? Appearance.colors.colSuccess : Appearance?.colors.colPrimary ?? "#65558F" }
                StyledText { text: `${Math.round(Battery.percentage * 100)}%`; font.pixelSize: Appearance.font.pixelSize.smaller; font.family: Appearance?.font.family.mono ?? "monospace" }
            }
        }
    }

    // Power row
    RowLayout {
        Layout.fillWidth: true; spacing: 6
        Item { Layout.fillWidth: true }
        ToolbarButton { iconName: "lock"; iconSize: 18; toolTipText: "Lock"; onClicked: { root.closeRequested(); Quickshell.execDetached(["loginctl", "lock-session"]) } }
        ToolbarButton { iconName: "power_settings_new"; iconSize: 18; toolTipText: "Session"; onClicked: { root.closeRequested(); GlobalStates.sessionOpen = true } }
    }

    component CaptureButton: RippleButton {
        property string iconName: ""
        property string label: ""
        implicitHeight: 30
        implicitWidth: capRow.implicitWidth + 16
        buttonRadius: Appearance?.rounding.small ?? 8
        contentItem: RowLayout {
            id: capRow
            spacing: 4
            MaterialSymbol { text: iconName; iconSize: 16; color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5" }
            StyledText { text: label; font.pixelSize: Appearance.font.pixelSize.smaller }
        }
    }

    component CPToggle: Rectangle {
        property string iconName: ""; property string label: ""; property bool active: false
        signal clicked()
        signal secondaryClicked()
        Layout.fillWidth: true; implicitHeight: 44
        radius: Appearance?.rounding.small ?? 8
        color: active ? Qt.rgba((Appearance?.colors.colPrimary ?? "#65558F").r, (Appearance?.colors.colPrimary ?? "#65558F").g, (Appearance?.colors.colPrimary ?? "#65558F").b, 0.2) : Appearance?.colors.colLayer1 ?? "#E5E1EC"
        border.width: active ? 1 : 0; border.color: Appearance?.colors.colPrimary ?? "#65558F"
        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(150) } }
        ColumnLayout { anchors.centerIn: parent; spacing: 1
            MaterialSymbol { text: iconName; iconSize: 18; fill: active ? 1 : 0; color: active ? Appearance?.colors.colPrimary ?? "#65558F" : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"; Layout.alignment: Qt.AlignHCenter }
            StyledText { text: label; font.pixelSize: Appearance.font.pixelSize.smallest; font.weight: Font.DemiBold; elide: Text.ElideRight; Layout.maximumWidth: 80; Layout.alignment: Qt.AlignHCenter; color: active ? Appearance?.colors.colPrimary ?? "#65558F" : Appearance?.colors.colOnLayer1 ?? "#E6E1E5" }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: mouse => mouse.button === Qt.RightButton ? parent.secondaryClicked() : parent.clicked() }
    }
}
