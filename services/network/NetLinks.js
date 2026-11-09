.pragma library

// The non-Wi-Fi links (services/Network.qml): ethernet, USB tethering,
// Bluetooth tethering, mobile broadband, and which one carries the default
// route. Pure; tested in scripts/dev/test-net-links.js.

// Interfaces that are never a way out: containers, VMs, bridges, and VPN
// tunnels (VPNs have their own row, services/VPN.qml).
const VIRTUAL = /^(lo$|vboxnet|vmnet|docker|veth|virbr|vnet|br-|tap|tun|wg|wt\d|nb-|tailscale|zt|lxc|lxd|podman|cni|flannel|cali|dummy)/

// A phone sharing its connection over USB shows up as one of these.
const TETHER_DRIVERS = ["rndis_host", "cdc_ether", "cdc_ncm", "ipheth"]

const ICONS = { ethernet: "lan", usb: "usb", bluetooth: "bluetooth", mobile: "signal_cellular_alt" }

function isVirtual(name) { return VIRTUAL.test(name || "") }

// `nmcli -t -f GENERAL.DEVICE,GENERAL.TYPE,GENERAL.STATE,GENERAL.CONNECTION,
// GENERAL.IP-IFACE,GENERAL.DRIVER,GENERAL.PRODUCT,IP4.ADDRESS device show`
// → [{ device, type, state, connection, iface, driver, product, ip }]
function devices(text) {
    const out = []
    let cur = null
    for (const line of String(text || "").split("\n")) {
        const i = line.indexOf(":")
        if (i < 0) continue
        const key = line.slice(0, i), val = line.slice(i + 1).replace(/\\:/g, ":").replace(/\\\\/g, "\\").trim()
        if (key === "GENERAL.DEVICE") { cur = { device: val, type: "", state: "", connection: "", iface: "", driver: "", product: "", ip: "" }; out.push(cur) }
        if (!cur) continue
        if (key === "GENERAL.TYPE") cur.type = val
        else if (key === "GENERAL.STATE") cur.state = val.replace(/^\d+\s*\(|\)$/g, "")
        else if (key === "GENERAL.CONNECTION") cur.connection = val
        else if (key === "GENERAL.IP-IFACE") cur.iface = val
        else if (key === "GENERAL.DRIVER") cur.driver = val
        else if (key === "GENERAL.PRODUCT") cur.product = val
        else if (key.startsWith("IP4.ADDRESS") && !cur.ip) cur.ip = val.split("/")[0]
    }
    return out
}

// `ip -j route show default` → the interface of the lowest-metric route, or "".
function primaryIface(json) {
    let routes = []
    try { routes = JSON.parse(json || "[]") } catch (e) { return "" }
    if (!Array.isArray(routes) || routes.length === 0) return ""
    routes.sort((a, b) => (a.metric || 0) - (b.metric || 0))
    return routes[0].dev || ""
}

function kindOf(d) {
    if (d.type === "bt") return "bluetooth"
    if (d.type === "gsm" || d.type === "cdma") return "mobile"
    if (d.type === "ethernet") return TETHER_DRIVERS.includes(d.driver) ? "usb" : "ethernet"
    return ""
}

function titleOf(d, kind) {
    const c = d.connection
    if (kind === "usb") return d.product || "USB tethering"
    if (kind === "bluetooth") return c ? c.replace(/ Network$/, "") : "Bluetooth tethering"
    if (kind === "mobile") return c || "Mobile broadband"
    return c && !/^Wired connection \d+$/.test(c) ? c : "Ethernet"
}

// → { links: [{ device, iface, kind, icon, title, state, connected, ip, primary }], primary }
// Only links you could use: no virtual interfaces, nothing unmanaged or
// unplugged. Connected first, the one carrying traffic on top.
function parse(deviceText, routeJson) {
    const primary = primaryIface(routeJson)
    const links = []
    for (const d of devices(deviceText)) {
        const kind = kindOf(d)
        if (!kind || isVirtual(d.device) || d.state.startsWith("unmanaged") || d.state.startsWith("unavailable")) continue
        const iface = d.iface || d.device
        const connected = d.state.startsWith("connected")
        links.push({
            device: d.device, iface: iface, kind: kind, icon: ICONS[kind], title: titleOf(d, kind),
            state: d.state, connected: connected, ip: connected ? d.ip : "",
            primary: connected && primary !== "" && iface === primary
        })
    }
    links.sort((a, b) => (b.primary - a.primary) || (b.connected - a.connected) || a.title.localeCompare(b.title))
    return { links: links, primary: primary }
}
