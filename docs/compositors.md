# Compositors

AnoShell talks to the compositor through one backend
(`services/compositor/`, contract in `BackendContract.md`). It picks the
backend from the session, or from `compositor.backend` when you force one
(Settings → Modules → Compositor):

| Backend | Detected by | Status |
|---|---|---|
| `hyprland` | `HYPRLAND_INSTANCE_SIGNATURE` | supported |
| `niri` | `NIRI_SOCKET` | supported (niri ≥ 26.04) |
| `sway` | `SWAYSOCK` | supported (sway ≥ 1.12) |
| `mango` | `MANGO_INSTANCE_SIGNATURE` | supported (mango ≥ 0.18) |
| `labwc` | `LABWC_PID` | supported (labwc ≥ 0.20) |
| `umbriel` | `UMBRIEL_SOCKET` | supported (umbriel ≥ 0.1) |
| `generic` | anything else | experimental |

`UMBRIEL_SOCKET` with `XDG_CURRENT_DESKTOP=umbriel` comes before everything,
Hyprland included: umbriel run nested in Hyprland passes
`HYPRLAND_INSTANCE_SIGNATURE` on to its clients. When several of the
other backends' variables are set, a matching `XDG_CURRENT_DESKTOP`
wins, then `UMBRIEL_SOCKET`, `MANGO_INSTANCE_SIGNATURE`, `LABWC_PID`
and `SWAYSOCK` last (sway exports it, and labwc `LABWC_PID`, to the
systemd/D-Bus activation environment, where a later session can inherit it).

Sway, mango, labwc and Umbriel have workspaces, the focused output,
fullscreen detection, the window list (overview, Alt+Tab, dock previews),
window focus/close and the dropdown terminal, and the shell runs on each of
them: tested headless (sway, labwc, mango) or nested (Umbriel), panels,
Settings and overview included. They don't have everything Hyprland and
niri have: no runtime blur rules, cursor zoom, screen shader or output
configuration, and Settings → Keybinds and Displays only edit Hyprland and
niri. Their reply parsing is tested against recorded replies
(`scripts/dev/test-sway-model.js`, `scripts/dev/test-mango-model.js`,
`scripts/dev/test-umbriel-model.js`).

`generic` (any other compositor) shows an "experimental" badge in Settings
and `ano doctor`: it has only what the shared protocols give.

## Bundled configs

`external/` has an AnoShell config for each compositor: it starts the shell
and anod, has the AnoShell keybinds (`qs -c ano ipc call …`, Super+Shift+T
for the dropdown terminal included) and the window and layer rules the shell
wants. Copy or link it; each file's header says where it goes and how to
check it.

| Compositor | Files | Check with |
|---|---|---|
| Hyprland | `external/hyprland/hyprland.lua` (+ `custom/`, `scripts/`) | `Hyprland --verify-config` |
| niri | `external/niri/ano.kdl` | `niri validate -c` |
| sway | `external/sway/ano.conf` → `~/.config/sway/config` | `sway -C -c` |
| mango | `external/mango/ano.conf` → `~/.config/mango/config.conf` | `mango -p -c` |
| labwc | `external/labwc/{rc.xml,autostart,shutdown,environment}` → `~/.config/labwc/` | labwc's log on start |
| Umbriel | `external/umbriel/ano.toml` → `~/.config/umbriel/config.toml` | `umbriel config validate` |

The sway, mango and Umbriel files load your own additions from a file
loaded last (`~/.config/<compositor>/local.conf`, `local.toml` for
Umbriel), so the bundled one can be replaced on update. The labwc
autostart leaves `labwc-session.target` off: starting it ties
graphical-session.target (portals, notifiers) to labwc's lifetime.

## Sway

