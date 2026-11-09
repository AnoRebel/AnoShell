pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick
import qs.modules.common
import qs.services.network
import "root:services/network/NetLinks.js" as NetLinks

/**
 * Network service. Wi-Fi state (radio, status, connected network, signal,
 * the network list, hotspot mode) is read live from Quickshell.Networking
 * (NetworkManager over D-Bus); actions, scans, the hotspot toggle, VPN
 * profiles and the non-Wi-Fi links (ethernet, USB/Bluetooth tethering,
 * mobile broadband, which one carries the default route, NetLinks.js) use
 * nmcli. `nmcli monitor` only refreshes the nmcli lists a line concerns
 * (NetLinks.monitorScope), so Wi-Fi and container churn spawn nothing.
 */
Singleton {
    id: root

    // The first Wi-Fi device (Quickshell.Networking WifiDevice), or null.
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wifiIfaces: Networking.devices.values.filter(d => d.type === DeviceType.Wifi).map(d => d.name)

    property bool wifi: wifiStatus === "connected"
    // A real wired link (ethernet or USB tether) is up; containers, VMs,
    // bridges and tunnels don't count (NetLinks.isVirtual).
    readonly property bool ethernet: links.some(l => l.connected && (l.kind === "ethernet" || l.kind === "usb"))
    // [{ device, iface, kind, icon, title, state, connected, ip, primary }]:
    // usable non-Wi-Fi links, the one carrying traffic first. Refreshed on
    // `nmcli monitor` events about a non-Wi-Fi device or the primary connection.
    property var links: []
    readonly property var primaryLink: links.find(l => l.primary) ?? null
    property string linkBusy: ""      // device a connect/disconnect is running on
    property string linkError: ""     // last failure, "<device>: <nmcli message>"
    // NetworkManager VPN and WireGuard profiles: [{ name, uuid, type, state, active }]
    // (NetLinks.vpns), refreshed on `nmcli monitor` profile / tunnel events.
    property var vpnConnections: []
    readonly property var activeVpn: vpnConnections.find(v => v.active) ?? null
    property string vpnBusy: ""       // uuid an up/down is running on
    property string vpnError: ""      // last failure, "<name>: <nmcli message>"
    property bool wifiEnabled: Networking.wifiEnabled
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget

    // Hotspot — on while the Wi-Fi device runs in access-point mode.
    // Toggled via nmcli device wifi hotspot / nmcli connection down.
    property bool hotspotActive: wifiDevice?.mode === WifiDeviceMode.AccessPoint
    property bool hotspotBusy: hotspotToggleProc.running
    // Replaced as a whole on each scan (never edited in place), so no binding
    // sees an entry that is being destroyed.
    property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active) return -1
        if (!a.active && b.active) return 1
        return b.strength - a.strength
    })
    // "connected" | "limited" (connected, no internet) | "connecting" | "disabled" | "disconnected"
    property string wifiStatus: {
        const d = root.wifiDevice
        if (!d) return "disconnected"
        if (!Networking.wifiEnabled || !Networking.wifiHardwareEnabled) return "disabled"
        if (d.state === ConnectionState.Connected)
            return Networking.connectivity === NetworkConnectivity.Limited ? "limited" : "connected"
        if (d.state === ConnectionState.Connecting) return "connecting"
        return "disconnected"
    }
    // The connected Wi-Fi network, else the link carrying traffic.
    property string networkName: active?.ssid ?? primaryLink?.title ?? ""
    property int networkStrength: active?.strength ?? 0

    property string materialSymbol: root.primaryLink
        ? root.primaryLink.icon
        : root.ethernet
        ? "lan"
        : root.wifiEnabled
            ? (networkStrength > 83 ? "signal_wifi_4_bar" :
               networkStrength > 67 ? "network_wifi" :
               networkStrength > 50 ? "network_wifi_3_bar" :
               networkStrength > 33 ? "network_wifi_2_bar" :
               networkStrength > 17 ? "network_wifi_1_bar" :
               "signal_wifi_0_bar")
            : (wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (wifiStatus === "disconnected")
                    ? "wifi_find"
                    : (wifiStatus === "disabled")
                        ? "signal_wifi_off"
                        : "signal_wifi_bad"

    // Controls
    function enableWifi(enabled = true): void {
        enableWifiProc.exec(["nmcli", "radio", "wifi", enabled ? "on" : "off"])
    }
    function toggleWifi(): void { enableWifi(!wifiEnabled) }

    function rescanWifi(): void {
        wifiScanning = true
        rescanProcess.running = true
    }

    function connectToWifiNetwork(accessPoint): void {
        accessPoint.askingPassword = false
        root.wifiConnectTarget = accessPoint
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid])
    }

    // Connect with a password typed into a UI (SSID and password are separate
    // argv elements, never part of a shell string). A wrong password leaves
    // the access point asking for one again (askingPassword).
    function connectToWifiNetworkWithPassword(accessPoint, password: string): void {
        accessPoint.askingPassword = false
        root.wifiConnectTarget = accessPoint
        connectProc.exec(["nmcli", "dev", "wifi", "connect", accessPoint.ssid, "password", password])
    }

    function disconnectWifiNetwork(): void {
        if (active) disconnectProc.exec(["nmcli", "connection", "down", active.ssid])
    }

    function forgetWifiNetwork(accessPoint): void {
        forgetProc.exec(["nmcli", "connection", "delete", accessPoint.ssid])
    }

    function isVirtualIface(name: string): bool { return NetLinks.isVirtual(name) }

    // Connect or disconnect a wired / tether link. The device must be one
    // of `links` (it is only ever an argv element).
    function setLinkConnected(device: string, on: bool): void {
        if (linkProc.running || !root.links.some(l => l.device === device)) return
        root.linkBusy = device
        root.linkError = ""
        linkProc.exec(["nmcli", "device", on ? "connect" : "disconnect", device])
    }

    // Bring a VPN profile up or down. The uuid must be one of
    // vpnConnections and is only ever an argv element.
    function setVpnActive(uuid: string, on: bool): void {
        const v = root.vpnConnections.find(c => c.uuid === uuid)
        if (vpnToggleProc.running || !v) return
        root.vpnBusy = uuid
        root.vpnError = ""
        vpnToggleProc.vpnName = v.name
        vpnToggleProc.exec(["nmcli", "connection", on ? "up" : "down", "uuid", uuid])
    }

    Process {
        id: vpnToggleProc
        property string vpnName: ""
        environment: ({ LANG: "C", LC_ALL: "C" })
        stderr: StdioCollector { id: vpnErr }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.vpnError = `${vpnToggleProc.vpnName}: ${vpnErr.text.trim().split("\n").pop().replace(/^Error: /, "") || "nmcli failed"}`
            root.vpnBusy = ""
            if (exitCode !== 0) root.vpnConnections = root.vpnConnections.slice() // switches back to the real state
            vpnProc.running = true
        }
    }

    Process {
        id: vpnProc
        running: true
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,STATE", "connection", "show"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                const v = NetLinks.vpns(this.text)
                if (JSON.stringify(v) !== JSON.stringify(root.vpnConnections)) root.vpnConnections = v
            }
        }
    }

    Process {
        id: linkProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        stderr: StdioCollector { id: linkErr }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.linkError = `${root.linkBusy}: ${linkErr.text.trim().replace(/^Error: /, "") || "nmcli failed"}`
            root.linkBusy = ""
            linksProc.running = true
        }
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"])
    }

    // Hotspot — read SSID + password from
    //   Config.options.network.hotspot.{ssid, password}
    // Generates a random 12-char alphanumeric password on first enable
    // when none is configured, and persists it back to config.
    function _generateHotspotPassword() {
        const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
        let p = ""
        for (let i = 0; i < 12; i++)
            p += chars[Math.floor(Math.random() * chars.length)]
        return p
    }

    function toggleHotspot(): void {
        const ssid = (Config.options?.network?.hotspot?.ssid ?? "").trim() || "AnoHotspot"
        let password = (Config.options?.network?.hotspot?.password ?? "").trim()
        if (root.hotspotActive) {
            // Bring it down by name. We don't know the connection's exact
            // nmcli name (nmcli auto-names hotspot connections "Hotspot"
            // by default), so try the configured SSID first, then "Hotspot".
            hotspotToggleProc.command = ["bash", "-c",
                `nmcli connection down ${JSON.stringify(ssid)} 2>/dev/null || ` +
                `nmcli connection down Hotspot 2>/dev/null || true`]
        } else {
            // Generate + persist a password if none.
            if (password.length === 0) {
                password = root._generateHotspotPassword()
                Config.setNestedValue("network.hotspot.password", password)
            }
            // Persist the SSID too if it was empty (we used the default).
            if ((Config.options?.network?.hotspot?.ssid ?? "").trim().length === 0)
                Config.setNestedValue("network.hotspot.ssid", ssid)
            hotspotToggleProc.command = ["nmcli", "device", "wifi", "hotspot",
                "ssid", ssid, "password", password]
        }
        hotspotToggleProc.running = true
    }

    Process { id: hotspotToggleProc }

    function changePassword(network, password, username = ""): void {
        network.askingPassword = false
        changePasswordProc.exec({
            "environment": { "PASSWORD": password, "SSID": network.ssid },
            "command": ["bash", "-c", 'nmcli connection modify "$SSID" wifi-sec.psk "$PASSWORD"']
        })
    }

    Process { id: enableWifiProc }

    Process {
        id: connectProc
        environment: ({ LANG: "C", LC_ALL: "C" })
        stderr: SplitParser {
            onRead: line => {
                if (line.includes("Secrets were required") && root.wifiConnectTarget) root.wifiConnectTarget.askingPassword = true
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (root.wifiConnectTarget) root.wifiConnectTarget.askingPassword = (exitCode !== 0)
            root.wifiConnectTarget = null
        }
    }

    // The network list is live (Quickshell.Networking): no refresh after these.
    Process { id: disconnectProc }
    Process { id: forgetProc }
    Process {
        id: changePasswordProc
        onExited: { connectProc.running = false; connectProc.running = true }
    }
    // A real scan; NetworkManager then updates the live list. Its output
    // also refreshes the BSSID / frequency details.
    Process {
        id: rescanProcess
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID", "d", "w", "list", "--rescan", "yes"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: root._apExtra = root._parseApList(text) }
        onExited: root.wifiScanning = false
    }

    // ── Wi-Fi network list (Quickshell.Networking) ──────────────────────
    // Visible networks only (NetworkManager also lists saved ones that are
    // out of range, at 0 %). Keyed on the SSID set, so a signal change
    // doesn't rebuild the list (a QML string property only notifies on a
    // real change).
    readonly property string _visibleKey: (wifiDevice?.networks.values ?? [])
        .filter(n => n.name && (n.signalStrength > 0 || n.connected)).map(n => n.name).join("\n")
    on_VisibleKeyChanged: _rebuildNetworks()
    // Also when the model's objects change under the same names, so no
    // entry keeps a destroyed WifiNetwork.
    Connections {
        target: root.wifiDevice?.networks ?? null
        function onValuesChanged() { root._rebuildNetworks() }
    }

    // { ssid: { bssid, frequency } } from the cached `nmcli d w list`: the
    // only Wi-Fi fields Quickshell.Networking doesn't have. Read at startup,
    // on every scan and when the connected network changes.
    property var _apExtra: ({})
    readonly property string _activeSsid: active?.ssid ?? ""
    on_ActiveSsidChanged: apInfoProc.running = true

    function _rebuildNetworks(): void {
        const nets = (wifiDevice?.networks.values ?? []).filter(n => n.name && (n.signalStrength > 0 || n.connected))
        const old = Array.from(root.wifiNetworks)
        const next = []
        for (const n of nets) {
            if (next.some(a => a.ssid === n.name)) continue
            const match = old.find(a => a.ssid === n.name)
            if (match) { match.network = n; next.push(match) }
            else {
                const ssid = n.name
                next.push(apComp.createObject(root, { ssid: ssid, network: n, extra: Qt.binding(() => root._apExtra[ssid] ?? {}) }))
            }
        }
        if (next.length === old.length && next.every((a, i) => a === old[i])) return
        const gone = old.filter(a => !next.includes(a))
        // Replaced as a whole, never edited in place.
        root.wifiNetworks = next
        // Destroyed once nothing lists them any more.
        Qt.callLater(() => gone.forEach(a => a.destroy()))
    }

    // `nmcli -g ACTIVE,SIGNAL,FREQ,SSID,BSSID d w list` → { ssid: { bssid, frequency } },
    // the active (else strongest) access point per SSID. `-g` escapes ":" as "\:".
    function _parseApList(text: string): var {
        const out = {}, best = {}
        for (const line of text.trim().split("\n")) {
            const f = line.replace(/\\:/g, "\u0001").split(":").map(x => x.replace(/\u0001/g, ":"))
            if (f.length < 5 || !f[3]) continue
            const ap = { active: f[0] === "yes", strength: parseInt(f[1]) || 0, frequency: parseInt(f[2]) || 0, bssid: f[4] }
            const cur = best[f[3]]
            if (!cur || (ap.active && !cur.active) || (!ap.active && !cur.active && ap.strength > cur.strength)) best[f[3]] = ap
        }
        for (const ssid in best) out[ssid] = { bssid: best[ssid].bssid, frequency: best[ssid].frequency }
        return out
    }

    Process {
        id: apInfoProc
        running: true
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID", "d", "w", "list", "--rescan", "no"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: root._apExtra = root._parseApList(text) }
    }

    Component { id: apComp; WifiAccessPoint {} }

    // ── nmcli-backed lists: links (NetLinks.parse) and VPN profiles ─────

    // One nmcli read of every device plus the default route, parsed in
    // NetLinks.js. A constant script: nothing is interpolated into it.
    Process {
        id: linksProc
        running: true
        command: ["sh", "-c", "nmcli -t -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,GENERAL.IP-IFACE,GENERAL.DRIVER,GENERAL.PRODUCT,IP4.ADDRESS device show; echo '@@ROUTES@@'; ip -j route show default"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("@@ROUTES@@")
                const links = NetLinks.parse(parts[0], parts[1] ?? "").links
                if (JSON.stringify(links) !== JSON.stringify(root.links)) root.links = links
            }
        }
    }

    // `nmcli monitor` prints events in bursts; a burst is coalesced into one
    // refresh of only the lists its lines concern (NetLinks.monitorScope).
    property bool _linksDirty: false
    property bool _vpnDirty: false
    Timer {
        id: updateDebounce
        interval: 300
        onTriggered: {
            if (root._linksDirty) linksProc.running = true
            if (root._vpnDirty) vpnProc.running = true
            root._linksDirty = root._vpnDirty = false
        }
    }

    Process {
        id: subscriber
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", "nmcli", "monitor"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: SplitParser {
            onRead: line => {
                const s = NetLinks.monitorScope(line, root.wifiIfaces)
                if (!s.links && !s.vpn) return
                if (s.links) root._linksDirty = true
                if (s.vpn) root._vpnDirty = true
                updateDebounce.restart()
            }
        }
    }
}
