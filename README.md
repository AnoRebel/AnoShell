# AnoShell

A Quickshell desktop shell for Wayland compositors (developed and tested on
Quickshell 0.3.2 / Qt 6.11). **Hyprland** and **niri** are supported;
**sway**, **mango** and **labwc** run on experimental backends, and any other
compositor on a generic one ([docs/compositors.md](docs/compositors.md)). The
backend is picked from the session at start.

**Documentation:** [anoshell.anorebel.net](https://anoshell.anorebel.net) (stable) · [anoshell-dev.anorebel.net](https://anoshell-dev.anorebel.net) (development) · source in [`docs/`](docs/overview.md)

## What's in it

- **Panels and the pill:** bars in several forms with attachable groups, the
  AnoSpot pill (faces, transients, any edge), sidebars, dock, launcher,
  overview, and four panel families; with the connected frame they fuse into
  one curved surface ([overview](docs/overview.md), [the pill](docs/anospot.md)).
- **Looks and colours:** Liquid, Ink, Neo-tech and Clay looks, static themes or
  wallpaper colours (matugen), glass, colour modes, your own looks
  ([looks](docs/looks.md)).
- **Atelier:** themes, looks, pieces, plugins, lock screens, wallpapers (and Wallhaven) and whole-setup
  rices from built-in, your folders and catalogs, with checksums, a code check
  and undo ([atelier](docs/atelier.md)).
- **Pieces** (desktop widgets) in pages on a grid, plus your own ([pieces](docs/pieces.md)).
- **Reader:** novels, manga and anime (resume, intro skip, Airing), fused into
  the frame ([reader](docs/reader.md)).
- **System:** network and NetBird VPN panel, Bluetooth, audio and EasyEffects,
  brightness, night light, power and performance mode, device pills, package
  updates, removable drives, notifications with DND, lock screen, screen time
  with limits, screenshots (freeze-frame regions) and screen recording,
  song recognition, lyrics ([extras](docs/extras.md), [configuration](docs/configuration.md)).
- **anod and `ano`:** the companion daemon (wallpapers, hooks, keybinds,
  displays, backups, the Atelier, the reader backend) and its CLI: `ano doctor`,
  `ano backup`, `ano atelier`, `ano keybinds` ([anod](docs/anod.md), [CLI](docs/cli.md)).
- **Settings** for all of it, as an overlay or a standalone window, with a
  Ctrl+K search over every option.

Shell source lives at `~/.config/quickshell/ano/`. Generated state and user-writable overrides live under the `anoshell` namespace: `~/.config/anoshell/` (config + themes + lyrics), `~/.local/state/anoshell/`, `~/.cache/anoshell/`.

## Quick Start

```bash
# Get the shell where Quickshell finds it, then the daemon and CLI
git clone https://github.com/AnoRebel/AnoShell.git ~/.config/quickshell/ano
~/.config/quickshell/ano/anod/install.sh     # anod + ano into ~/.local/bin

# Launch it
qs -c ano

# Check what's installed and what's missing
ano doctor

# Settings on their own
qs -n -p ~/.config/quickshell/ano/settings.qml
```

To start it with your session, use the bundled compositor configs
(`external/hyprland/hyprland.lua`, `external/niri/ano.kdl`); see
[docs/installation.md](docs/installation.md).

## Services

Service singletons sit under `services/` and are auto-loaded by `import "services"` in `shell.qml`. They expose state and methods that any module (and IPC handlers) can read/call. Most are dormant until referenced.

### Compositor & windows

| Service | What it provides |
|---------|------------------|
| `CompositorService` | One API over the compositor backends in `services/compositor/` (Hyprland, niri; experimental: sway, mango, labwc, generic): workspaces, windows (leased), outputs, fullscreen, keyboard layout, actions. |
| `NiriService` | Full Niri IPC over its UNIX socket — events, window list, workspace list, focus changes. |
| `HyprlandKeybinds` / `NiriKeybinds` | Parsers for the live keybinds files. Power the cheatsheet. |
| `AnoSocket` | Auto-reconnecting socket helper used by NiriService. |
| `MinimizedWindows` | Niri-only minimize emulation registry (Niri has no native minimize concept). |

### Audio, brightness, input

| Service | What it provides |
|---------|------------------|
| `Audio` | PipeWire default sink/source. Volume/mute, mic mute, volume protection. |
| `Brightness` | `brightnessctl` for backlight + `ddcutil` for external monitors via DDC/CI. |
| `Battery` | UPower charge/health/time-remaining + auto-suspend trigger. |
| `KeyboardLayoutService` | Active XKB layout on both Hyprland and Niri, plus click-to-cycle on Niri. |
| `Idle` | Wayland IdleInhibitor toggle (caffeine-style). |
| `IdleInhibitor` | Per-app inhibit registry. |

### Network, devices, system

| Service | What it provides |
|---------|------------------|
| `Network` | nmcli-backed WiFi scanning/connect/disconnect, signal strength, hotspot toggle. |
| `NetworkUsage` | rx/tx throughput polled from `/proc/net/dev`. Opt-in via `network.usage.enable`. |
| `VPN` | Connect/disconnect/status for tailscale, netbird, warp, wireguard, or custom providers. |
| `BluetoothStatus` | Adapter state + paired/connected device list. |
| `TrayService` | System tray entries with pinning + DBus menu support. |
| `Cliphist` | Clipboard history with fuzzy search. |
| `ResourceUsage` | CPU / RAM / swap / network from `/proc`. |
| `Privacy` | Mic-active and cam-active detection. |
| `GameMode` | Follows gamemoded over D-Bus (no polling) and drives performance mode (pauses animations, blur, visualisers and popups while a game runs, a window is fullscreen, or by hand). |
| `PowerProfilePersistence` | Restores last `power-profiles-daemon` profile on shell start. |
| `ShellExec` | Shell-runtime detection + safe exec helper. |

### Theme & appearance

| Service | What it provides |
|---------|------------------|
| `MaterialThemeLoader` | Watches the wallpaper-derived MD3 JSON and writes into `Appearance.m3colors` when source is Material You. |
| `StaticThemeLoader` | Loads `assets/themes/<name>.json` (or `~/.config/anoshell/themes/<name>.json`) when source is static. Defers to `Appearance.previewTokens` during Settings hover-preview. |
| `ThemeRegistry` | Discovers + indexes all available themes (bundled + user). Exposes `themes` ListModel and `themeContents` (parsed JSON cache). |
| `Wallpapers` | The wallpaper folder for the picker, anod palette (hue, stills), favourites, apply via anod. |
| `Wallhaven` | Wallhaven search + download for the picker; API key in `~/.local/share/anoshell/secrets/wallhaven` (0600). |
| `AntiFlashbang` | Hyprland GLSL shader that darkens bright screens. IPC-controlled. |
| `Pieces` | Desktop piece registry (bundled `pieces/` + `~/.config/anoshell/pieces/`, live, broken ones marked) and the per-screen layout; the layer is `modules/pieces` ([docs/pieces.md](docs/pieces.md)). Off by default. |
| `NightLight` | wlsunset wrapper. Warm now (the toggle), or automatically from sunset to sunrise or between set times. Opt-in. |

### Media

| Service | What it provides |
|---------|------------------|
| `MprisController` | Active Mpris player tracking, duplicate filtering, position polling. |
| `LyricsService` | Synced `.lrc` parsing — local files first, falls back to LRCLIB / NetEase. Opt-in. |
| `SpectrumService` | Cava audio spectrum, reference-counted (only runs when something subscribes). |
| `RecorderStatus` | Screen recording with gpu-screen-recorder, wl-screenrec or wf-recorder (fps, audio none/system/mic/both, discard, finish preview); state from its own recorder process. |

### Time, weather, notifications, calendar, AI

| Service | What it provides |
|---------|------------------|
| `DateTime` | Formatted clock + uptime. |
| `Weather` | wttr.in API client with optional GPS. |
| `Notifications` | DBus notification server with persistent storage and popup management. |
| `CalendarSync` | iCal/CalDAV pull from configured URLs. Opt-in. |
| `Ai` | AI chat across OpenAI, Gemini, Anthropic, Mistral, OpenRouter, Ollama. Streaming + Anthropic thinking blocks. |
| `FocusTime` | Daemon lifecycle for the per-app usage tracker (SQLite-backed Python daemon). |

### AnoSpot

| Service | What it provides |
|---------|------------------|
| `AnoSpotState` | Aggregated state shared between the AnoSpot pill and its widgets. |
| `AnoSpotStash` | Manages the drag-and-drop stash directory ($XDG_RUNTIME_DIR/anoSpot or fallback). |

## Configuration

All settings in `config.json`. GUI via Settings overlay (`qs -c ano ipc call settings toggle`) or standalone window (`qs -n -p settings.qml`). Both share the same page components and behave identically — including keyboard navigation:

| Key | Action |
|-----|--------|
| `Ctrl+K` | Open the command palette (search every config key) |
| `Up` / `Down` | Cycle nav rail (when no input is focused) |
| `Tab` / `Shift+Tab` | Cycle pages or default Tab traversal inside an input |
| `Ctrl+1`..`Ctrl+9` | Jump to page N |
| `Ctrl+0` | Jump to last page |
| `Esc` | Close the panel (overlay) or quit (standalone) |

**Command palette (`Ctrl+K`).** Search every setting by the words you see in Settings (card titles, control labels and descriptions) or by config key — case-insensitive, multi-word (every term must match somewhere). Keys come live from the config; labels come from `modules/settings/settings-index.json` (generated, see *Keeping settings wired* below). Up/Down move the highlight, Enter jumps to the page that owns the key and scrolls to its card, Esc closes.

```
Ctrl+K → "event border"   → anoSpot.eventBorder.holdMs   → AnoSpot · Event border animation
Ctrl+K → "hotspot"        → network.hotspot.password     → Services · Network usage tracking
Ctrl+K → "lyrics"         → lyrics.dir                   → Services · Lyrics
Ctrl+K → "wallpaper rot"  → background.randomize         → Appearance · Wallpaper Rotation
```

Each page also has a per-page "Reset" affordance in its header (only visible when that page has overridden any keys), and AboutPage has a global "Reset every setting" card. Both reset paths target only the user delta at `~/.config/anoshell/config.json`; bundled defaults are never written to.

### How config persistence works

There are two config files:

- **`~/.config/quickshell/ano/config.json`** — bundled defaults that ship with the shell. Read-only at runtime; nothing the shell does writes here.
- **`~/.config/anoshell/config.json`** — your per-machine delta. Sparse: only contains keys you've actually changed. **The Settings UI writes here.**

On startup the shell reads the bundle for defaults, then deep-merges your delta on top. This means:

- The user file is **portable** — copy it to another machine for an identical configuration without bringing the entire bundle along.
- Shell upgrades that bump bundle defaults reach you automatically for any keys you haven't customised.
- "Reset to defaults" (per-page or global, in Settings) deletes keys from the user file rather than writing the default value into it.

You can edit the user file directly if you prefer JSON over the GUI. The shell watches it with `watchChanges: true` — saves apply within ~100ms with no restart needed:

```json
// Example ~/.config/anoshell/config.json — only the keys you've customised
{
  "bar": {
    "layout": { "height": 38, "radius": 16 },
    "actions": { "leftClick": "settings" }
  },
  "anoSpot": {
    "enable": true,
    "position": "bottom"
  },
  "appearance": {
    "theme": { "source": "static", "static": "tokyo-night-dark" }
  },
  "nightLight": { "schedule": "times", "start": "21:00", "end": "07:00", "nightTemp": 3500 }
}
```

**Semantics**

- Plain objects merge recursively (your `bar.layout.height` doesn't wipe `bar.actions`).
- Arrays and scalars replace entirely (setting `enabledPanels: [...]` replaces the whole list).
- A malformed JSON file fires a desktop notification with the line/column of the parse error and the last-known-good config keeps applying — the shell never crashes on a stray comma.
- Removing a key from the user file reverts that key to the bundle default on the next reload.

### Settings pages

The Settings UI has 12 pages, each owning a set of top-level config keys. The "Reset" header button on each page only clears keys it owns; the global "Reset every setting" card on the About page wipes the entire user delta.

| Page         | Owns                                                                                     | What you'll find there |
|--------------|------------------------------------------------------------------------------------------|------------------------|
| General      | `audio`, `battery`, `time`, `notifications`, `interactions`, `sounds.battery`, `session` | Volume protection, battery thresholds (with ordering warning), clock/date format with live preview, notification timeout/silent/max popups, logout & shutdown confirmation, scroll speed |
| Modules      | `enabledPanels`, `panelFamily`, `osd`, `screenCorners`, `altSwitcher`, `apps`, `focusTime`, `taskView`, `media`, `compositor`, `displayManager`, `display.primaryMonitor`, `sounds.theme`, `bar.morphingPanels` | Searchable + categorised module enable/disable, OSD indicators, hot corners, app launcher options, compositor fallback, panel-family picker, advanced toggles |
| Bar          | `bar`, `bars`, `tray`                                                                    | Edge picker (visual), per-section module chip editor, click/scroll actions, layout sliders, weather, tray pinning |
| Dock         | `dock`                                                                                   | Position, style (pill/macOS), sizing, hover-reveal, pinned apps |
| Sidebars     | `sidebar`                                                                                | Behavior toggles (instant open, keep loaded), right-sidebar widget picker with empty-state warning, quick-slider sub-toggles |
| AnoSpot      | `anoSpot`                                                                                | Position, per-widget visibility, click bindings, event border animation, drag/drop config + custom drop actions |
| Appearance   | `appearance`, `background`, `animations`                                                 | Theme source (Material You / static) with hover-preview, font picker, bezel preview, animation speed, wallpaper rotation |
| Overview     | `overview`                                                                               | AnoView layout selector (11 cards) |
| Services     | `ai`, `gameMode`, `powerProfiles`, `network`, `vpn`, `nightLight`, `lyrics`, `calendar`, `resources`, `light`, `shell`, `weather` | Toggle and configure every optional service (see Optional services below) |
| Displays     | `cursor`, `icons`                                                                        | Monitor arrangement, mode, scale, rotation, VRR and profiles (through anod), cursor and icon themes |
| Keybinds     | `keyboard`                                                                               | Search, record, add, change or remove binds; keyboard layouts |
| About        | `user`                                                                                   | Presets, export/import, backup & restore (through anod, same archives as `ano backup`), avatar picker, system info, credits, global "Reset every setting" card |

Settings opens via `qs -c ano ipc call settings toggle`, the standalone window via `qs -n -p ~/.config/quickshell/ano/settings.qml`, or `Super+,` (Hyprland default).

### Bar System
```json
{
  "bars": [{
    "id": "main",
    "edge": "top",
    "modules": { "left": [...], "center": [...], "right": [...] },
    "autoHide": false,
    "showBackground": true,
    "morphingPanel": false,
    "height": null, "radius": null,
    "leftSpacing": null, "centerSpacing": null, "rightSpacing": null,
    "edgePadding": null
  }],
  "bar": {
    "layout": { "height": 42, "radius": 12, "leftSpacing": 8, "centerSpacing": 4, "rightSpacing": 8, "edgePadding": 8, "centerGroupPadding": 5, "centerGroupRadius": 8, "showCenterBackground": true, "showSeparators": false },
    "actions": { "leftClick": "sidebarLeft", "rightClick": "sidebarRight", "centerClick": "overview", "scrollLeft": "brightness", "scrollRight": "volume", "scrollCenter": "workspace" }
  }
}
```
Per-bar fields (null = use global): `morphingPanel`, `height`, `radius`, all spacing/padding/action fields.
Available bar modules: `clock`, `workspaces`, `battery`, `network`, `bluetooth`, `tray`, `media`, `resources`, `activeWindow`, `sidebarButton`, `weather`, `keyboard` (alias `keyboardLayout`), `notifications`, `idle`, `privacy`, `gameMode`

### Panel Families
Switch entire layout presets atomically. A family is the set of modules it hosts, declared in `modules/common/PanelGate.qml` (`familyModules`); switching only loads/unloads the modules that differ. Turning a module off in Settings → Modules (or its own enable key) works in every family:

| Family   | Includes                                                                  | Best for                          |
|----------|---------------------------------------------------------------------------|-----------------------------------|
| `ano`    | Bar + Dock + both Sidebars + HUD + AI + Overview + Focus Time + Display Manager + everything | Default daily driver |
| `hefty`  | Same as `ano` minus Focus Time/Display Manager; morphing panels always on | Maximalist visual                 |
| `clean`  | Bar + Sidebars + clipboard/cheatsheet/calendar. No dock, hot corners, HUD | Focused work                      |
| `minimal`| Bar + bare overlays only. No sidebars, no dock, no HUD                    | Lightweight / external launchers  |

Connected mode and AnoSpot are available in every family.

Set via `panelFamily: "ano"|"hefty"|"clean"|"minimal"` in `config.json`, cycle with `Ctrl+Super+P`, or via `qs -c ano ipc call panelFamily cycle`. Switching plays a configurable ripple-transition animation (`familyTransitionAnimation: true`).

### Sidebar Right widgets
Configurable via `sidebar.right.enabledWidgets[]` in any order:

| Widget          | Purpose                                                            |
|-----------------|--------------------------------------------------------------------|
| `systemButtons` | Uptime + reload/settings/session row                               |
| `quickSliders`  | Volume / Brightness / (optionally) Mic                             |
| `quickToggles`  | WiFi / Hotspot / BT / DND / Idle / NightLight pills                |
| `networkDetail` | Bandwidth (rx/tx) + VPN status (auto-hides when both dormant)      |
| `media`         | Compact Mpris player                                               |
| `notifications` | Recent notifications                                               |
| `calendar`      | Month grid                                                         |
| `systemInfo`    | CPU / RAM / Battery gauges                                         |

The night-light pill has a chevron — tap the body to toggle, tap the chevron to expand an inline temperature slider (animated reveal).

### Theme system
Two color sources, switched via `appearance.theme.source`:

- **`materialYou`** (default) — `MaterialThemeLoader` derives Material 3 palette from the active wallpaper via matugen.
- **`static`** — `StaticThemeLoader` reads `assets/themes/<name>.json` (or user override `~/.config/anoshell/themes/<name>.json`). 24 themes ship in the bundle (dark + light variants of Catppuccin, Dracula, Nord, Tokyo Night, Gruvbox, Kanagawa, Rosé Pine, Ayu, Eldritch, Noctalia, Inir, plus Angel and Aurora).

Pick from Settings → Appearance → Theme grid (hover-preview, click-to-commit). Themes optionally export `glass_*` keys consumed by `Appearance.glassTokens` for translucent surfaces (RecordingOsd, AnoSpot pill, AnoSpot stash popout).

### AnoSpot (dynamic-island overlay)
Top/bottom/left/right pill overlay aggregating now-playing (Mpris), latest notification, recording indicator (with elapsed timer), clock/weather, workspace number, and battery. Compositor-agnostic (Hyprland + Niri). Click to expand into related panels; drag from a file manager to stage files for triage actions like sending via LocalSend.

```json
"anoSpot": {
  "enable": false,
  "position": "top",            // top | bottom | left | right (invalid → top)
  "widthPx": 420, "heightPx": 36,

  // Per-widget visibility
  "showMpris": true,
  "showNotification": true,
  "showRecording": true,
  "showClockWeather": true,
  "showWorkspace": true,
  "showBattery": true,
  "notificationTimeoutMs": 4000,

  // Click bindings — each value is the IPC target opened by `qs -c ano ipc call <target> toggle`
  "actions": {
    "leftClick": "mediaControls",
    "rightClick": "controlPanel",
    "middleClick": "anoview",
    "scrollOnMpris": "audio"     // wheel on the Mpris widget → volume up/down
  },

  // Animated gradient halo that pulses on configured events
  "eventBorder": {
    "enable": true,
    "holdMs": 1500,
    "events": ["notification", "track", "recording", "workspace"]
  },

  // Drag-handle to reposition (release snaps to nearest screen edge)
  "draggable": true,

  // Drag and drop
  "acceptDrops": true,
  "stashDir": "",                // empty = auto ($XDG_RUNTIME_DIR/anoSpot, /tmp/anoSpot-<UID> fallback)
  "dropTargets": []              // user-defined custom action buttons; see below
}
```

Toggle from Settings → AnoSpot. Page warns when `anoSpot.position` collides with `bars[0].edge` (visual overlap likely).

#### Click bindings
| Trigger              | Default action                        | Configurable via                      |
|----------------------|---------------------------------------|---------------------------------------|
| Left click           | open Media Controls                   | `actions.leftClick`                   |
| Right click          | open Control Panel                    | `actions.rightClick`                  |
| Middle click         | open AnoView (overview)               | `actions.middleClick`                 |
| Wheel on Mpris area  | volume up/down                        | `actions.scrollOnMpris` (`""` = off)  |
| Click Workspace widget | open AnoView (overview)             | (hard-coded discoverability shortcut) |

Each `actions.*` value is the IPC target name; the dispatcher invokes `qs -c ano ipc call <target> toggle`. Set to `""` to disable.

#### Drag and drop
Drop files (or any `text/uri-list` payload) on the pill to stage them in an ephemeral stash directory. The popout opens with a thumbnail-grid view of the staged items, per-item × removal, and an action toolbar.

Built-in actions:

| Action       | Behavior                                                 | Requires                          |
|--------------|----------------------------------------------------------|-----------------------------------|
| LocalSend    | mDNS + /24 sweep for LocalSend devices, then send each staged file to the picked device | `python3`, `curl`, `openssl`, `iproute2` (all standard) |
| Open         | `xdg-open` each staged item with the user's default app  | `xdg-utils`                       |
| Copy path    | Newline-joined absolute paths to the wl-clipboard        | `wl-clipboard`                    |
| Move to…     | zenity directory picker, then `mv` each item there       | `zenity`                          |
| Reveal       | `xdg-open` the parent directory in the user's file manager | `xdg-utils`                     |
| Clear all    | Empty the stash and close the popout                     | —                                 |

Stash directory resolution order:
1. `Config.options.anoSpot.stashDir` if non-empty (explicit override)
2. `$XDG_RUNTIME_DIR/anoSpot` (preferred — per-user, ephemeral, auto-cleaned at logout)
3. `/tmp/anoSpot-<UID>` (fallback if `XDG_RUNTIME_DIR` is unset)

The directory is created on first use. Originals are never moved; AnoSpot stages copies and acts on those copies.

#### Custom drop actions
Add user-defined buttons to the popout footer via `Config.options.anoSpot.dropTargets[]`. Each rule:

```json
{
  "name":    "Encode for web",
  "icon":    "compress",          // any Material Symbols name
  "action":  "shell",             // "exec" = argv-split (safe, no shell) | "shell" = bash -c
  "command": "ffmpeg -i {path} -c:v libx264 -crf 28 {dir}/{name}.web.mp4",
  "perItem": true                 // true = invoke once per staged item; false = once with full set
}
```

Placeholder substitution:

| Placeholder | Substituted with                              |
|-------------|-----------------------------------------------|
| `{path}`    | First item's full absolute path               |
| `{name}`    | First item's basename                         |
| `{dir}`     | First item's parent directory                 |
| `{ext}`     | First item's extension (without leading dot)  |
| `{paths}`   | Newline-joined absolute paths (full set)      |
| `{names}`   | Newline-joined basenames (full set)           |

Action modes:
- **`exec`** — Splits `command` on whitespace, substitutes each arg individually, runs the resulting argv directly. No shell, no globs, no pipes. Safe for paths with spaces or special characters.
- **`shell`** — Substitutes the whole `command` string then runs via `bash -c`. Pipes, redirects, and globs work. You quote your paths.

Edit the rule list in Settings → AnoSpot → "Custom drop actions" — fields, add, remove, and a built-in placeholder cheat-sheet.

#### Event border animation
The pill renders a gradient halo behind itself that pulses when configured events fire. Subscribe/unsubscribe per event type via `eventBorder.events` (e.g. drop `"workspace"` if it's too chatty for your workflow). Hold duration controls how long the halo stays visible before fading.

> **Renamed** from `ActivSpot`. If your existing `config.json` still uses the old `activSpot` key, it is migrated automatically on first start (values copied to `anoSpot`, old key removed; one-shot, idempotent).

### Overview (AnoView)
Layouts: `smartgrid`, `justified`, `bands`, `masonry`, `hero`, `spiral`, `satellite`, `staggered`, `columnar`, `vortex`, `random`

### AI Chat
Providers: **Gemini** (2.5 Flash, 3 Flash), **Anthropic** (Claude Sonnet 4, Haiku 3.5), **OpenAI** (GPT-4.1 Mini), **Mistral** (Medium 3), **OpenRouter** (dynamic free models), **Ollama** (local auto-detect). Commands: `/model`, `/key`, `/temp`, `/prompt`, `/save`, `/load`, `/clear`

### Optional services
All of the following are **disabled by default**. Enable from Settings → Services or by editing `config.json` directly.

| Block | Purpose | Notable keys |
|---|---|---|
| `gameMode.enable` | Bar indicator while a game holds GameMode | — |
| `performance` | Performance mode: what turns it on (`onGameMode` on by default, `onFullscreen`) and what it pauses | `stopAnimations`, `stopBlur`, `stopVisualizers`, `holdPopups`; IPC `performance toggle\|on\|off\|status` |
| `powerProfiles.restoreOnStart` | Restore last `power-profiles-daemon` profile on shell start | `preferredProfile` (auto-populated when you change profiles) |
| `network.usage` | Per-interface rx/tx polling for the sidebar bandwidth panel | `intervalMs`, `historyLength` |
| `network.hotspot` | WiFi tethering toggle backed by `nmcli device wifi hotspot` | `ssid`, `password` (auto-generated on first enable) |
| `vpn` | Generic VPN status + connect/disconnect for tailscale/netbird/warp/wireguard/custom | `providers[]`, `notifyOnChange` |
| `calendar` | KHal/CalDAV pull into the calendar panel | `upcomingDays`, `externalSync.{enable, refreshMinutes, sources[]}` |
| `lyrics` | Synced lyric overlay in MediaControls + AnoSpot | `enable`, `backend`, `dir` |
| `nightLight` | wlsunset-backed warm-shift (Hyprland, niri, sway) | `enable` (on now), `schedule` (off/sun/times), `start`, `end`, `fade` (min), `dayTemp`, `nightTemp`, `latitude`, `longitude`, `gamma`, `outputs` |
| `lock.notifications` | Mirror notifications onto the lock screen | `maxItems` |
| `lock.osk` | On-screen keyboard for password entry | — |
| `lock.statusRow` | Battery + WiFi + clock chips on the lock screen | — |
| `lock.dim` | Auto-dim the lock background after idle | `idleMs`, `opacity` |
| `lock.passwordInput.expandOnFocus` | Animate the password field on focus | — |
| `anoSpot.showLyrics` | Swap track title for the current lyric line | requires `lyrics.enable` |
| `anoSpot.workspaceHoverPreview` | Hover the workspace pill to see live thumbnails | `openDelayMs`, `closeDelayMs`, `thumbnailWidth`, `thumbnailHeight` |
| `appearance.theme` | Switch between dynamic Material You and bundled static themes | `source` (`materialYou`/`static`), `static` (theme name) |

`appearance.theme.source = "static"` activates the StaticThemeLoader, which reads `assets/themes/<name>.json` (or `~/.config/anoshell/themes/<name>.json` to override). 24 themes ship in the bundle (Catppuccin, Dracula, Nord, Tokyo Night, Gruvbox, Kanagawa, Rosé Pine, Ayu, Eldritch, Noctalia, Aurora, Inir, Angel — most with dark/light variants).

### Module Enable/Disable
Every module is toggleable via the `enabledPanels` array (empty = all) or the Modules settings page, in every panel family. A module loads only when its family hosts it, you haven't switched it off, its own feature key (e.g. `dock.enable`, `focusTime.enable`) is on, and the compositor supports it — see `modules/common/PanelGate.qml`. Disabled modules are never even compiled.

### Keeping settings wired (developers)
- Every key lives in the schema (`modules/common/Config.qml`), the bundled defaults (`config.json`) and is read by runtime code outside `modules/settings/`.
- Runtime code changes settings only through `Config.setNestedValue("a.b", value)`; it is a no-op when the value doesn't change, so controls echoing their initial value never write.
- Per-bar fields in `bars[]` are `null` to follow the global setting.
- After adding or renaming a control or key, run:

```sh
python3 scripts/dev/settings-index.py   # regenerate the palette label index
python3 scripts/dev/settings-audit.py   # exit 1 on dead, undeclared, mismatched keys or a stale index
```

## IPC Commands
```bash
qs -c ano ipc call <target> <method>
```
| Target | Methods |
|--------|---------|
| `bar` | `toggle`, `open`, `close` |
| `sidebarLeft` / `sidebarRight` | `toggle`, `open`, `close` |
| `anoview` | `toggle [layout]`, `open`, `close` |
| `overviewWorkspacesToggle` | `toggle` (workspace-strip overview) |
| `settings` / `settingsStandalone` | `toggle`, `open` / `open` |
| `audio` | `toggleMute`, `toggleMicMute`, `increment`, `decrement` |
| `brightness` | `increment`, `decrement` |
| `mpris` | `pauseAll`, `playPause`, `previous`, `next` |
| `idle` | `toggle`, `enable`, `disable` |
| `hud` | `toggle`, `open`, `close` |
| `session` | `toggle`, `open`, `close` |
| `dock` | `toggle`, `pin`, `unpin` |
| `clipboard` / `cliphistService` | `toggle`, `open`, `close` / direct cliphist actions |
| `altSwitcher` | `show`, `hide`, `next`, `prev`, `activate` |
| `search` | `toggle`, `open`, `close` |
| `taskView` | `toggle`, `open`, `close` |
| `mediaControls` | `toggle`, `open`, `close` |
| `controlPanel` | `toggle`, `open`, `close` |
| `weatherPanel` | `toggle`, `open`, `close` |
| `calendar` | `toggle`, `open`, `close` |
| `recordingOsd` | `toggle`, `open`, `close` |
| `cheatsheet` | `toggle`, `open`, `close` |
| `lock` | `lock` |
| `wallpapers` / `wallpaperSelector` | `apply path` / `toggle` |
| `ai` | `run "text or /command"` |
| `panelFamily` | `cycle`, `set family` |
| `shell` | `reload`, `quit` |
| `screenCorners` | `enable`, `disable`, `toggle` |
| `focusTime` | `toggle`, `open`, `close` |
| `displayManager` | `toggle`, `open`, `close` |
| `antiFlashbang` | `toggle`, `enable`, `disable` |
| `niriKeybinds` | `reload` (re-parse KDL) |
| `minimize` | `toggle` (Niri minimize emulation) |
| `zoom` | `zoomIn`, `zoomOut` |
| `TEST_ALIVE` | _(no methods — existence check)_ |

## Keybinds (Hyprland)

Source files: `~/.config/hypr/Ano/hyprland/keybinds.conf` (defaults, tracked) and `~/.config/hypr/Ano/custom/keybinds.conf` (user overrides, sourced after defaults). Equivalent Niri bindings live at `~/.config/niri/ano.kdl`. Both are reachable via symlinks under `external/{niri,hyprland}/` inside this repo.

### QuickShell UI Toggles
| Key | Action |
|-----|--------|
| `Super` (tap) | Search/launcher |
| `Super+Tab` | Overview (AnoView) |
| `Super+`` ` | Task view |
| `Super+B` | Left sidebar (AI/notifications) |
| `Super+N` | Right sidebar (controls) |
| `Super+A` | App search |
| `Super+I` | Control panel |
| `Super+,` | Settings |
| `Super+Shift+I` | HUD |
| `Alt+V` | Clipboard history |
| `Super+O` | Media controls |
| `Super+X` | Session menu |
| `Super+/` | Cheatsheet |
| `Super+Shift+B` | Toggle bar |
| `Super+Shift+D` | Toggle dock |
| `Super+Shift+W` | Weather panel |
| `Super+Shift+F` | FocusTime tracker |
| `Super+−` / `Super+=` | Zoom out / in |
| `Ctrl+Super+D` | Display manager |
| `Ctrl+Super+T` | Wallpaper selector |
| `Ctrl+Super+B` | Anti-flashbang shader |
| `Ctrl+Super+P` | Cycle panel family |
| `Ctrl+Super+R` | Restart QuickShell |

### Pyprland
| Key | Action |
|-----|--------|
| `Super+Shift+T` | Dropdown terminal |
| `Super+M` | Toggle minimized workspace |
| `Super+Shift+-` | Minimize/restore window |
| `Ctrl+Super+L` | Fetch lost windows |

### Screenshots & Capture
| Key | Action |
|-----|--------|
| `Super+Shift+S` | Region screenshot |
| `Super+Shift+X` | OCR (text recognition) |
| `Super+Shift+G` | Google Lens search |
| `Super+Shift+R` | Screen recording |
| `Super+Shift+C` | Color picker |
| `Print` | Full screenshot to clipboard |
| `Shift+Print` | Region screenshot (swappy) |

### Window Management
| Key | Action |
|-----|--------|
| `Super+Space` | Toggle floating |
| `Super+F` | Fullscreen |
| `Super+S` | Toggle split |
| `Super+Q` | Kill active |
| `Super+C` | Center window |
| `Super+G` | Toggle group |
| `Super+Alt+A` | Toggle special workspace |
| `Super+Shift+A` | Move to special workspace |
| `Super+1-0` | Switch workspace 1-10 |
| `Super+Shift+1-0` | Move to workspace 1-10 |

### Session
| Key | Action |
|-----|--------|
| `Super+L` | Lock screen |
| `Super+Shift+L` | Suspend |
| `Super+Alt+F1` | VM mode (disable keybinds) |

## External Packages

### Required
| Package | Purpose |
|---------|---------|
| `quickshell` (tested with 0.3.2) | Shell framework |
| `awww` + `awww-daemon` | Wallpaper engine |
| `matugen` ≥4.0 | Material You color generation |
| `jq` | JSON parsing in scripts |
| `brightnessctl` | Screen backlight |
| `NetworkManager` (`nmcli`) | WiFi/Ethernet |
| `cliphist` + `wl-clipboard` | Clipboard, AnoSpot Copy-path action |
| `curl` | HTTP (weather, AI chat, AnoSpot LocalSend send) |
| `openssl` | Random fingerprint for AnoSpot LocalSend |
| `iproute2` (`ip`) | Network introspection for AnoSpot LocalSend discovery |
| `libnotify` | Notifications, AnoSpot LocalSend status messages |
| `python3` | Scripts (general + AnoSpot LocalSend discovery/send) |
| `xdg-utils` (`xdg-open`) | AnoSpot Open / Reveal actions |

Sway (1.12+), Mango (0.18) and labwc (0.20) sessions run on experimental backends; see [docs/compositors.md](docs/compositors.md). Sway needs `swaymsg` (part of sway); Mango and labwc need nothing extra (labwc users with a `<privilegedInterfaces>` block must allow the protocols listed there).

For the Niri session specifically, **niri ≥ 26.04** is required — `~/.config/niri/ano.kdl` uses the `background-effect { blur }` and window-rule `popups { … }` blocks introduced in 26.04 for visual parity with Hyprland-Ano.

### Recommended
`pyprland` (dropdown terminal, minimize, lost windows), `pywal` (terminal colors), `ddcutil` (external monitors), `cava` (spectrum), `zenity` (file picker — required for AnoSpot's "Move to…" action), `ydotool` (paste), `translate-shell` (translator), `wf-recorder` (screen recording — drives AnoSpot's recording widget), `xdg-desktop-portal-*` (one of `-gtk`/`-kde`/`-hyprland` — file open/screenshare integration; almost always already installed by the desktop)

### Optional
`ffmpeg`, `hyprpicker`, `qalc` (calculator), `grim`+`slurp` (screenshot), `wlsunset` (night light — works on any wlroots session), `localsend` (the GUI app — only needed on the **receiving** device for AnoSpot's LocalSend action; the sender side ships ready-to-use scripts in `scripts/anoSpot/`)

### AnoSpot dependency map
Each AnoSpot widget/action and the underlying tool that makes it work:

| Surface                  | Provided by                                                |
|--------------------------|------------------------------------------------------------|
| Mpris widget             | Mpris D-Bus (any modern player); `playerctl` recommended    |
| Notification widget      | `libnotify`-emitted notifications via the QS service       |
| Recording widget         | a recorder: `gpu-screen-recorder`, `wl-screenrec` or `wf-recorder`; `ffmpeg` (finish thumbnail), `gio` (Discard to trash), `pactl` (system + mic mix) |
| Battery widget           | UPower D-Bus (standard on every Linux desktop with a battery) |
| Workspace widget         | `CompositorService` → Hyprland or Niri IPC                 |
| Clock/Weather widget     | Built-in `DateTime` + `Weather` services                   |
| Click bindings           | QuickShell IPC (`qs -c ano ipc call …`); no external deps  |
| Drag handle              | Qt `MouseArea`; no external deps                           |
| Drop target              | QML `DropArea` (Wayland data-device protocol)              |
| Stash                    | bash + `cp`/`rm`/`stat`/`du`/`mkdir`/`ls` (coreutils)      |
| Action: LocalSend        | `bash`, `python3`, `curl`, `openssl`, `iproute2`           |
| Action: Open / Reveal    | `xdg-utils` (`xdg-open`)                                   |
| Action: Copy path        | `wl-clipboard` (`wl-copy`)                                 |
| Action: Move to…         | `zenity` (file picker) + coreutils `mv`                    |
| Action: Custom           | whatever your rule's `command` invokes                     |

If any dependency is missing, the corresponding action shows a `notify-send` failure message but the rest of AnoSpot keeps working.

### System integration dependency map
What each feature needs from the system (`ano doctor` checks the binaries):

| Feature | Needs | Without it |
|---------|-------|------------|
| Apps launched in their own unit (dock, launcher, default apps) | a systemd user manager (`systemd-run`, `systemctl`), else `setsid` (util-linux) | plain detached launch |
| Password prompt (polkit) | `polkit` (polkitd; `pkaction` for Details), `procps-ng` (`pgrep`, `ps`) for the pkexec command in Details; no other agent running (e.g. hyprpolkitagent) | another agent answers, Settings says so |
| Blur behind the polkit prompt (`polkit.blur`) | the bundled Hyprland/niri layer rules for `quickshell:polkit` / `quickshell:polkitPlain` | the compositor's own rules decide |
| Sensitive clipboard entries skipped | `wl-clipboard` (`wl-paste --watch`) + `cliphist` (verified with 0.7.0) | password-manager copies land in the history |
| Privacy: microphone, PipeWire cameras | PipeWire + WirePlumber | not shown |
| Privacy: cameras opened directly | anod running (inotify on `/dev/video*`, no packages) | only PipeWire cameras shown |
| Privacy: screen sharing | Hyprland (screencast events); portal casts via `xdg-desktop-portal` + `-hyprland` (or `-gnome` on niri) and PipeWire | not shown (a browser sharing its own tab is never visible to the desktop) |
| Long-running helpers (`nmcli monitor`, `wlsunset`, `cava`, `udevadm monitor`) | `setpriv` (util-linux): started with `--pdeathsig TERM` so they end with the shell, even a killed one | the helper fails to start |
| Removable drives (bar module `drives`) | `udisks2` (`udisksctl`), `util-linux` (`lsblk` ≥ 2.37 for `MOUNTPOINTS`), udev (`udevadm`: systemd-udev or eudev), `libnotify` (`notify-send`) | no drives listed / no notifications |
| Night light (Settings → Services, bar/pill module `nightlight`, sidebar toggle) | `wlsunset`; a compositor with wlr-gamma-control (Hyprland, niri, sway) | the toggle does nothing |
| Qt apps in the palette (`appearance.theme.qt`) | `qt6ct` (and `QT_QPA_PLATFORMTHEME=qt6ct`); `qt5ct` for Qt 5 apps; `kvantum` for the default Kvantum mode | Qt apps keep Qt's default look |
| Downloads (bar/pill module `downloads`) | anod running (inotify on the download folder from `user-dirs.dirs`, else `~/Downloads`); `xdg-utils` (`xdg-open`) to open | not shown |
| Keyboard layout catalogue (Settings → Keybinds) | `xkeyboard-config` (`/usr/share/X11/xkb/rules/evdev.xml`), anod running | no catalogue to pick from |
| Bioma organisms (pieces `bioma-*`) | `qt6-5compat` (Qt5Compat.GraphicalEffects); weather and photoperiod: `curl` and Open-Meteo (`geocoding-api.open-meteo.com`, `api.open-meteo.com`, no key); media band: `cava` and an MPRIS player; disks: `df`; system organisms: `/proc`, `/sys`, `upowerd` for the battery, `pgrep`/`awk`/`sed`/`xargs` for cytoplasm; recent files: `~/.local/share/recently-used.xbel`; rings: `stat`, ext-idle-notify | the organism shows why it's empty |
| Location (Settings → Services → Location: weather, night light's sunset schedule, the Bioma pieces' sun and moon) | automatic: `geoclue` (the GeoClue 2 service, Wi-Fi/GPS) and `qt6-positioning` (its geoclue2 plugin); fallback and city name: `curl` to `ip-api.com` (sends your IP address, city-level); manual: nothing | weather falls back to its city setting or wttr.in's guess; the sunset schedule waits |
| Music recognition (`musicRecognition.enable`) | `songrec` (uses Shazam's unofficial service), `pipewire` (`pw-record`), `libnotify` (`notify-send` ≥ 0.7.10 for the Copy/Search actions), `wl-clipboard` | "Not recognised: songrec gave no answer" |
| Device event pills (`deviceEvents`) | BlueZ (Bluetooth), PipeWire (audio output), udev's `udevadm` (USB; systemd-udev or eudev) | that kind of event isn't shown |
| Caps Lock / Num Lock OSD, lock screen Caps Lock warning | Hyprland: the bundled `Caps_Lock`/`Num_Lock` binds (non-consuming) and `hyprctl` (reads the main keyboard, so keyd and other virtual keyboards are fine); elsewhere: keyboard LEDs in `/sys/class/leds` (read only while locked; bind a key to `qs ipc call lockKeys refresh` for the OSD) | no lock-key OSD; no warning |
| Package updates (`updates.enable`, bar module `updates`) | `pacman-contrib` (`checkupdates`); `paru` or `yay` for AUR counts; a terminal (Settings → Default apps) to run the update | no count / AUR not counted |
| Atelier (Settings → Atelier, `ano atelier`) | anod running (downloads, checksums and archives in Go, no extra binaries); catalogs need the network | the page says anod isn't running; catalogs show the cached index |
| News piece (`news`) | `curl` to `news.google.com` (RSS, no key; local news sends the place you set); source icons: Google's favicon service (`www.google.com/s2/favicons`, sends only the source's site; off with the widget's "Source icons" setting) | the widget says it couldn't reach Google News; no icons |
| Clock | the system clock; keep it synchronised (`systemd-timesyncd`: `sudo timedatectl set-ntp true`, or chrony) — `ano doctor` warns when it isn't | the clock drifts |
| EasyEffects quick toggle and presets (`audio.easyEffects.enable`) | `easyeffects` ≥ 7 running (its CLI: `-b`, `--bypass-toggle`, `-p`, `-l`); the shell never starts it | the pill stays hidden |
| Game mode indicator, performance mode during games | `gamemode` (gamemoded; games run with `gamemoderun` or libgamemode), `glib2` (`gdbus`) | performance mode only by hand or for fullscreen windows |
| Palette cursors and icons | `librsvg` (`rsvg-convert`), `imagemagick` (`magick`) | the palette themes can't be built |
| Lock screen (niri; `lock.enable`, `lock.screen`) | `pam` with `/etc/pam.d/login` (the password check, faillock included); a compositor with ext-session-lock-v1; `glib2` (`gdbus`) to lock on `loginctl lock-session` | Super+L and `qs ipc call lock lock` still lock; `loginctl lock-session` (session menu, idle tools) doesn't |
| KDE Connect (`kdeConnect.enable`, off by default; bar module "Phone") | `kdeconnect` with `kdeconnectd` running (the shell doesn't start it; the bundled Hyprland/niri configs do), `systemd` (`busctl`), `glib2` (`gdbus`), `util-linux` (`setpriv`); sending a file: `zenity` | no pill and no phone actions; a hung kdeconnectd shows as not answering |
| Fingerprint unlock (niri lock; `lock.fingerprint.enable`, off by default) | `fprintd` (`fprintd-list`, `pam_fprintd.so`) and at least one enrolled print (`fprintd-enroll`); the shell's own `modules/lock/pam/fprint` service, no faillock | password only |
| Launcher plugins (`search.userPlugins`; bundled `clipboard`) | nothing for the loader; the bundled clipboard plugin needs `cliphist` | the plugin shows nothing |
| Frame jelly (`appearance.connectedCorners.jelly`) | nothing (a spring in the frame shader) | — |

Tested on Quickshell 0.3.2 (Qt 6.11), Hyprland (Lua config) and polkit with pam_faillock.

### Color Pipeline
```
Wallpaper → awww (apply) → matugen (Material You → colors.json) → MaterialThemeLoader
                         → pywal (terminal colors + cava gradients)
                         → gtk.css block (anod, GTK 3/4 + libadwaita; appearance.theme.gtk)
                         → applycolor.sh (kitty/ghostty/foot/Qt)
Wallpapers are applied by anod: `ano wallpaper set IMAGE` (awww, matugen colours, then `background.hooks`).
```

## Widget Library (50+ components)
**Foundation**: StyledText, MaterialSymbol, Circle, PointingHandInteraction, FadeLoader, Revealer, StyledImage, WavyLine, DragManager, RoundCorner
**Controls**: RippleButton, StyledSlider, StyledSwitch, StyledProgressBar, CircularProgress, CombinedCircularProgress, Graph, StyledScrollBar, StyledFlickable, Tooltips, StyledTextInput/Area
**Composite**: ToolbarButton, Toolbar, GroupButton, ButtonGroup, ConfigRow/Switch/Slider, ConfigTextInput (placeholder + validator + inline errors), ChoiceRow (single-select icon-row picker), RestartRequiredBadge (clickable reload-now pill), ContentSection, NoticeBox, KeyboardKey, CalendarView, NotificationItem, StyledBlurEffect, StyledDropShadow, ScrollEdgeFade, StyledPopup, SettingsCard (with `configKeys` for command-palette resolution), SettingsPageHeader (per-page reset), SettingsCommandPalette (Ctrl+K dynamic-search overlay)
**Animation**: Anim, CAnim, AbstractChoreographable, FlyFadeEnterChoreographable, ChoreographerLayout
**Morph**: ShapeCanvas, MorphedPanel, TopLayerPanel, BarWidgetPopout, BarModulePopout (16 JS shape files)
**Spectrum**: LinearSpectrum, MirroredSpectrum

## Morphing Panel System (from hefty-hype)
Set `morphingPanel: true` on any bar in `bars[]` to use polygon-based ShapeCanvas backgrounds that morph between states. The `BarModulePopout` wrapper auto-detects morph mode — 8 bar modules have rich morph-capable popouts.

## Credits
Built from: **@rebels** (base), **@hyprview** (layouts), **@inir** (Niri/dock/alt-switcher/translator), **@ilyamiro** (FocusTime/display manager/Network Orbit/widget designs), **@caelestia** (animations/HUD), **@noctalia-shell** (spectrum/settings), **@end-4** (AI chat/anti-flashbang/systray menus), **@end-4 hefty-hype** (polygon morphing system), **wallpaperpicker** (wallpaper card deck, spectrum ribbon, Wallhaven source)
**Bioma** (GPL-3.0: palette cursors and icon themes, the desktop "organisms" in `pieces/bioma-*` with their support code in `pieces/_bioma`, downloads, ideas throughout), **novelmangareader** (GPL-3.0: the reader).

## Licence

GPL-3.0 (`LICENSE`), as the ported Bioma and novelmangareader code requires.

## Architecture

<details>
<summary>Source tree (click to expand)</summary>

```
ano/
├── shell.qml                       # Entry point — panel-family loader, IPC handlers
├── settings.qml                    # Standalone Settings window (FloatingWindow)
├── GlobalStates.qml                # All panel/overlay open/close states
├── config.json                     # Bundled defaults (read-only at runtime)
│
├── modules/
│   ├── common/                     # Singletons + reusable widgets
│   │   ├── Config.qml              # JSON config R/W; user delta lives at ~/.config/anoshell/config.json
│   │   ├── Appearance.qml          # MD3 colors, glass tokens, fonts, animation curves, previewTokens
│   │   ├── Directories.qml         # XDG paths, theme paths, user-config path
│   │   ├── AnimationConfig.qml     # Animation presets
│   │   ├── FamilyTransitionOverlay.qml
│   │   ├── functions/              # ColorUtils, DateUtils, FileUtils, Format (formatDuration), ObjectUtils, StringUtils
│   │   └── widgets/                # 50+ reusable widgets (see Widget Library)
│   │       ├── shapes/             # Polygon morph system (16 JS + 1 QML from hefty-hype)
│   │       └── spectrum/           # LinearSpectrum, MirroredSpectrum (cava)
│   │
│   ├── bar/                        # Multi-bar system
│   │   ├── BarManager.qml          # Creates N bars per monitor, respects morphingPanel
│   │   ├── BarWindow.qml           # PanelWindow on any edge
│   │   ├── BarContent.qml          # Spacing/padding/click/scroll actions
│   │   ├── BarGroup.qml            # Rounded pill container
│   │   └── modules/                # 17 bar modules (see Bar Modules list)
│   │
│   ├── overview/                   # AnoView with 11 layout algorithms
│   ├── taskView/                   # Current-workspace window view
│   ├── altSwitcher/                # Alt-Tab switcher with thumbnails
│   ├── search/                     # App launcher + calculator
│   ├── sidebarLeft/                # AI Chat | Notifications | Translator
│   ├── sidebarRight/               # Configurable widget stack (see Sidebar Right widgets)
│   ├── controlPanel/               # Floating notification-shade
│   ├── settings/                   # 10-page settings system + SettingsKeyHandler + SettingsPageHeader + SettingsCommandPalette (Ctrl+K) + SettingsRegistry (dynamic search index)
│   ├── osd/                        # 6-indicator on-screen display
│   ├── hud/                        # Heads-up display
│   ├── session/                    # Power menu: actions around the avatar, press twice to confirm
│   ├── dock/                       # Pill / macOS application dock
│   ├── clipboard/                  # cliphist browser
│   ├── mediaControls/              # Full media player with vinyl art + lyrics
│   ├── weather/                    # Detailed weather panel
│   ├── notifications/              # Notification list component
│   ├── notificationPopup/          # Floating popup notifications
│   ├── cheatsheet/                 # Searchable keybinds viewer
│   ├── wallpaperSelector/          # Wallpaper card deck (local / favourites / Wallhaven)
│   ├── lock/                       # Niri lock screen + opt-in notifications/OSK/status row
│   ├── focusTime/                  # App-usage tracker UI
│   ├── displayManager/             # Hyprland-only monitor config
│   ├── screenCorners/              # Hot corners
│   ├── recordingOsd/               # Live screen-recording overlay
│   ├── calendar/                   # Standalone calendar with event dots
│   └── anoSpot/                    # Dynamic-island pill + drag/drop stash + workspace hover-preview
│
├── services/                       # 42 service singletons (see Services section)
│
├── assets/themes/                  # 24 bundled static themes
├── layouts/                        # 11 overview layout algorithms
│
├── scripts/
│   ├── colors/applycolor.sh                # app colours (an anod wallpaper hook)
│   ├── hyprland/get_keybinds.py
│   ├── anoSpot/                    # LocalSend send/discover scripts
│   └── focustime/{focus_daemon,get_stats}.py
│
├── plugins/                        # C++ extension point placeholder
├── external/                       # Symlinked Niri/Hyprland-Ano configs
└── translations/                   # Future content
```

</details>
