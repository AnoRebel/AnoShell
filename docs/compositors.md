# Compositors

AnoShell talks to the compositor through one backend
(`services/compositor/`, contract in `BackendContract.md`). It picks the
backend from the session, or from `compositor.backend` when you force one
(Settings → Modules → Compositor):

| Backend | Detected by | Status |
|---|---|---|
| `hyprland` | `HYPRLAND_INSTANCE_SIGNATURE` | supported |
| `niri` | `NIRI_SOCKET` | supported (niri ≥ 26.04) |
| `sway` | `SWAYSOCK` | experimental |
| `mango` | `MANGO_INSTANCE_SIGNATURE` | experimental |
| `labwc` | `LABWC_PID` | experimental |
| `generic` | anything else | experimental |

When several of the experimental backends' variables are set, a matching
`XDG_CURRENT_DESKTOP` wins, then `MANGO_INSTANCE_SIGNATURE`, `LABWC_PID`
and `SWAYSOCK` last (sway exports it, and labwc `LABWC_PID`, to the
systemd/D-Bus activation environment, where a later session can inherit it).

An experimental backend shows a badge in Settings and in `ano doctor`. It
has workspaces, the focused output, fullscreen detection and window
focus/close, but not everything Hyprland and niri have: no blur rules,
cursor zoom, screen shader or output configuration, and the Hyprland/niri
keybind and display pages don't apply. None of the three has been run
against a live session yet; they are written from the compositors'
documentation and source, and tested against recorded replies
(`scripts/dev/test-sway-model.js`, `scripts/dev/test-mango-model.js`).

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
  a leading number gets its place in the list; switching goes through its
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

## labwc

Written against labwc 0.20 ([labwc(1)](https://github.com/labwc/labwc/blob/0.20.2/docs/labwc.1.scd),
[labwc-config(5)](https://github.com/labwc/labwc/blob/0.20.2/docs/labwc-config.5.scd)).

labwc has no IPC. Workspaces and windows come from ext-workspace-v1 and the
foreign-toplevel protocol, as on the generic backend, and the session ends
with `labwc --exit`.

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
