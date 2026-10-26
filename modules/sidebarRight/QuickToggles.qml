import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "."

/**
 * Quick toggle grid — WiFi, Bluetooth, DND, Idle inhibit, Night light.
 * Inspired by ilyamiro's SysPill system and Android-style toggle panels.
 */
Rectangle {
    id: root
    property bool nightLightExpanded: false
    property bool networkExpanded: false
    property bool bluetoothExpanded: false
    property bool easyEffectsExpanded: false

    implicitHeight: contentCol.implicitHeight + 16
    radius: Appearance?.rounding.normal ?? 12
    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

    ColumnLayout {
        id: contentCol
        anchors { fill: parent; margins: 8 }
        spacing: 6

    GridLayout {
        id: toggleGrid
        Layout.fillWidth: true
        columns: 3; columnSpacing: 6; rowSpacing: 6

        // WiFi — tap toggles, chevron opens the network detail panel (pick a
        // network). Toggling here just turns the radio on/off.
        TogglePill {
            iconName: Network.materialSymbol
            label: Network.wifi ? Network.networkName : (Network.wifiEnabled ? "Disconnected" : "Off")
            tooltip: Network.wifi
                ? `Wi-Fi: ${Network.networkName} · tap to turn off, ▾ for networks`
                : "Wi-Fi off · tap to turn on"
            active: Network.wifi
            activeColor: Appearance?.colors.colPrimary ?? "#65558F"
            onClicked: Network.toggleWifi()
            showChevron: true
            chevronRotation: root.networkExpanded ? 180 : 0
            onChevronClicked: {
                if (GlobalStates.networkOrbitStyle) GlobalStates.openNetworkOrbit("wifi")
                else root.networkExpanded = !root.networkExpanded
            }
            Layout.fillWidth: true
        }

        // Hotspot — broadcasts a WiFi network from this machine. SSID +
        // password configured via Config.options.network.hotspot. Password
        // auto-generated on first enable when empty.
        TogglePill {
            iconName: Network.hotspotActive ? "wifi_tethering" : "wifi_tethering_off"
            label: Network.hotspotBusy ? "..." : (Network.hotspotActive ? "Hotspot" : "Off")
            tooltip: Network.hotspotActive ? "Wi-Fi hotspot on · tap to stop" : "Wi-Fi hotspot off · tap to broadcast"
            active: Network.hotspotActive
            activeColor: Appearance.colors.colWarning
            onClicked: Network.toggleHotspot()
            Layout.fillWidth: true
        }

        // Bluetooth — tap toggles the adapter on/off (had no handler before).
        TogglePill {
            iconName: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            label: BluetoothStatus.connected ? `${BluetoothStatus.activeDeviceCount} dev` : (BluetoothStatus.enabled ? "On" : "Off")
            tooltip: BluetoothStatus.connected
                ? `Bluetooth: ${BluetoothStatus.activeDeviceCount} connected · tap to turn off`
                : (BluetoothStatus.enabled ? "Bluetooth on · tap to turn off" : "Bluetooth off · tap to turn on")
            active: BluetoothStatus.connected || BluetoothStatus.enabled
            activeColor: Appearance.colors.colTertiary
            visible: BluetoothStatus.available
            onClicked: {
                const adapter = Bluetooth.defaultAdapter
                if (adapter) adapter.enabled = !adapter.enabled
            }
            showChevron: true
            chevronRotation: root.bluetoothExpanded ? 180 : 0
            onChevronClicked: {
                if (GlobalStates.networkOrbitStyle) GlobalStates.openNetworkOrbit("bt")
                else root.bluetoothExpanded = !root.bluetoothExpanded
            }
            Layout.fillWidth: true
        }

        // DND
        TogglePill {
            iconName: Notifications.silent ? "notifications_paused" : "notifications_active"
            label: Notifications.silent ? "Silent" : "Alerts"
            tooltip: Notifications.silent ? "Do Not Disturb on · tap to allow alerts" : "Alerts on · tap for Do Not Disturb"
            active: Notifications.silent
            activeColor: Appearance.colors.colWarning
            onClicked: Notifications.silent = !Notifications.silent
            Layout.fillWidth: true
        }

        // Idle inhibit
        TogglePill {
            iconName: Idle.inhibit ? "coffee" : "coffee_maker"
            label: Idle.inhibit ? "Awake" : "Idle"
            tooltip: Idle.inhibit ? "Keeping screen awake · tap to allow idle" : "Screen may sleep · tap to keep awake"
            active: Idle.inhibit
            activeColor: Appearance.colors.colInfo
            onClicked: Idle.toggleInhibit()
            Layout.fillWidth: true
        }

        // EasyEffects: tap toggles the global bypass, chevron picks a preset
        TogglePill {
            visible: EasyEffects.enabled && EasyEffects.available
            iconName: "graphic_eq"
            label: EasyEffects.bypassed ? "Bypass" : (EasyEffects.currentPreset || "Effects")
            tooltip: EasyEffects.bypassed ? "EasyEffects bypassed · tap to turn effects back on, ▾ for presets"
                : `EasyEffects: ${EasyEffects.currentPreset || "on"} · tap to bypass, ▾ for presets`
            active: !EasyEffects.bypassed
            activeColor: Appearance.colors.colTertiary
            onClicked: EasyEffects.toggleBypass()
            showChevron: true
            chevronRotation: root.easyEffectsExpanded ? 180 : 0
            onChevronClicked: root.easyEffectsExpanded = !root.easyEffectsExpanded
            Layout.fillWidth: true
        }

        // Performance mode (GameMode.qml)
        TogglePill {
            iconName: "speed"
            label: GameMode.performance ? "Perf" : "Normal"
            tooltip: GameMode.performance
                ? (GameMode.manual ? "Performance mode on by hand · tap to turn off"
                    : `Performance mode on while ${GameMode.performanceReason} · tap to keep it on afterwards`)
                : "Performance mode off · tap to pause motion, blur and visualisers"
            active: GameMode.performance
            activeColor: Appearance.colors.colWarning
            onClicked: GameMode.toggle()
            Layout.fillWidth: true
        }

        // Night light — tap pill to toggle, chevron to expand inline slider
        TogglePill {
            iconName: NightLight.enabled || NightLight.scheduled ? "nightlight" : "wb_sunny"
            label: NightLight.enabled ? `${NightLight.nightTemp}K`
                : NightLight.scheduled ? NightLight.scheduleText : "Day"
            active: NightLight.enabled
            activeColor: Appearance.colors.colWarning
            tooltip: NightLight.enabled ? `Night light on (${NightLight.nightTemp}K) · tap to turn off, ▾ to adjust`
                : NightLight.scheduled ? `Night light automatic (${NightLight.scheduleText}) · tap to turn on now`
                : "Night light off · tap to warm the screen"
            onClicked: NightLight.toggle()
            showChevron: true
            chevronRotation: root.nightLightExpanded ? 180 : 0
            onChevronClicked: root.nightLightExpanded = !root.nightLightExpanded
            Layout.fillWidth: true
        }

        // Eye-care screen filter (where the compositor takes a screen shader)
        TogglePill {
            visible: ScreenFilters.supported
            iconName: ScreenFilters.mode === "none" ? "filter_none" : "filter_vintage"
            label: ScreenFilters.mode === "none" ? "Filter" : (ScreenFilters.modes.find(m => m.id === ScreenFilters.mode)?.label ?? "Filter")
            active: ScreenFilters.mode !== "none"
            tooltip: ScreenFilters.mode === "none" ? `Tap for ${ScreenFilters.lastMode}` : "Tap to turn the filter off"
            onClicked: ScreenFilters.toggle()
            Layout.fillWidth: true
        }

        // Battery (if laptop)
        Loader {
            Layout.fillWidth: true
            active: Battery.available
            visible: active
            sourceComponent: TogglePill {
                iconName: Battery.isCharging ? "battery_charging_full" : (Battery.percentage > 0.2 ? "battery_full" : "battery_alert")
                label: `${Math.round(Battery.percentage * 100)}%`
                tooltip: Battery.isCharging ? `Battery ${Math.round(Battery.percentage * 100)}% · charging` : `Battery ${Math.round(Battery.percentage * 100)}%`
                active: Battery.isCharging
                activeColor: Appearance.colors.colSuccess
            }
        }

        // Keyboard layout
        Loader {
            Layout.fillWidth: true
            active: KeyboardLayoutService.layoutCodes.length > 1
            visible: active
            sourceComponent: TogglePill {
                iconName: "keyboard"
                label: KeyboardLayoutService.currentLayoutCode.toUpperCase()
                tooltip: `Keyboard layout: ${KeyboardLayoutService.currentLayoutName ?? KeyboardLayoutService.currentLayoutCode}`
                active: false
            }
        }
    }

        // ── Wi-Fi network picker (inline expander) ──
        // The WiFi pill's chevron reveals the list of nearby networks to connect.
        Item {
            Layout.fillWidth: true
            clip: true
            implicitHeight: root.networkExpanded ? netPicker.implicitHeight + 8 : 0
            opacity: root.networkExpanded ? 1 : 0
            // A spring: the lists grow as scan results arrive, and a timed animation restarted on each.
            Behavior on implicitHeight { MotionSpring { token: "settle" } }
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }

            WifiNetworkPicker {
                id: netPicker
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4 }
            }
        }

        // ── Bluetooth device picker (inline expander) ──
        Item {
            Layout.fillWidth: true
            clip: true
            implicitHeight: root.bluetoothExpanded ? btPicker.implicitHeight + 8 : 0
            opacity: root.bluetoothExpanded ? 1 : 0
            // A spring: the lists grow as scan results arrive, and a timed animation restarted on each.
            Behavior on implicitHeight { MotionSpring { token: "settle" } }
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }

            BluetoothDevicePicker {
                id: btPicker
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4 }
            }
        }

        // ── EasyEffects output presets (inline expander) ──
        Item {
            Layout.fillWidth: true
            clip: true
            readonly property bool open: root.easyEffectsExpanded && EasyEffects.available
            implicitHeight: open ? Math.min(presetCol.implicitHeight, 220) + 8 : 0
            opacity: open ? 1 : 0
            Behavior on implicitHeight { MotionSpring { token: "settle" } }
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }

            StyledFlickable {
                anchors { fill: parent; topMargin: 4 }
                contentHeight: presetCol.implicitHeight
                clip: true
                ColumnLayout {
                    id: presetCol
                    width: parent.width
                    spacing: 2
                    Repeater {
                        model: EasyEffects.presets
                        delegate: RippleButton {
                            required property string modelData
                            Layout.fillWidth: true
                            implicitHeight: 32
                            toggled: modelData === EasyEffects.currentPreset
                            buttonText: modelData
                            onClicked: EasyEffects.loadPreset(modelData)
                        }
                    }
                }
            }
        }

        // ── Night light inline expander ──
        // Animated reveal of a temperature slider when the night-light pill's
        // chevron is tapped. Stays out of the layout entirely when collapsed.
        Item {
            Layout.fillWidth: true
            clip: true
            implicitHeight: root.nightLightExpanded ? expanderCol.implicitHeight + 8 : 0
            opacity: root.nightLightExpanded ? 1 : 0
            // A spring: the lists grow as scan results arrive, and a timed animation restarted on each.
            Behavior on implicitHeight { MotionSpring { token: "settle" } }
            Behavior on opacity { NumberAnimation { duration: AnimationConfig.scaledDuration(180) } }

            ColumnLayout {
                id: expanderCol
                anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 4 }
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    MaterialSymbol {
                        text: "thermostat"; iconSize: 16
                        color: Appearance?.colors.colSubtext ?? "#CAC4D0"
                    }
                    StyledText {
                        text: `${NightLight.nightTemp}K`
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        font.family: Appearance?.font.family.numbers
                        color: NightLight.enabled
                            ? Appearance.colors.colWarning
                            : (Appearance?.colors.colOnLayer1 ?? "#E6E1E5")
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: NightLight.enabled ? "On" : "Off"
                        font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                        opacity: 0.7
                        color: Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                    }
                }

                Slider {
                    id: tempSlider
                    Layout.fillWidth: true
                    from: 2500; to: 6500; stepSize: 100
                    value: NightLight.nightTemp
                    onMoved: Config.setNestedValue("nightLight.nightTemp", Math.round(value))
                }
            }
        }
    }

    // Toggle pill component
    component TogglePill: Rectangle {
        id: pill
        property string iconName: ""
        property string label: ""
        property string tooltip: ""       // hover hint — what this toggle is/does
        property bool active: false
        property color activeColor: Appearance?.colors.colPrimary ?? "#65558F"
        property bool showChevron: false
        property real chevronRotation: 0
        signal clicked()
        signal chevronClicked()

        implicitHeight: 44
        // Morphs: a full pill while on, a rounded tile while off (springs between).
        radius: active ? height / 2 : (Appearance?.rounding.small ?? 8)
        Behavior on radius { MotionSpring { token: "snappy" } }
        scale: pillMouse.pressed ? 0.95 : 1
        Behavior on scale { MotionSpring { token: "snappy" } }
        color: active ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.2) : Appearance?.colors.colLayer2 ?? "#2B2930"
        border.width: active ? 1 : 0
        border.color: Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.4)

        Behavior on color { ColorAnimation { duration: AnimationConfig.scaledDuration(200) } }

        RowLayout {
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                text: pill.iconName; iconSize: 18
                fill: pill.active ? 1 : 0
                color: pill.active ? pill.activeColor : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
            }
            StyledText {
                text: pill.label
                font.pixelSize: Appearance?.font.pixelSize.smaller ?? 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.maximumWidth: pill.showChevron ? 50 : 70
                color: pill.active ? pill.activeColor : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
            }
            MaterialSymbol {
                id: chevronIcon
                visible: pill.showChevron
                text: "expand_more"; iconSize: 16
                rotation: pill.chevronRotation
                color: pill.active ? pill.activeColor : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
                Behavior on rotation { NumberAnimation { duration: AnimationConfig.scaledDuration(200); easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel } }
            }
        }

        // ONE hit area for the whole pill: left-click expands (when there's an
        // expander), right-click toggles. Splitting the pill into a toggle zone and
        // a chevron strip was a coin toss to aim at — the RowLayout is
        // centreInParent, so the visible chevron never lined up with a fixed
        // right-edge band and clicks landed on the wrong action. Button-based
        // dispatch removes the geometry from the equation.
        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: event => {
                if (event.button === Qt.LeftButton && pill.showChevron)
                    pill.chevronClicked()
                else
                    pill.clicked()
            }

            StyledToolTip {
                text: pill.showChevron && pill.tooltip.length > 0
                    ? `${pill.tooltip} — right-click to toggle`
                    : pill.tooltip
                extraVisibleCondition: pill.tooltip.length > 0 && pillMouse.containsMouse
            }
        }
    }
}
