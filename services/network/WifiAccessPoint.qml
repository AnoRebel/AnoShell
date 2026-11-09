import QtQuick
import Quickshell.Networking

// One Wi-Fi network (SSID) in Network.wifiNetworks, live from a
// Quickshell.Networking WifiNetwork. The BSSID and frequency are not in that
// API: Network.qml fills `extra` from an occasional `nmcli d w list`.
QtObject {
    required property string ssid
    required property var network      // Quickshell.Networking WifiNetwork; null once NM drops it
    property var extra: ({})           // { bssid, frequency }
    readonly property string bssid: extra?.bssid ?? ""
    readonly property int strength: Math.round((network?.signalStrength ?? 0) * 100)
    readonly property int frequency: extra?.frequency ?? 0
    readonly property bool active: network?.connected ?? false
    readonly property bool known: network?.known ?? false  // a saved profile exists
    // In nmcli's SECURITY format ("WPA2", "WPA3", "WPA2 802.1X", "" when open).
    readonly property string security: {
        switch (network?.security) {
        case WifiSecurityType.Wpa3SuiteB192: return "WPA3 802.1X"
        case WifiSecurityType.Sae: return "WPA3"
        case WifiSecurityType.Wpa2Eap: return "WPA2 802.1X"
        case WifiSecurityType.Wpa2Psk: return "WPA2"
        case WifiSecurityType.WpaEap: return "WPA1 802.1X"
        case WifiSecurityType.WpaPsk: return "WPA1"
        case WifiSecurityType.StaticWep:
        case WifiSecurityType.DynamicWep: return "WEP"
        case WifiSecurityType.Leap: return "802.1X"
        case WifiSecurityType.Owe: return "OWE"
        default: return ""
        }
    }
    readonly property bool isSecure: security.length > 0

    property bool askingPassword: false
    property string connectionError: ""
}
