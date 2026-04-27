import QtQuick
import QtQuick.Layouts
import "root:modules/common"
import "root:modules/common/widgets"
import "root:services"

/**
 * Quick toggle grid — WiFi, Bluetooth, DND, Idle inhibit, Night light.
 * Inspired by ilyamiro's SysPill system and Android-style toggle panels.
 */
Rectangle {
    id: root
    implicitHeight: toggleGrid.implicitHeight + 16
    radius: Appearance?.rounding.normal ?? 12
    color: Appearance?.colors.colLayer1 ?? "#E5E1EC"

    GridLayout {
        id: toggleGrid
        anchors { fill: parent; margins: 8 }
        columns: 3; columnSpacing: 6; rowSpacing: 6

        // WiFi
        TogglePill {
            iconName: Network.materialSymbol
            label: Network.wifi ? Network.networkName : (Network.wifiEnabled ? "Disconnected" : "Off")
            active: Network.wifi
            activeColor: Appearance?.colors.colPrimary ?? "#65558F"
            onClicked: Network.toggleWifi()
            Layout.fillWidth: true
        }

        // Bluetooth
        TogglePill {
            iconName: BluetoothStatus.connected ? "bluetooth_connected" : BluetoothStatus.enabled ? "bluetooth" : "bluetooth_disabled"
            label: BluetoothStatus.connected ? `${BluetoothStatus.activeDeviceCount} dev` : (BluetoothStatus.enabled ? "On" : "Off")
            active: BluetoothStatus.connected
            activeColor: "#B388FF"
            visible: BluetoothStatus.available
            Layout.fillWidth: true
        }

        // DND
        TogglePill {
            iconName: Notifications.silent ? "notifications_paused" : "notifications_active"
            label: Notifications.silent ? "Silent" : "Alerts"
            active: Notifications.silent
            activeColor: "#FFB74D"
            onClicked: Notifications.silent = !Notifications.silent
            Layout.fillWidth: true
        }

        // Idle inhibit
        TogglePill {
            iconName: Idle.inhibit ? "coffee" : "coffee_maker"
            label: Idle.inhibit ? "Awake" : "Idle"
            active: Idle.inhibit
            activeColor: "#4DB6AC"
            onClicked: Idle.toggleInhibit()
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
                active: Battery.isCharging
                activeColor: "#81C784"
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
                active: false
            }
        }
    }

    // Toggle pill component
    component TogglePill: Rectangle {
        id: pill
        property string iconName: ""
        property string label: ""
        property bool active: false
        property color activeColor: Appearance?.colors.colPrimary ?? "#65558F"
        signal clicked()

        implicitHeight: 44
        radius: Appearance?.rounding.small ?? 8
        color: active ? Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.2) : Appearance?.colors.colLayer2 ?? "#2B2930"
        border.width: active ? 1 : 0
        border.color: Qt.rgba(activeColor.r, activeColor.g, activeColor.b, 0.4)

        Behavior on color { ColorAnimation { duration: 200 } }

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
                Layout.maximumWidth: 70
                color: pill.active ? pill.activeColor : Appearance?.colors.colOnLayer1 ?? "#E6E1E5"
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }
}