Written against sway 1.12 ([sway-ipc(7)](https://github.com/swaywm/sway/blob/1.12/sway/sway-ipc.7.scd),
[sway(5)](https://github.com/swaywm/sway/blob/1.12/sway/sway.5.scd)).

- Workspaces come from ext-workspace-v1, which sway has since 1.12; earlier
  versions show none.
- Quickshell's I3 module gives the focused output and runs commands
  (`workspace number N`, `workspace next_on_output`, `exit`,
  `output * power off|on`, `gaps outer all set N`,
  `input type:keyboard xkb_switch_layout next|prev`, `[con_id=N] focus|kill`).
- Which workspaces hold windows, fullscreen and the window list come from
  `swaymsg -t get_tree`, and keyboard layouts from `swaymsg -t get_inputs`,
  refreshed on window, workspace and input events. Needs `swaymsg` (part of
  sway).
- Sway numbers workspaces across outputs, like Hyprland. A workspace without
  a leading number gets the smallest number no other workspace on its output
  has; switching goes through its
  ext-workspace handle, so it lands on the right one. Sway has no maximised
  state, so only fullscreen (a window's, a container's, or a global one,
  which covers every output) hides the bar.

## Mango

Written against mango 0.18.3 ([IPC](https://mangowm.github.io/docs/ipc/),
[dispatchers](https://github.com/mangowm/mango/blob/0.18.3/docs/bindings/keys.md),
[src/ipc/ipc.c](https://github.com/mangowm/mango/blob/0.18.3/src/ipc/ipc.c)).

- The shell connects to the socket in `MANGO_INSTANCE_SIGNATURE` directly; no
  `mmsg` needed. One line per connection: `watch all-monitors` and
  `watch all-clients` stay open and resend the whole state on every change;
  each `dispatch …` gets one reply and the connection closes. A watch that
  drops reconnects after 2 s.
- Tags are the workspaces: per monitor, numbered 1–9, several can be shown
  at once. A tag counts as occupied when it holds a client.
- Actions: `view,N` (or `viewcrossmon,N,<monitor>` on another monitor),
  `viewtoleft`/`viewtoright`, `quit`, `sleep_monitor`/`wakeup_monitor`
  per monitor, `switch_keyboard_layout` (forward only: mango's IPC doesn't
  list the layouts), `focusid` and `killclient` with `client,<id>`.
- Fullscreen and maximised clients come from the client list. With two tags
  shown on a monitor, its windows count as on the first.
- The dropdown terminal is minimized while hidden (`minimized`,
  `restore_minimized`) and placed with `resizewin`, `centerwin` and
  `smartmovewin`; it floats through the window rule in
  `external/mango/ano.conf` (without it, it opens tiled).
- The bundled config uses mango 0.18's keyword names (`exec_once`,
  `window_rule`, `layer_rule`, `border_px`); mango's newer docs spell some
  differently. Lines are read up to 255 bytes.

## Umbriel

Written against umbriel 0.1.0 (`umbriel --help`, `umbriel msg --help`,
[docs](https://docs.noctalia.dev/umbriel/)), run nested in Hyprland.

- Umbriel exports `UMBRIEL_SOCKET` (`$XDG_RUNTIME_DIR/umbriel-<display>.sock`)
  and `XDG_CURRENT_DESKTOP=umbriel` to everything it starts; the `umbriel`
  CLI finds the compositor through the first.
- One `umbriel subscribe windows,workspaces,keyboard_layout` process drives
  the backend: it prints a JSON line `{"event": …, "data": …}` holding the
  whole state of that kind at start and on every change (identical repeats
  are dropped). If it exits (umbriel restarted), it's started again after 2 s.
- Workspaces are per output, numbered from 1 (`index`), like niri's; umbriel
  keeps an empty one at the end. A window's `active` flag marks the focused
  window (`focused` only means focused within its workspace). Geometry is in
  layout coordinates.
- Fullscreen: a shown fullscreen window. Covered (wallpaper hidden): also a
  window maximised to the edges (`window-toggle-maximize-to-edges`); a
  full-width column (`window-toggle-maximize`) isn't.
- Actions run `umbriel msg`: `workspace-switch N [--output O]`,
  `workspace-next`/`workspace-previous`, `session-quit skip-confirmation`,
  `dpms-off`/`dpms-on`, `keyboard-layout-next` (Umbriel only steps forward:
  back is forward n−1 times), `window-focus <id>`, `window-close <id>`.
- No ext-background-effect-v1 and no runtime layer rules, so shell blur
  comes from the layer rules in the bundled `external/umbriel/ano.toml`
  (copy or link it to `~/.config/umbriel/config.toml`; it starts the shell
  and anod, and has the AnoShell keybinds with `qs -c ano ipc call …`).
  Gaps, cursor zoom, screen shaders and output configuration are config
  only; window capture isn't offered (Quickshell captures windows through
  Hyprland's toplevel export only).
- Settings → Keybinds (anod's keybind store) doesn't edit Umbriel's config
  yet: change the `[keybinds]` table by hand and check it with
  `umbriel config validate`.
- In a nested umbriel 0.1.0, `dpms-off` left the compositor unable to
  answer `outputs` queries, and `dpms-on` then hung; not tried on a real
  session.

## labwc

Written against labwc 0.20 ([labwc(1)](https://github.com/labwc/labwc/blob/0.20.2/docs/labwc.1.scd),
[labwc-config(5)](https://github.com/labwc/labwc/blob/0.20.2/docs/labwc-config.5.scd)).

labwc has no IPC. Workspaces and windows come from ext-workspace-v1 and the
foreign-toplevel protocol, as on the generic backend, and the session ends
with `labwc --exit`. The dropdown terminal is minimized and restored through
foreign-toplevel; where it opens comes from the window rule in
`external/labwc/rc.xml` (1440×640 at the top edge; labwc sizes in pixels).

If your `rc.xml` has a `<privilegedInterfaces>` block, labwc hides every
privileged protocol it doesn't list from non-sandboxed clients. AnoShell
needs these allowed:

| Interface | For |
|---|---|
| `zwlr_layer_shell_v1` | every shell surface (required) |
| `zwlr_foreign_toplevel_manager_v1` | windows: dock, switcher, task view |
| `ext_workspace_manager_v1` | workspaces |
| `ext_session_lock_manager_v1` | the lock screen |
| `zwlr_screencopy_manager_v1` | screenshots (`grim`) and window previews |
| `ext_data_control_manager_v1`, `zwlr_data_control_manager_v1` | clipboard history (`wl-paste`, `cliphist`) |
| `zwlr_gamma_control_manager_v1` | night light (`wlsunset`) |
| `ext_idle_notifier_v1` | idle actions |

## Generic

Any other Wayland compositor: workspaces from ext-workspace-v1 (shown ones
only count as occupied), windows and fullscreen from foreign-toplevel. No
session control (exit, DPMS, layouts).
