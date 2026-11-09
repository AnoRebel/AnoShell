pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick
import qs.modules.common
import qs.services.network
import "root:services/network/NetLinks.js" as NetLinks

/**
 * Network service using nmcli. WiFi scanning, connecting, password management,
 * status monitoring, signal strength tracking, and a hotspot toggle.
 * Also the non-Wi-Fi links (ethernet, USB/Bluetooth tethering, mobile
 * broadband) and which one carries the default route (NetLinks.js).
 */
Singleton {
    id: root

    property bool wifi: true
    // A real wired link (ethernet or USB tether) is up; containers, VMs,
    // bridges and tunnels don't count (NetLinks.isVirtual).
    readonly property bool ethernet: links.some(l => l.connected && (l.kind === "ethernet" || l.kind === "usb"))
    // [{ device, iface, kind, icon, title, state, connected, ip, primary }]:
    // usable non-Wi-Fi links, the one carrying traffic first. Refreshed on
    // `nmcli monitor` events with the rest of the status.
    property var links: []
    readonly property var primaryLink: links.find(l => l.primary) ?? null
    property string linkBusy: ""      // device a connect/disconnect is running on
    property string linkError: ""     // last failure, "<device>: <nmcli message>"
    property bool wifiEnabled: false
    property bool wifiScanning: false
    property bool wifiConnecting: connectProc.running
    property WifiAccessPoint wifiConnectTarget

    // Hotspot — detected by polling `nmcli -t -f NAME,TYPE,DEVICE c show --active`
    // for a row of type `802-11-wireless` whose name is the configured SSID.
    // Toggled via nmcli device wifi hotspot / nmcli connection down.
    property bool hotspotActive: false
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
    property string wifiStatus: "disconnected"
    property string networkName: ""
    property int networkStrength

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

    Process {
        id: hotspotToggleProc
        onExited: (_, __) => hotspotPollProc.running = true
    }
    Process {
        id: hotspotPollProc
        // Look for an active connection of type 802-11-wireless whose name
        // looks like a hotspot. Matches the default "Hotspot" name and any
        // connection with the configured SSID.
        command: ["bash", "-c",
            "nmcli -t -f NAME,TYPE,DEVICE c show --active 2>/dev/null | " +
            "awk -F: '$2 == \"802-11-wireless\" { print $1 }'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const ssid = (Config.options?.network?.hotspot?.ssid ?? "").trim() || "AnoHotspot"
                const lines = (this.text || "").split("\n").map(l => l.trim()).filter(l => l)
                root.hotspotActive = lines.some(l => l === "Hotspot" || l === ssid)
            }
        }
    }

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
        stdout: SplitParser { onRead: line => { getNetworks.running = true } }
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

    Process { id: disconnectProc; stdout: SplitParser { onRead: getNetworks.running = true } }
    Process { id: forgetProc; stdout: SplitParser { onRead: getNetworks.running = true } }
    Process {
        id: changePasswordProc
        onExited: { connectProc.running = false; connectProc.running = true }
    }
    Process {
        id: rescanProcess
        command: ["nmcli", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: SplitParser { onRead: { wifiScanning = false; getNetworks.running = true } }
    }

    // Status monitoring
    function update() {
        updateConnectionType.startCheck()
        wifiStatusProcess.running = true
        updateNetworkName.running = true
        updateNetworkStrength.running = true
        linksProc.running = true
    }

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

    // `nmcli monitor` prints events in bursts; each refresh spawns several
    // nmcli queries, so coalesce a burst into one refresh (hotspot included).
    // Also runs once at startup. (Replaces a 5 s hotspot poll.)
    Timer {
        id: updateDebounce
        interval: 300
        running: true
        onTriggered: { root.update(); hotspotPollProc.running = true }
    }

    Process {
        id: subscriber
        running: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", "nmcli", "monitor"]
        stdout: SplitParser { onRead: updateDebounce.restart() }
    }

    Process {
        id: updateConnectionType
        property string buffer
        command: ["sh", "-c", "nmcli -t -f TYPE,STATE d status && nmcli -t -f CONNECTIVITY g"]
        running: true
        function startCheck() { buffer = ""; updateConnectionType.running = true }
        stdout: SplitParser { onRead: data => { updateConnectionType.buffer += data + "\n" } }
        onExited: (exitCode, exitStatus) => {
            const lines = updateConnectionType.buffer.trim().split('\n')
            const connectivity = lines.pop()
            let hasWifi = false; let ws = "disconnected"
            lines.forEach(line => {
                if (line.includes("wifi:")) {
                    if (line.includes("disconnected")) ws = "disconnected"
                    else if (line.includes("connected")) { hasWifi = true; ws = "connected"; if (connectivity === "limited") { hasWifi = false; ws = "limited" } }
                    else if (line.includes("connecting")) ws = "connecting"
                    else if (line.includes("unavailable")) ws = "disabled"
                }
            })
            root.wifiStatus = ws; root.wifi = hasWifi
        }
    }

    Process {
        id: updateNetworkName
        command: ["sh", "-c", "nmcli -t -f NAME c show --active | head -1"]
        running: true
        stdout: SplitParser { onRead: data => { root.networkName = data } }
    }

    Process {
        id: updateNetworkStrength
        running: true
        command: ["sh", "-c", "nmcli -f IN-USE,SIGNAL,SSID device wifi list --rescan no | awk '/^\\*/{if (NR!=1) {print $2}}'"]
        stdout: SplitParser { onRead: data => { root.networkStrength = parseInt(data) } }
    }

    Process {
        id: wifiStatusProcess
        command: ["nmcli", "radio", "wifi"]
        Component.onCompleted: running = true
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector { onStreamFinished: { root.wifiEnabled = text.trim() === "enabled" } }
    }

    Process {
        id: getNetworks
        running: true
        command: ["nmcli", "-g", "ACTIVE,SIGNAL,FREQ,SSID,BSSID,SECURITY", "d", "w", "list", "--rescan", "no"] // the cached list: scans happen on request (rescanProcess)
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                const PLACEHOLDER = "STRINGWHICHHOPEFULLYWONTBEUSED"
                const rep = new RegExp("\\\\:", "g")
                const rep2 = new RegExp(PLACEHOLDER, "g")

                const allNetworks = text.trim().split("\n").map(n => {
                    const net = n.replace(rep, PLACEHOLDER).split(":")
                    return {
                        active: net[0] === "yes", strength: parseInt(net[1]),
                        frequency: parseInt(net[2]), ssid: (net[3] ?? "").replace(rep2, ":"),
                        bssid: net[4]?.replace(rep2, ":") ?? "", security: net[5] || ""
                    }
                }).filter(n => n.ssid && n.ssid.length > 0)

                const networkMap = new Map()
                for (const network of allNetworks) {
                    const existing = networkMap.get(network.ssid)
                    if (!existing) networkMap.set(network.ssid, network)
                    else if (network.active && !existing.active) networkMap.set(network.ssid, network)
                    else if (!network.active && !existing.active && network.strength > existing.strength) networkMap.set(network.ssid, network)
                }

                const wifiNetworks = Array.from(networkMap.values())
                const old = Array.from(root.wifiNetworks)
                // One entry per SSID (the map's key): matching on the BSSID too made a
                // new object (and destroyed the one being connected to) when the
                // strongest or active access point changed.
                const same = (a, b) => a.ssid === b.ssid
                const next = []
                for (const network of wifiNetworks) {
                    const match = old.find(n => same(n, network))
                    if (match) { match.lastIpcObject = network; next.push(match) }
                    else next.push(apComp.createObject(root, { lastIpcObject: network }))
                }
                const gone = old.filter(n => !next.includes(n))
                root.wifiNetworks = next
                // Destroyed once nothing lists them any more.
                Qt.callLater(() => gone.forEach(n => n.destroy()))
            }
        }
    }

    Component { id: apComp; WifiAccessPoint {} }
}
