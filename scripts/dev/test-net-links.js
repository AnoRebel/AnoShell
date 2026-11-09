// Check for services/network/NetLinks.js (the wired & tethering links the
// network panels list). Run: node scripts/dev/test-net-links.js
const fs = require('fs'), path = require('path')
const src = fs.readFileSync(path.join(__dirname, '../../services/network/NetLinks.js'), 'utf8').replace('.pragma library', '')
const N = new Function(src + ';return {parse, isVirtual, primaryIface, vpns, monitorScope};')()
const a = (c, m) => { if (!c) throw new Error(m) }

const dev = (d, type, state, conn, iface, driver, product, ip) =>
    `GENERAL.DEVICE:${d}\nGENERAL.TYPE:${type}\nGENERAL.STATE:${state}\nGENERAL.CONNECTION:${conn}\n` +
    `GENERAL.IP-IFACE:${iface}\nGENERAL.DRIVER:${driver}\nGENERAL.PRODUCT:${product}\n` +
    (ip ? `IP4.ADDRESS[1]:${ip}/24\n` : '') + '\n'

const text = [
    dev('wlp0s20f3', 'wifi', '100 (connected)', 'Home', 'wlp0s20f3', 'iwlwifi', '', '192.168.1.5'),
    dev('enp3s0', 'ethernet', '100 (connected)', 'Wired connection 1', 'enp3s0', 'r8169', '', '10.0.0.2'),
    dev('enp0s20u1', 'ethernet', '100 (connected)', 'Wired connection 2', 'enp0s20u1', 'rndis_host', 'Pixel 7', '192.168.42.10'),
    dev('AA\\:BB\\:CC\\:DD\\:EE\\:FF', 'bt', '30 (disconnected)', '', '', 'btusb', '', ''),
    dev('cdc-wdm0', 'gsm', '100 (connected)', 'Carrier', 'wwan0', 'qmi_wwan', '', '100.64.1.2'),
    dev('enp4s0', 'ethernet', '20 (unavailable)', '', 'enp4s0', 'e1000e', '', ''),
    dev('vboxnet0', 'ethernet', '100 (connected (externally))', 'vboxnet0', 'vboxnet0', 'vboxnet', '', '192.168.56.1'),
    dev('veth15d98b7', 'ethernet', '10 (unmanaged)', '', '', 'veth', '', ''),
    dev('docker0', 'bridge', '100 (connected (externally))', 'docker0', 'docker0', 'bridge', '', '172.17.0.1'),
    dev('wt0', 'wireguard', '10 (unmanaged)', '', '', '', '', ''),
].join('')
const routes = JSON.stringify([
    { dst: 'default', dev: 'wlp0s20f3', metric: 600 },
    { dst: 'default', dev: 'wwan0', metric: 700 },
    { dst: 'default', dev: 'enp0s20u1', metric: 100 },
])

const r = N.parse(text, routes)
const by = d => r.links.find(l => l.device === d)
a(r.primary === 'enp0s20u1', 'lowest metric wins')
a(r.links.map(l => l.device).join(',') === 'enp0s20u1,cdc-wdm0,enp3s0,AA:BB:CC:DD:EE:FF',
    'primary first, then connected by title; virtual/unmanaged/unplugged/wifi left out: ' + r.links.map(l => l.device))
a(by('enp0s20u1').kind === 'usb' && by('enp0s20u1').title === 'Pixel 7' && by('enp0s20u1').primary, 'USB tether by driver, named after the phone')
a(by('enp3s0').kind === 'ethernet' && by('enp3s0').title === 'Ethernet' && by('enp3s0').ip === '10.0.0.2' && !by('enp3s0').primary, 'plain ethernet')
const bt = by('AA:BB:CC:DD:EE:FF')
a(bt.kind === 'bluetooth' && !bt.connected && bt.ip === '' && bt.title === 'Bluetooth tethering', 'bluetooth, escaped MAC unescaped')
a(by('cdc-wdm0').kind === 'mobile' && by('cdc-wdm0').iface === 'wwan0' && by('cdc-wdm0').icon === 'signal_cellular_alt', 'mobile broadband, matched by ip iface')

// The modem's iface carries the route: matched through IP-IFACE, not the device name.
a(N.parse(text, JSON.stringify([{ dev: 'wwan0' }])).links[0].device === 'cdc-wdm0', 'route via IP-IFACE')
a(N.parse(text, '').primary === '' && N.parse(text, 'not json').primary === '', 'no or bad route output')
a(N.parse('', '[]').links.length === 0, 'nothing to list')
a(N.parse(dev('enp1s0', 'ethernet', '100 (connected)', 'Office LAN', 'enp1s0', 'igc', '', ''), '[]').links[0].title === 'Office LAN', 'own profile name kept')

for (const v of ['vboxnet0', 'docker0', 'veth1', 'virbr0', 'br-abc', 'tun0', 'wg0', 'wt0', 'lo', 'tailscale0'])
    a(N.isVirtual(v), 'virtual: ' + v)
for (const v of ['enp3s0', 'eth0', 'enp0s20u1', 'wlan0', 'lom1'])
    a(!N.isVirtual(v), 'real: ' + v)
// VPN profiles (`nmcli -t -f NAME,UUID,TYPE,STATE connection show`)
const vp = N.vpns([
    'Rebels:6631c943:802-11-wireless:activated',
    'NetBird:896f00ed:vpn:',
    'Office\\: VPN:1111:vpn:activating',
    'wg-home:2222:wireguard:activated',
    'docker0:3333:bridge:activated',
    'short:line',
].join('\n'))
a(vp.map(v => v.name).join('|') === 'Office: VPN|wg-home|NetBird', 'vpn + wireguard only, up first, escapes undone: ' + vp.map(v => v.name))
a(vp[1].active && vp[1].type === 'wireguard' && !vp[0].active && vp[0].state === 'activating' && vp[2].uuid === '896f00ed', 'state and uuid')
a(N.vpns('').length === 0, 'no profiles')

// `nmcli monitor` lines → which nmcli lists need a refresh
const sc = (line) => { const s = N.monitorScope(line, ['wlp0s20f3']); return (s.links ? 'L' : '') + (s.vpn ? 'V' : '') }
for (const [line, want] of [
    ['wlp0s20f3: connecting (configuring)', ''],
    ['wlp0s20f3: using connection \'Rebels\'', ''],
    ['p2p-dev-wlp0s20f3: disconnected', ''],
    ['Connectivity is now \'full\'', ''],
    ['NetworkManager is now in the \'connected\' state', ''],
    ['veth15d98b7: unmanaged', ''],
    ['br-09d1652257f3: connected (externally)', ''],
    ['vethb24106a: device removed', ''],
    ['enp3s0: connected', 'L'],
    ['AA:BB:CC:DD:EE:FF: disconnected', 'L'],
    ['\'Rebels\' is now the primary connection', 'L'],
    ['There\'s no primary connection', 'L'],
    ['wg0: connected', 'V'],
    ['tun0: device created', 'V'],
    ['Office WiFi: connection profile changed', 'V'],
    ['my:vpn: connection profile removed', 'V'],
    ['NetworkManager is running', 'LV'],
    ['', ''],
]) a(sc(line) === want, `monitorScope(${JSON.stringify(line)}) = ${sc(line)}, want ${want}`)
console.log('net links ok')
