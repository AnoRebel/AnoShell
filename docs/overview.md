# Overview

AnoShell is a desktop shell for Wayland built on
[Quickshell](https://quickshell.org): bars, sidebars, a dock, notifications,
an overview, a lock screen, settings and more, written in QML. It runs on
**Hyprland** and **niri**, and picks the compositor backend at runtime
(`compositor.backend` is `auto` by default; set it to `hyprland`, `niri` or
`generic` to force one).

The shell runs as the Quickshell config `ano` (`qs -c ano`) from
`~/.config/quickshell/ano`. Next to it, an optional companion daemon,
[anod](anod.md), handles what has to outlive a shell crash, and the
[`ano` CLI](cli.md) manages the install from a terminal. The shell never
depends on anod: without it, everything native keeps working and daemon
features show as unavailable.

## Panel families

A panel family is the set of modules the shell loads. Switching families only
loads or unloads the modules that differ.

| Family | Hosts |
|---|---|
| `ano` (default) | everything: bar, overlays, both sidebars, dock, HUD, task view, control panel, Network Orbit, media controls, weather, wallpaper selector, screen corners, Focus Time, Display Manager |
| `hefty` | the same minus Focus Time and Display Manager; morphing panels always on |
| `clean` | the core plus the sidebars, clipboard, cheatsheet and calendar; no dock or HUD |
| `minimal` | the core only: bar, overview, notifications, OSD, session screen, settings, search, window switcher, lock screen and the pill |

Set `panelFamily` in your config, pick it in Settings → Modules, cycle with
`Ctrl+Super+P` (in the bundled Hyprland and niri configs), or run `ano ipc call panelFamily cycle`. Inside any family you
can switch individual modules off on the Modules page; a module loads only
when its family hosts it, you haven't switched it off, its own feature key is
on, and the compositor supports it.

## The connected frame

By default every surface floats with its own background. In **Connected**
mode (`appearance.connectedCorners.enable`, or Settings → Appearance) the
screen gets a painted band with rounded inner corners, and every surface that
touches an edge (bar, pill, sidebars, dock, popouts, notifications, OSD, tray
menus) is drawn as part of one continuous shape, joined to the band by concave
fillets. Surfaces grow out of their own edge rather than sliding in.

While connected, the shell sets the compositor's outer gap to 0 so windows sit
flush against the band, and the band reserves its thickness on edges no bar
covers. When a window goes fullscreen the frame retracts, and the bar and pill
slide into their edges. How it works is in [Architecture](architecture.md).

## The pill (AnoSpot)

AnoSpot is a floating media and status pill on any screen edge (`top`,
`bottom`, `left` or `right`). It shows the playing track, incoming
notifications, screen recording, the clock and weather, battery and the
current workspace (each one can be turned off), with workspace previews on
hover (`anoSpot.workspaceHoverPreview`). Files dropped on it go to a stash or to configurable drop actions.

It's off by default: turn it on with `anoSpot.enable` or on the AnoSpot
settings page. In Connected mode it fuses into the frame unless
`anoSpot.floating` is set. With `anoSpot.pillOnly`, the pill is the whole shell
chrome: no bar and no dock.

## Where to go next

- [Installation](installation.md): clone the shell and install anod and the CLI.
- [Configuration](configuration.md): your config file, Settings, bar forms and groups.
- [The `ano` CLI](cli.md): status, doctor, setup and backups.
- [Reader](reader.md): the novel, manga and anime panels.
- [Keybinds](keybinds.md): one keybind set for Hyprland and niri.
- [Displays and cursor](displays.md): arrangement, modes, profiles, cursor.
- [Welcome and presets](onboarding.md): the first-start wizard and whole-shell presets.
