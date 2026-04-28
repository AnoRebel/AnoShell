pragma Singleton
import QtQuick

/**
 * Maps module name strings to QML components.
 * This is used by BarContent to dynamically load modules based on config.
 */
QtObject {
    id: root

    function getModule(name) {
        switch (name) {
            case "clock": return clockModule
            case "workspaces": return workspacesModule
            case "battery": return batteryModule
            case "network": return networkModule
            case "bluetooth": return bluetoothModule
            case "tray": return trayModule
            case "media": return mediaModule
            case "resources": return resourcesModule
            case "activeWindow": return activeWindowModule
            case "sidebarButton": return sidebarButtonModule
            case "weather": return weatherModule
            case "keyboard": return keyboardModule
            case "keyboardLayout": return keyboardModule  // alias — same module, both IDs accepted
            case "notifications": return notificationsModule
            case "idle": return idleModule
            case "privacy": return privacyModule
            case "gamemode": return gameModeModule
            default:
                console.warn(`[BarModuleLoader] Unknown module: ${name}`)
                return null
        }
    }

    property Component clockModule: Component { ClockModule {} }
    property Component workspacesModule: Component { WorkspacesModule {} }
    property Component batteryModule: Component { BatteryModule {} }
    property Component networkModule: Component { NetworkModule {} }
    property Component bluetoothModule: Component { BluetoothModule {} }
    property Component trayModule: Component { TrayModule {} }
    property Component mediaModule: Component { MediaModule {} }
    property Component resourcesModule: Component { ResourcesModule {} }
    property Component activeWindowModule: Component { ActiveWindowModule {} }
    property Component sidebarButtonModule: Component { SidebarButtonModule {} }
    property Component weatherModule: Component { WeatherModule {} }
    property Component keyboardModule: Component { KeyboardModule {} }
    property Component notificationsModule: Component { NotificationsModule {} }
    property Component idleModule: Component { IdleModule {} }
    property Component privacyModule: Component { PrivacyModule {} }
    property Component gameModeModule: Component { GameModeModule {} }
}
