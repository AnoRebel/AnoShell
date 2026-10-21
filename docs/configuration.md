# Configuration

## Two files

| File | What it is |
|---|---|
| `~/.config/quickshell/ano/config.json` | the bundled defaults that ship with the shell. Nothing the shell does writes here |
| `~/.config/anoshell/config.json` | your per-machine **delta**: only the keys you changed. Settings writes here |

On start the shell reads the bundled defaults and deep-merges your delta on top:

- Objects merge key by key, so setting `bar.layout.height` leaves the rest of
  `bar` alone.
- Arrays and plain values replace the default entirely.
- Removing a key from your file brings back the default.
- Because the file is sparse, it's portable to another machine, and new
  defaults in a shell update reach you for every key you haven't changed.

You can edit the file by hand; the shell watches it and applies saves without a
restart. A file that isn't valid JSON gets a notification with the line and
column of the error, and the last good config keeps applying.

```json
{
  "bar": { "form": "islands", "layout": { "height": 38, "radius": 16 } },
  "anoSpot": { "enable": true, "position": "bottom" },
  "appearance": { "connectedCorners": { "enable": true } }
}
```

Check a hand-edited file with `ano config validate`, and bring an old one up
to date with `ano config migrate` (see [The `ano` CLI](cli.md#config)).

## Settings

Open Settings with `ano ipc call settings toggle` (bound to `Super+,` in the
bundled Hyprland config), or as a standalone window with
`qs -n -p ~/.config/quickshell/ano/settings.qml`. Both use the same pages.

| Page | Config keys it owns |
|---|---|
| General | `audio`, `battery`, `time`, `notifications`, `interactions`, `sounds.battery`, `session` |
| Modules | `disabledPanels`, `panelFamily`, `familyTransitionAnimation`, `osd`, `screenCorners`, `altSwitcher`, `apps`, `focusTime`, `taskView`, `media`, `compositor`, `hacks`, `displayManager`, `display.primaryMonitor`, `sounds.theme`, `bar.morphingPanels` |
| Bar | `bar`, `bars`, `tray` |
| Dock | `dock` |
| Sidebars | `sidebar` |
| AnoSpot | `anoSpot` |
| Appearance | `appearance`, `background`, `animations` |
| Overview | `overview` |
| Services | `ai`, `gameMode`, `powerProfiles`, `network`, `vpn`, `nightLight`, `lyrics`, `calendar`, `resources`, `light`, `shell`, `weather` |
| About | `user` |

- `Ctrl+K` opens a command palette that searches every setting by its label
  or its config key; Enter jumps to the card that owns it.
- `Ctrl+1` … `Ctrl+9` jump to a page; `Esc` closes.
- Each page's **Reset** clears only the keys that page owns from your delta.
  **Reset every setting** on the About page clears the whole delta. Neither
  writes defaults into your file.

## Bars

Bars are defined in the `bars` array. Each bar sits on an edge (`top`,
`bottom`, `left` or `right`) and has its own modules; `bar.*` holds the
defaults every bar falls back to.

### Forms

`bar.form` (or `form` on one bar) shapes the whole bar:

| Form | Shape |
|---|---|
| `full` | edge to edge (the default) |
| `fit` | inset from the screen edges, floating |
| `islands` | every group is its own pill |
| `notch` | all groups packed in the middle; the bar hugs its content |

`fit` and `islands` sit `bar.layout.formMargin` (6 px) off the screen edge.
Switching forms animates.

### Groups

A bar's modules are arranged in **groups**. Each group has an id, a zone
(`start`, `center` or `end`), its modules, and whether it is attached to the
bar body:

```json
{
  "bars": [{
    "id": "main",
    "edge": "top",
    "form": "full",
    "groups": [
      { "id": "start",  "zone": "start",  "modules": ["sidebarButton", "activeWindow"], "attached": true },
      { "id": "center", "zone": "center", "modules": ["workspaces"], "attached": false },
      { "id": "end",    "zone": "end",    "modules": ["clock", "battery", "network", "tray"], "attached": true }
    ]
  }]
}
```

- A detached group (`"attached": false`) becomes its own island, with
  `bar.layout.groupGap` (10 px) opened on each side. In the `islands` form every
  group is detached.
- Attached groups sit `bar.layout.groupSpacing` (8 px) apart.
- A bar without `groups` uses its older `modules.left/center/right` lists as
  three groups (start, center, end); the first edit through Settings or the
  group menu saves them as `groups`.

Edit groups on the **Bar** page (pick the form, detach groups, drag modules
between groups), or right-click a group on the bar for **Detach group** /
**Attach group** and **Customize bar…**.

Bar modules: `sidebarButton`, `activeWindow`, `workspaces`, `clock`,
`weather`, `battery`, `network`, `bluetooth`, `tray`, `media`, `resources`,
`keyboard` (also `keyboardLayout`), `notifications`, `idle`, `privacy`,
`gamemode`.

## Network panel

`network.panelStyle` picks what the network and Bluetooth entry points open:

| Value | Opens |
|---|---|
| `"classic"` (default) | The inline pickers: the bar popouts pin open with the Wi-Fi / Bluetooth list, and the sidebar chevrons expand them. |
| `"orbit"` | **Network Orbit**, an animated panel adapted from ilyamiro's network popup. |

Set it on **Settings → Services → Network panel**. With `"orbit"`:

- Clicking the bar's `network` module opens Orbit on Wi-Fi (Ethernet when
  wired), and clicking `bluetooth` opens it on Bluetooth. Click again to close.
- The right sidebar's Wi-Fi and Bluetooth chevrons open it on that tab.
- Right-clicking the control panel's Wi-Fi or Bluetooth toggle opens it.

Network Orbit has a tab per available connection type: Ethernet, Wi-Fi,
Bluetooth, and VPN (when a provider is set under `vpn.providers`).

- **Cores:** connected devices glow in the middle. Several Bluetooth devices
  orbit each other.
- **Cards:** networks and devices you can connect to orbit around the cores.
  Once you're connected, the cards show the connection's details instead.
  **Scan** / **Current device** switches between the two.
- **Press and hold** a card to run it: connect, pair, copy the IP, sign in to a
  portal, forget the network, or unpair the device. Press and hold a core to
  disconnect it.
- **Password:** a secured Wi-Fi network that needs a password asks for it in
  the core. Enter connects, and Escape cancels.
- **Power:** the power button turns the tab's radio on or off. On the VPN tab
  it connects or disconnects, or opens the sign-in link when the provider asks
  for one.
- **Keys:** Tab cycles the tabs, and Escape closes the panel.

The panel is the `anoNetworkOrbit` module (Overlays, in the ano and hefty
families). Its IPC target is `networkOrbit`:

```sh
ano ipc call networkOrbit open wifi     # wifi | bt | vpn | eth
ano ipc call networkOrbit toggle bt     # "" toggles whatever tab is open
ano ipc call networkOrbit close
```

### NetBird

With `vpn.providers` set to NetBird, the right sidebar's Network card shows
the management and signal servers (with their errors), your NetBird IP and
FQDN (copy buttons), and how many peers are connected. It checks every 30 s,
every 2 s while the sidebar is open, and backs off to 5 min while the NetBird
service is down; `vpn.notifyOnChange` announces a management or signal
change.

- **Exit node:** choose **Direct** or one of your exit nodes (networks routing
  `0.0.0.0/0`). Only one is used at a time; choosing one deselects the others.
- **Networks:** each routed network has a switch (`netbird networks select -a`
  / `deselect`).
- The bar's network icon carries a small shield while the VPN is up, filled
  while traffic goes out an exit node; its popup names the exit node.

## anod hooks

Event hooks for anod live under `hooks` in the same file. See
[anod → Event hooks](anod.md#event-hooks).
