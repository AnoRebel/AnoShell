import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Network Orbit: the content of the NetworkOrbit panel. Connected devices are
 * glowing cores in the middle; nearby networks / devices (or, once connected,
 * the connection's details) orbit around them as cards, joined by beams.
 * Hold a core to disconnect. Tabs: Ethernet, Wi-Fi, Bluetooth, VPN.
 *
 * Adapted from ilyamiro's NetworkPopup (Serpantinum) for AnoShell. The data
 * comes from AnoShell's services (Network, BluetoothStatus / Quickshell
 * Bluetooth, VPN); no external text is ever put into a shell string.
 *
 * Child layers (OrbitCores, OrbitCards, OrbitControls) read their state from
 * this item through their `view` property. Springs on unitless values
 * (angles, 0..1 progress, scales) pass a fine epsilon: the tokens' 0.25 is
 * tuned for pixels and would snap the last stretch.
 */
Item {
    id: root

    // Bound by the host: true while the panel should be on screen. Turning it
    // off plays the exit and then emits exited().
    property bool shown: false
    signal exited()

    // ── Motion helpers (ilyamiro's intro choreography: one linear clock,
    // each element eases in over its own window of it) ─────────────────────
    function animWin(t, a, b) { return t <= a ? 0 : (t >= b ? 1 : (t - a) / (b - a)) }
    function easeOut(t) { const c = Math.max(0, Math.min(1, t)); return 1 - Math.pow(1 - c, 3) }
    function easeBack(t) { const c = Math.max(0, Math.min(1, t)); return 1 + 2.7 * Math.pow(c - 1, 3) + 1.7 * Math.pow(c - 1, 2) }

    property real introState: 0
    Behavior on introState {
        enabled: root.shown
        NumberAnimation { duration: AnimationConfig.scaledDuration(900); easing.type: Easing.Linear }
    }
    property real exitOpacity: 1
    readonly property bool live: root.shown || exitAnim.running
    // The host card's fade + slight scale (intro and exit).
    readonly property real cardOpacity: root.exitOpacity * root.easeOut(root.animWin(root.introState, 0, 0.12))
    readonly property real cardScale: (0.96 + 0.04 * root.easeOut(root.animWin(root.introState, 0, 0.12))) * (0.97 + 0.03 * root.exitOpacity)

    SequentialAnimation {
        id: exitAnim
        NumberAnimation {
            target: root; property: "exitOpacity"; to: 0
            duration: AnimationConfig.scaledDuration(110)
            easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedAccel
        }
        ScriptAction { script: { root.introState = 0; root.exited() } }
    }
    // ~2 frames: the intro starts after the panel's first frame, not inside it.
    Timer { id: introTimer; interval: 40; onTriggered: root.introState = 1 }
    // nmcli starts once the card has faded in, so its processes and results
    // don't land on the intro's first frames.
    Timer {
        id: scanTimer
        interval: 40 + AnimationConfig.scaledDuration(120)
        onTriggered: { root._scanForMode(); devicesProc.running = true }
    }

    function _start() {
        exitAnim.stop()
        root.exitOpacity = 1
        root.introState = 0
        root.powerAnimAllowed = false
        powerAnimBlocker.restart()
        introTimer.restart()
        root.showInfoView = root.currentConn
        scanTimer.restart()
    }
    onShownChanged: {
        if (root.shown) { root._start(); return }
        introTimer.stop()
        scanTimer.stop()
        root._stopScans()
        root.pendingWifiSsid = ""
        root.hoveredCardCount = 0
        root.disconnectHoverCount = 0
        exitAnim.restart()
    }
    Component.onCompleted: if (root.shown) root._start()
    Component.onDestruction: root._stopScans()

    // Power morph animations stay off right after opening / switching tab,
    // so the power button doesn't fly across on a state it merely loaded.
    property bool powerAnimAllowed: false
    Timer { id: powerAnimBlocker; interval: 250; onTriggered: root.powerAnimAllowed = true }

    // ── Devices (nmcli, read-only; device names are only ever argv) ────────
    property var ethDev: null    // { name, state, mac, ip, speed }
    property var wifiDev: null
    property bool devicesKnown: false

    Process {
        id: devicesProc
        command: ["nmcli", "-t", "-f", "GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.HWADDR,IP4.ADDRESS,CAPABILITIES.SPEED", "device", "show"]
        environment: ({ LANG: "C", LC_ALL: "C" })
        stdout: StdioCollector {
            onStreamFinished: {
                let eth = null, wifi = null, cur = null
                const flush = () => {
                    if (!cur) return
                    // A real port, a connected one first (vboxnet, veth etc. are type ethernet too).
                    if (cur.type === "ethernet" && !Network.isVirtualIface(cur.name)
                        && (!eth || (!eth.state.startsWith("connected") && cur.state.startsWith("connected")))) eth = cur
                    else if (cur.type === "wifi" && !wifi) wifi = cur
                    cur = null
                }
                for (const line of this.text.split("\n")) {
                    const i = line.indexOf(":")
                    if (i < 0) { flush(); continue }
                    const key = line.slice(0, i), val = line.slice(i + 1).replace(/\\:/g, ":").trim()
                    if (key === "GENERAL.DEVICE") { flush(); cur = { name: val, type: "", state: "", mac: "", ip: "", speed: "" } }
                    if (!cur) continue
                    if (key === "GENERAL.TYPE") cur.type = val
                    else if (key === "GENERAL.STATE") cur.state = val.replace(/^\d+\s*\(|\)$/g, "")
                    else if (key === "GENERAL.HWADDR") cur.mac = val
                    else if (key.startsWith("IP4.ADDRESS") && !cur.ip) cur.ip = val.split("/")[0]
                    else if (key === "CAPABILITIES.SPEED") cur.speed = val === "unknown" ? "" : val
                }
                flush()
                if (JSON.stringify(eth) !== JSON.stringify(root.ethDev)) root.ethDev = eth
                if (JSON.stringify(wifi) !== JSON.stringify(root.wifiDev)) root.wifiDev = wifi
                root.devicesKnown = true
            }
        }
    }
    // Refresh device details on network events while the panel is up.
    Connections {
        target: Network
        enabled: root.live
        function onEthernetChanged() { devicesProc.running = true }
        function onNetworkNameChanged() { devicesProc.running = true }
        function onWifiStatusChanged() { devicesProc.running = true }
    }
    Timer {
        interval: 5000; repeat: true
        running: root.shown && (root.isEthConn || root.isWifiConn)
        onTriggered: devicesProc.running = true
    }

    // ── Tabs ──────────────────────────────────────────────────────────────
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool ethPresent: !!root.ethDev && root.ethDev.state !== "unavailable" && root.ethDev.state !== "unmanaged"
    readonly property bool wifiPresent: !root.devicesKnown || !!root.wifiDev || Network.wifiNetworks.length > 0
    readonly property bool btPresent: BluetoothStatus.available
    readonly property bool vpnPresent: VPN.enabled
    readonly property var modes: {
        const m = []
        if (root.ethPresent) m.push("eth")
        if (root.wifiPresent) m.push("wifi")
        if (root.btPresent) m.push("bt")
        if (root.vpnPresent) m.push("vpn")
        return m
    }
    // The requested tab (GlobalStates.networkOrbitTab), or the first available.
    readonly property string activeMode: root.modes.includes(GlobalStates.networkOrbitTab) ? GlobalStates.networkOrbitTab : (root.modes[0] ?? "wifi")
    function gotoMode(m) {
        if (m === root.activeMode || !root.modes.includes(m)) return
        root.powerAnimAllowed = false
        powerAnimBlocker.restart()
        GlobalStates.networkOrbitTab = m
    }
    function cycleMode() {
        if (root.pendingWifiSsid !== "") { root.pendingWifiSsid = ""; return }
        if (root.modes.length > 1) root.gotoMode(root.modes[(root.modes.indexOf(root.activeMode) + 1) % root.modes.length])
    }
    onActiveModeChanged: {
        root.hoveredCardCount = 0
        root.disconnectHoverCount = 0
        root.pendingWifiSsid = ""
        root._pendingNodes = null
        orbitListModel.clear()
        root.currentCores = [null, null, null, null, null]
        root.syncCores()
        root.showInfoView = root.currentConn
        if (root.shown) root._scanForMode()
        root._applyNodes()
    }

    // Accent per tab: Bluetooth tertiary, VPN secondary, the rest primary.
    readonly property color activeColor: root.activeMode === "bt" ? Appearance.colors.colTertiary
        : root.activeMode === "vpn" ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
    readonly property color onActiveColor: root.activeMode === "bt" ? Appearance.colors.colOnTertiary
        : root.activeMode === "vpn" ? Appearance.colors.colOnSecondary : Appearance.colors.colOnPrimary
    readonly property color activeGradientSecondary: Qt.darker(root.activeColor, 1.25)

    // ── Scanning ──────────────────────────────────────────────────────────
    function _scanForMode() {
        if (root.activeMode === "bt") { if (root.adapter?.enabled) root.adapter.discovering = true }
        else if (root.adapter?.discovering) root.adapter.discovering = false
        if (root.activeMode === "wifi" && Network.wifiEnabled) Network.rescanWifi()
    }
    function _stopScans() { if (root.adapter?.discovering) root.adapter.discovering = false }
    Timer {
        interval: 20000; repeat: true
        running: root.shown && root.activeMode === "wifi" && Network.wifiEnabled && !root.showInfoView
        onTriggered: Network.rescanWifi()
    }

    // ── Power (per tab) ───────────────────────────────────────────────────
    function powerOf(m) {
        if (m === "wifi") return Network.wifiEnabled
        if (m === "bt") return root.adapter?.enabled ?? false
        if (m === "eth") return root.isEthConn
        if (m === "vpn") return VPN.connected
        return false
    }
    readonly property bool currentPower: root.powerOf(root.activeMode)
    // Expected power per tab while a toggle is in flight (cleared when the
    // service reports it, or after 8 s).
    property var _expect: ({})
    readonly property bool currentPowerPending: (root.activeMode === "vpn" && VPN.connecting)
        || (root._expect[root.activeMode] !== undefined && root._expect[root.activeMode] !== root.currentPower)
    Timer { id: expectReset; interval: 8000; onTriggered: root._expect = ({}) }

    function togglePower() {
        root.pendingWifiSsid = ""
        const m = root.activeMode
        if (root.currentPowerPending) return
        const on = !root.currentPower
        if (m === "vpn") {
            if (VPN.status.state === "needs-auth" && VPN.status.authUrl) root.openUrl(VPN.status.authUrl)
            else VPN.toggle()
            return
        }
        const e = Object.assign({}, root._expect); e[m] = on; root._expect = e
        expectReset.restart()
        if (m === "wifi") Network.enableWifi(on)
        else if (m === "bt") { if (root.adapter) root.adapter.enabled = on }
        else if (m === "eth" && root.ethDev) {
            Quickshell.execDetached(["nmcli", "device", on ? "connect" : "disconnect", root.ethDev.name])
            ethRefresh.restart()
        }
    }
    Timer { id: ethRefresh; interval: 1500; onTriggered: devicesProc.running = true }

    // ── Connections (what the cores show) ─────────────────────────────────
    readonly property bool isEthConn: !!root.ethDev && root.ethDev.state.startsWith("connected")
    readonly property bool isWifiConn: !!Network.active
    readonly property bool isBtConn: BluetoothStatus.connectedDevices.length > 0

    function btIcon(dev) {
        const s = ((dev?.icon ?? "") + " " + (dev?.name ?? "")).toLowerCase()
        if (/head|buds|pods|earphone/.test(s)) return "headphones"
        if (/audio|speaker|card/.test(s)) return "speaker"
        if (/phone|android/.test(s)) return "smartphone"
        if (/mouse/.test(s)) return "mouse"
        if (/keyboard/.test(s)) return "keyboard"
        if (/game|controller|joystick/.test(s)) return "sports_esports"
        if (/watch/.test(s)) return "watch"
        return "bluetooth"
    }
    function wifiIcon(s) {
        return s > 83 ? "signal_wifi_4_bar" : s > 67 ? "network_wifi" : s > 50 ? "network_wifi_3_bar"
            : s > 33 ? "network_wifi_2_bar" : s > 17 ? "network_wifi_1_bar" : "signal_wifi_0_bar"
    }
    function modeIcon(m) { return m === "wifi" ? "wifi" : m === "eth" ? "lan" : m === "vpn" ? "vpn_lock" : "bluetooth" }
    function modeOffIcon(m) { return m === "wifi" ? "wifi_off" : m === "eth" ? "link_off" : m === "vpn" ? "vpn_key_off" : "bluetooth_disabled" }

    // [{ id, name, icon }] for the active tab.
    readonly property var connectedList: {
        const m = root.activeMode
        if (m === "wifi") return Network.active ? [{ id: Network.active.ssid, name: Network.active.ssid, icon: root.wifiIcon(Network.active.strength) }] : []
        if (m === "eth") return root.isEthConn ? [{ id: root.ethDev.name, name: "Ethernet", icon: "lan" }] : []
        if (m === "vpn") return VPN.connected ? [{ id: "vpn", name: VPN.currentConfig?.displayName || VPN.providerName, icon: "vpn_lock" }] : []
        return BluetoothStatus.connectedDevices.map(d => ({ id: d.address, name: d.name || d.address, icon: root.btIcon(d) }))
    }
    readonly property bool currentConn: root.connectedList.length > 0
    onCurrentConnChanged: if (root.currentConn) root.showInfoView = true
    property string _connKey: ""
    onConnectedListChanged: {
        const k = JSON.stringify(root.connectedList)
        if (k === root._connKey) return
        root._connKey = k
        root.syncCores()
        // A hold-to-disconnect is done once its connection is gone.
        const keep = {}
        for (const d of root.connectedList) if (root.disconnectingIds[d.id]) keep[d.id] = true
        if (Object.keys(keep).length !== Object.keys(root.disconnectingIds).length) root.disconnectingIds = keep
    }

    // Up to 5 cores; a device keeps its slot while it stays connected.
    property var currentCores: [null, null, null, null, null]
    property var coreVisualIndices: [0, 0, 0, 0, 0]
    property int activeCoreCount: 0
    property real smoothedActiveCoreCount: activeCoreCount
    Behavior on smoothedActiveCoreCount { enabled: root.shown; MotionSpring { token: "liquid"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }

    function syncCores() {
        // also runs from onActiveModeChanged during construction, before
        // the connectedList binding has a value
        const list = root.currentPower ? (root.connectedList ?? []).slice(0, 5) : []
        const cores = root.currentCores.map(c => c && list.find(d => d.id === c.id) ? list.find(d => d.id === c.id) : null)
        for (const d of list) {
            if (cores.some(c => c && c.id === d.id)) continue
            const free = cores.indexOf(null)
            if (free >= 0) cores[free] = d
        }
        let n = 0
        root.coreVisualIndices = cores.map(c => c ? n++ : 0)
        root.currentCores = cores
        root.activeCoreCount = n
    }
    onCurrentPowerChanged: {
        root.syncCores()
        if (root.shown && root.currentPower) root._scanForMode()   // radio just came on
    }

    readonly property bool isLogicMultiState: root.activeMode === "bt" && root.activeCoreCount > 1
    property real multiTransitionState: (root.isLogicMultiState && root.currentPower) ? 1 : 0
    Behavior on multiTransitionState { enabled: root.shown; MotionSpring { token: "liquid"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }

    // ── Busy / failure state ──────────────────────────────────────────────
    property string failedId: ""
    property string failReason: ""  // shown on the failed card in place of its name
    Timer { id: failClear; interval: 8000; onTriggered: root.failedId = "" }
    function fail(id, reason) { root.failedId = id; root.failReason = reason ?? "Failed"; failClear.restart() }

    function findAp(ssid) { return Network.wifiNetworks.find(n => n.ssid === ssid) ?? null }
    function findBt(addr) { return (root.adapter?.devices.values ?? []).find(d => d.address === addr) ?? null }

    function isBusy(id) {
        if (root.activeMode === "wifi") return Network.wifiConnecting && Network.wifiConnectTarget?.ssid === id
        if (root.activeMode === "bt") {
            const d = root.findBt(id)
            return !!d && (d.pairing || d.state === BluetoothDeviceState.Connecting)
        }
        return false
    }
    function isDisconnecting(id) {
        if (root.activeMode === "bt") { const d = root.findBt(id); return !!d && d.state === BluetoothDeviceState.Disconnecting }
        if (root.activeMode === "vpn") return VPN.connecting && VPN.connected
        return false
    }
    // Set by a hold-to-disconnect until the connection drops (or 10 s).
    property var disconnectingIds: ({})
    Timer { id: disconnectReset; interval: 10000; onTriggered: root.disconnectingIds = ({}) }

    property int disconnectHoverCount: 0
    readonly property bool isDisconnectHovered: root.disconnectHoverCount > 0

    // Wi-Fi: a failed connect to a secured network asks for its password in
    // the core; to an open one it flashes the card.
    property string pendingWifiSsid: ""
    property var _connectTarget: null
    Connections {
        target: root._connectTarget
        function onAskingPasswordChanged() {
            const ap = root._connectTarget
            if (!ap || !ap.askingPassword) return
            if (ap.isSecure) root.pendingWifiSsid = ap.ssid
            else root.fail(ap.ssid, "Couldn't connect")
            root._connectTarget = null
        }
        function onActiveChanged() { if (root._connectTarget?.active) root._connectTarget = null }
    }
    function submitPassword(password) {
        const ap = root.findAp(root.pendingWifiSsid)
        root.pendingWifiSsid = ""
        if (!ap || password === "") return
        root._connectTarget = ap
        Network.connectToWifiNetworkWithPassword(ap, password)
    }

    // Bluetooth: pair first, then connect once pairing lands.
    property var _pairTarget: null
    Connections {
        target: root._pairTarget
        function onPairedChanged() {
            const d = root._pairTarget
            if (!d || !d.paired) return
            root._pairTarget = null
            // BlueZ keeps the pairing link up for a moment; connect() on it is a
            // no-op, so wait (up to 15 s) for that link to drop first.
            if (d.connected) { root._linkDropTarget = d; linkDropTimer.restart() }
            else d.connect()
        }
        function onPairingChanged() {
            const d = root._pairTarget
            if (d && !d.pairing && !d.paired) { root._pairTarget = null; root.fail(d.address, "Pairing failed") }
        }
    }

    property var _linkDropTarget: null
    function _connectAfterPair() {
        const d = root._linkDropTarget
        root._linkDropTarget = null
        linkDropTimer.stop()
        if (d) d.connect()
    }
    Timer { id: linkDropTimer; interval: 15000; onTriggered: root._connectAfterPair() }
    Connections {
        target: root._linkDropTarget
        function onConnectedChanged() { if (!root._linkDropTarget?.connected) root._connectAfterPair() }
    }

    function connectNode(id) {
        root.failedId = ""
        if (root.activeMode === "wifi") {
            const ap = root.findAp(id)
            if (!ap || Network.wifiConnecting) return
            root._connectTarget = ap
            Network.connectToWifiNetwork(ap)
        } else if (root.activeMode === "bt") {
            const d = root.findBt(id)
            if (!d) { root.fail(id, "Device gone"); return }
            if (root.adapter?.discovering) root.adapter.discovering = false
            if (!d.paired && !d.bonded) { d.trusted = true; root._pairTarget = d; d.pair() }
            else d.connect()
        }
    }

    function disconnectCore(id) {
        const dd = Object.assign({}, root.disconnectingIds); dd[id] = true; root.disconnectingIds = dd
        disconnectReset.restart()
        if (root.activeMode === "wifi") Network.disconnectWifiNetwork()
        else if (root.activeMode === "bt") root.findBt(id)?.disconnect()
        else if (root.activeMode === "vpn") VPN.disconnect()
        else if (root.activeMode === "eth" && root.ethDev) {
            Quickshell.execDetached(["nmcli", "device", "disconnect", root.ethDev.name])
            ethRefresh.restart()
        }
    }

    function openUrl(url) { if (/^https?:\/\//.test(url)) DefaultApps.launch(["xdg-open", url]) }

    // Card actions. Each `cmd` maps to a service call; `arg` (an SSID, a MAC,
    // an IP or a URL) is only ever an argv element or an object lookup key.
    // List cards' ids are "n:" + arg, so an SSID can't collide with an action
    // card's id.
    function trigger(node) {
        switch (node.cmd) {
        case "toggleView": root.hoveredCardCount = 0; root.showInfoView = !root.showInfoView; break
        case "copy": if (node.arg) Quickshell.execDetached(["wl-copy", "--", node.arg]); break
        case "portal": Network.openPublicWifiPortal(); break
        case "forgetWifi": if (Network.active) Network.forgetWifiNetwork(Network.active); break
        case "forgetBt": root.findBt(node.arg)?.forget(); break
        case "auth": root.openUrl(node.arg); break
        case "connect": root.connectNode(node.arg); break
        }
    }

    // ── Cards (orbit model) ───────────────────────────────────────────────
    property bool showInfoView: false
    onShowInfoViewChanged: root.hoveredCardCount = 0

    function _info(id, name, icon, parentIndex, cmd, arg) {
        return { id: id, name: name, icon: icon, action: "", isInfoNode: true, isActionable: !!cmd, cmd: cmd || "", arg: arg || "", parentIndex: parentIndex, highlight: !!cmd }
    }
    function _coreIndexOf(id) { const i = root.currentCores.findIndex(c => c && c.id === id); return i < 0 ? 0 : i }

    // The cards for the active tab: details of the connection(s) while the
    // info view is up, otherwise what you can connect to.
    readonly property var nodes: {
        const m = root.activeMode
        const out = []
        if (!root.currentPower) return out
        if (root.currentConn && root.showInfoView) {
            if (m === "wifi") {
                const ap = Network.active
                out.push(root._info("sig", `${ap.strength}%`, root.wifiIcon(ap.strength), 0))
                out.push(root._info("sec", ap.security || "Open", ap.isSecure ? "lock" : "lock_open", 0))
                if (root.wifiDev?.ip) out.push(root._info("ip", root.wifiDev.ip, "content_copy", 0, "copy", root.wifiDev.ip))
                if (ap.frequency > 0) out.push(root._info("freq", `${(ap.frequency / 1000).toFixed(1)} GHz`, "settings_input_antenna", 0))
                if (Network.wifiStatus === "limited") out.push(root._info("portal", "Sign in", "login", 0, "portal"))
                out.push(root._info("forget", "Forget", "delete", 0, "forgetWifi"))
                out.push(root._info("scan", "Scan", "travel_explore", -1, "toggleView"))
            } else if (m === "eth") {
                out.push(root._info("ip", root.ethDev.ip || "No IP", "content_copy", 0, root.ethDev.ip ? "copy" : "", root.ethDev.ip))
                out.push(root._info("spd", root.ethDev.speed || "Unknown", "speed", 0))
                out.push(root._info("mac", root.ethDev.mac || "Unknown", "fingerprint", 0))
            } else if (m === "vpn") {
                out.push(root._info("prov", VPN.currentConfig?.displayName || VPN.providerName, "shield", 0))
                if (VPN.currentConfig?.interface) out.push(root._info("iface", VPN.currentConfig.interface, "settings_ethernet", 0))
                out.push(root._info("state", VPN.status.state, "info", 0))
            } else {
                for (const d of BluetoothStatus.connectedDevices) {
                    const p = root._coreIndexOf(d.address)
                    if (d.batteryAvailable) out.push(root._info("bat_" + d.address, `${Math.round(d.battery * 100)}%`, "battery_full", p))
                    out.push(root._info("mac_" + d.address, d.address, "fingerprint", p))
                    out.push(root._info("forget_" + d.address, "Unpair", "link_off", p, "forgetBt", d.address))
                }
                out.push(root._info("scan", "Scan", "travel_explore", -1, "toggleView"))
            }
            return out
        }
        if (m === "wifi") {
            const nets = Network.friendlyWifiNetworks.filter(n => !n.active).slice(0, 14)
            for (let i = 0; i < nets.length; i++)
                out.push({ id: "n:" + nets[i].ssid, name: nets[i].ssid, icon: root.wifiIcon(nets[i].strength), action: "Connect", isInfoNode: false, isActionable: true, cmd: "connect", arg: nets[i].ssid, parentIndex: -1, highlight: !root.isWifiConn && i === 0 })
        } else if (m === "bt") {
            const mac = /^([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}$/
            const devs = BluetoothStatus.pairedButNotConnectedDevices.concat(BluetoothStatus.unpairedDevices.filter(d => d.name && !mac.test(d.name)))
            for (const d of devs.slice(0, 14))
                out.push({ id: "n:" + d.address, name: d.name || d.address, icon: root.btIcon(d), action: d.paired ? "Connect" : "Pair", isInfoNode: false, isActionable: true, cmd: "connect", arg: d.address, parentIndex: -1, highlight: d.paired })
        }
        if (root.currentConn && m !== "eth" && m !== "vpn")
            out.push({ id: "current", name: "Current device", icon: "settings", action: "", isInfoNode: false, isActionable: true, cmd: "toggleView", arg: "", parentIndex: -1, highlight: true })
        return out
    }
    onNodesChanged: root._applyNodes()

    // Cards don't reshuffle under the pointer: while one is hovered, updates
    // wait and land when it leaves.
    property int hoveredCardCount: 0
    readonly property bool isListLocked: root.hoveredCardCount > 0
    property var _pendingNodes: null
    onIsListLockedChanged: if (!root.isListLocked && root._pendingNodes) root._applyNodes()
    function _applyNodes() {
        if (root.isListLocked) { root._pendingNodes = root.nodes; return }
        root._pendingNodes = null
        root.syncModel(orbitListModel, root.nodes)
    }

    // Diff `arr` into the ListModel so surviving cards keep their delegates
    // (and their positions animate) instead of being rebuilt.
    function syncModel(model, arr) {
        for (let i = model.count - 1; i >= 0; i--)
            if (!arr.some(d => d.id === model.get(i).id)) model.remove(i)
        for (let i = 0; i < arr.length && i < 30; i++) {
            const d = arr[i]
            let at = -1
            for (let j = 0; j < model.count; j++) if (model.get(j).id === d.id) { at = j; break }
            if (at === -1) { model.insert(i, d); continue }
            if (at !== i) model.move(at, i, 1)
            const cur = model.get(i)
            for (const k in d) if (cur[k] !== d[k]) model.setProperty(i, k, d[k])
        }
    }
    ListModel { id: orbitListModel }
    readonly property ListModel orbitModel: orbitListModel

    // ── Ambient motion ────────────────────────────────────────────────────
    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2; loops: Animation.Infinite
        duration: AnimationConfig.scaledDuration(400000); easing.type: Easing.Linear
        running: root.live && AnimationConfig.continuous
    }
    readonly property real lightningStrikeProg: root.animWin(root.introState, 0.40, 0.85)
    readonly property int bottomBand: 65

    // ── Visuals ───────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent

        // Two drifting colour blobs behind everything.
        Rectangle {
            width: parent.width * 0.8; height: width; radius: width / 2
            x: (parent.width - width) / 2 + Math.cos(root.globalOrbitAngle * 2) * 120
            y: (parent.height - height) / 2 + Math.sin(root.globalOrbitAngle * 2) * 80
            opacity: (root.currentPower ? (root.isDisconnectHovered ? 0.05 : 0.03) : 0.01) * root.easeOut(root.animWin(root.introState, 0.02, 0.22))
            color: root.isDisconnectHovered && root.currentConn ? Appearance.colors.colError
                : (root.currentConn ? root.activeColor : Appearance.m3colors.m3surfaceVariant)
            Behavior on color { enabled: root.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(300) } }
            visible: opacity > 0.005
        }
        Rectangle {
            width: parent.width * 0.9; height: width; radius: width / 2
            x: (parent.width - width) / 2 - Math.sin(root.globalOrbitAngle * 1.5) * 120
            y: (parent.height - height) / 2 - Math.cos(root.globalOrbitAngle * 1.5) * 80
            opacity: (root.currentPower ? (root.isDisconnectHovered ? 0.04 : 0.02) : 0.005) * root.easeOut(root.animWin(root.introState, 0.04, 0.26))
            color: root.isDisconnectHovered && root.currentConn ? Qt.darker(Appearance.colors.colError, 1.25)
                : (root.currentConn ? root.activeGradientSecondary : Appearance.m3colors.m3surfaceContainerHighest)
            Behavior on color { enabled: root.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(300) } }
            visible: opacity > 0.002
        }

        // Intro ping: one ring expanding out of the core.
        Rectangle {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -root.bottomBand / 2
            width: 520; height: width; radius: width / 2
            color: "transparent"
            border.color: root.activeColor; border.width: 2
            readonly property real pingProg: root.animWin(root.introState, 0.03, 0.32)
            opacity: (1 - pingProg) * (root.currentPower ? 0.45 : 0.18)
            scale: 0.2 + 0.9 * pingProg
            visible: pingProg > 0.001 && pingProg < 0.999 && opacity > 0.01
        }

        // Radar rings.
        Item {
            anchors.fill: parent
            anchors.bottomMargin: root.bottomBand
            opacity: root.currentPower ? 1 : 0
            scale: root.currentPower ? 1 : 1.05
            visible: opacity > 0.01
            Behavior on opacity { enabled: root.shown; MotionNumber { curve: "standard"; baseDuration: 600 } }
            Behavior on scale { enabled: root.shown; MotionSpring { token: "settle"; epsilon: AnimationConfig.transitions ? 0.002 : 1000 } }

            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property bool dropping: Object.keys(root.disconnectingIds).length > 0
                    readonly property real ringIntro: root.easeOut(root.animWin(root.introState, 0.06 + index * 0.05, 0.22 + index * 0.05))
                    anchors.centerIn: parent
                    width: 220 + index * 130; height: width; radius: width / 2
                    color: "transparent"
                    border.color: dropping ? Appearance.colors.colError : root.activeColor
                    border.width: dropping ? 2 : 1
                    scale: 0.75 + 0.25 * ringIntro
                    opacity: (dropping ? 0.2 : (root.currentConn ? 0.08 - index * 0.02 : 0.03)) * ringIntro
                    Behavior on border.color { enabled: root.shown; ColorAnimation { duration: AnimationConfig.scaledDuration(150) } }
                }
            }
        }

        // Beams from each core to the cards it owns.
        ShaderEffect {
            id: beams
            anchors.fill: parent
            anchors.bottomMargin: root.bottomBand
            readonly property bool wanted: root.currentConn && root.showInfoView && root.currentPower && root.lightningStrikeProg > 0.01
            opacity: wanted ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { enabled: root.shown; MotionNumber { curve: "expressiveEffects"; baseDuration: 400 } }

            property real time: 0
            NumberAnimation on time {
                running: root.live && beams.visible && AnimationConfig.continuous
                from: 0; to: 1000; loops: Animation.Infinite
                duration: AnimationConfig.scaledDuration(1000000); easing.type: Easing.Linear
            }
            property vector2d itemSize: Qt.vector2d(width, height)
            property real strikeProg: root.lightningStrikeProg
            property real pxScale: 1
            property color activeColor: root.activeColor

            readonly property var activeBeams: {
                void root.globalOrbitAngle
                const out = []
                if (!beams.wanted) return out
                const cores = coreLayer.repeater, cards = cardLayer.repeater
                const centre = it => Qt.vector2d(it.x + it.width / 2, it.y + it.height / 2)
                for (let i = 0; i < cards.count; i++) {
                    const card = cards.itemAt(i)
                    if (!card || !card.isLoaded) continue
                    const t = centre(card)
                    const owners = card.myParentIdx === -1 ? [...Array(cores.count).keys()] : [card.myParentIdx]
                    for (const c of owners) {
                        const core = cores.itemAt(c)
                        if (core && core.activeTransition > 0.01) {
                            const s = centre(core)
                            out.push(Qt.vector4d(s.x, s.y, t.x, t.y))
                        }
                    }
                }
                return out
            }
            readonly property vector4d noBeam: Qt.vector4d(-1, -1, -1, -1)
            property real beamCount: Math.min(8, activeBeams.length)
            property vector4d beam0: activeBeams[0] ?? noBeam
            property vector4d beam1: activeBeams[1] ?? noBeam
            property vector4d beam2: activeBeams[2] ?? noBeam
            property vector4d beam3: activeBeams[3] ?? noBeam
            property vector4d beam4: activeBeams[4] ?? noBeam
            property vector4d beam5: activeBeams[5] ?? noBeam
            property vector4d beam6: activeBeams[6] ?? noBeam
            property vector4d beam7: activeBeams[7] ?? noBeam
            fragmentShader: Qt.resolvedUrl(Quickshell.shellPath("shaders/qsb/node_beams.frag.qsb"))
        }

        OrbitCores { id: coreLayer; view: root }
        OrbitCards { id: cardLayer; view: root; orbitContainer: coreLayer; coreRepeater: coreLayer.repeater }
        OrbitControls { view: root }
    }
}
