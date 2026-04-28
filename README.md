# Ano Shell

A comprehensive QuickShell (v0.2.1+) desktop shell for Wayland compositors.
Supports **Hyprland** and **Niri** with runtime auto-detection.

**218+ QML files • 30,000+ lines • 28 modules • 41 services • 30+ IPC targets • 10 settings pages • 4 panel families • 24 bundled themes**

## Quick Start

```bash
# Launch with QuickShell
qs -c ano

# Launch standalone settings
qs -n -p ~/.config/quickshell/ano/settings.qml

# Or from Hyprland companion config (auto-launches)
# Source ~/.config/hypr/Ano/hyprland.conf
```

## Architecture

```
ano/
├── shell.qml                       # Entry point — 25 LazyLoaders, panel families
├── settings.qml                    # Standalone settings window
├── GlobalStates.qml                # All panel/overlay open/close states
├── config.json                     # User configuration (30+ sections)
│
├── modules/
│   ├── common/                     # 63 files
│   │   ├── Config.qml              # Singleton — JSON config R/W with setNestedValue
│   │   ├── Appearance.qml          # Singleton — MD3 theme, colors, fonts, curves
│   │   ├── Directories.qml         # Singleton — XDG paths, user avatar
│   │   ├── AnimationConfig.qml     # Singleton — animation presets
│   │   ├── FamilyTransitionOverlay.qml  # Panel family switch ripple animation
│   │   ├── functions/              # 5 utility singletons (Color, File, String, Date, Object)
│   │   └── widgets/                # 50+ reusable widgets (see below)
│   │       ├── shapes/             # Polygon morph system (16 JS + 1 QML from hefty-hype)
│   │       └── spectrum/           # LinearSpectrum, MirroredSpectrum (cava)
│   │
│   ├── bar/                        # 19 files — multi-bar system
│   │   ├── BarManager.qml          # Creates N bars per monitor, respects morphingPanel flag
│   │   ├── BarWindow.qml           # PanelWindow on any edge, per-bar height/radius
│   │   ├── BarContent.qml          # Configurable spacing/padding/click/scroll actions
│   │   ├── BarGroup.qml            # Rounded pill container
│   │   └── modules/                # 17 bar modules (8 with morph-capable popouts)
│   │       ├── BarModuleLoader.qml # Singleton mapper
│   │       ├── ClockModule.qml     # 🕐 Popout: calendar, uptime, weather
│   │       ├── WorkspacesModule.qml# Workspace dots (Hyprland + Niri)
│   │       ├── BatteryModule.qml   # 🔋 Popout: gauge, health, power rate, time
│   │       ├── NetworkModule.qml   # 📶 Popout: signal, speed, WiFi toggle
│   │       ├── BluetoothModule.qml # 🔵 Popout: device list
│   │       ├── TrayModule.qml      # System tray with DBus menus + pin/unpin
│   │       ├── SysTrayMenu.qml    # StackView menu with submenu navigation
│   │       ├── SysTrayMenuEntry.qml # Menu entry (labels, icons, checkboxes, submenus)
│   │       ├── MediaModule.qml     # 🎵 Popout: art, controls, spectrum
│   │       ├── ResourcesModule.qml # 📊 Popout: gauges, CPU graph, details
│   │       ├── WeatherModule.qml   # 🌡️ Popout: temp, stats, sun times
│   │       ├── NotificationsModule.qml # 🔔 Popout: recent notifications
│   │       ├── ActiveWindowModule.qml  # Window title
│   │       ├── SidebarButtonModule.qml # Toggle pill
│   │       ├── KeyboardModule.qml  # XKB layout + click-to-cycle (Niri)
│   │       ├── PrivacyModule.qml   # Mic-active indicator (zero-width when idle)
│   │       ├── GameModeModule.qml  # GameMode-active indicator
│   │       └── IdleModule.qml      # Coffee cup toggle
│   │
│   ├── overview/                   # AnoView — 10 layout algorithms
│   │   ├── AnoView.qml            # Compositor-agnostic window overview
│   │   ├── WindowThumbnail.qml    # ScreencopyView with hover/click
│   │   └── SearchBox.qml          # Type-to-filter
│   │
│   ├── taskView/                   # Separate from overview
│   │   └── TaskView.qml           # Current workspace windows + workspace strip
│   │
│   ├── altSwitcher/                # Alt-Tab window switcher
│   │   └── AltSwitcher.qml        # Thumbnails, MRU, search, keyboard nav
│   │
│   ├── search/                     # App launcher
│   │   └── Search.qml             # DesktopEntries search, recent apps, calculator
│   │
│   ├── sidebarLeft/                # 8 files — 3 tabs: AI Chat | Notifications | Translator
│   │   ├── SidebarLeft.qml        # PanelWindow shell
│   │   ├── SidebarLeftContent.qml  # Tabbed container
│   │   ├── AiChat.qml             # AI chat (OpenAI/Gemini/Anthropic/Mistral/Ollama)
│   │   ├── Translator.qml         # trans CLI + AI fallback, 12 languages
│   │   └── aiChat/                 # Message rendering (3 files)
│   │
│   ├── sidebarRight/               # 8 files — configurable widget stack
│   │   ├── SidebarRight.qml       # PanelWindow shell
│   │   ├── SidebarRightContent.qml # enabledWidgets array
│   │   ├── QuickSliders.qml       # Volume / Brightness / Mic
│   │   ├── QuickToggles.qml       # WiFi / Hotspot / BT / DND / Idle / NightLight pills (chevron-expandable temp slider)
│   │   ├── NetworkDetailPanel.qml  # rx/tx bandwidth + VPN toggle (auto-hides when both dormant)
│   │   ├── CompactMediaPlayer.qml  # Vinyl art + controls
│   │   ├── NotificationCenter.qml  # Recent notifications
│   │   └── SystemInfoPanel.qml    # CPU/RAM/Battery gauges + net speed
│   │
│   ├── controlPanel/               # Floating notification-shade
│   │   └── ControlPanel.qml       # Toggles, sliders, media, gauges, power
│   │
│   ├── settings/                   # 12 files — 10-page settings system
│   │   ├── SettingsOverlay.qml    # Floating overlay (10 nav pages)
│   │   ├── SettingsCard.qml       # Collapsible card component
│   │   ├── GeneralConfig.qml      # Audio, battery, time, notifications, scrolling
│   │   ├── ModulesConfig.qml      # Module enable/disable, OSD, corners, alt-tab, apps
│   │   ├── BarConfig.qml          # Edge, layout, spacing, actions, weather, tray
│   │   ├── DockConfig.qml         # Position, style, sizing, behavior, pinned apps
│   │   ├── SidebarsConfig.qml     # Behavior, widget toggles, sliders
│   │   ├── AppearanceConfig.qml   # Theme source picker, dynamic/static themes, bezel, animations, wallpaper rotation
│   │   ├── OverviewConfig.qml     # Layout selector (11 cards)
│   │   ├── AnoSpotConfig.qml      # Position, widgets, click bindings, event border, drag/drop, custom drop actions
│   │   ├── ServicesConfig.qml     # AI, GameMode, PowerProfiles, NetworkUsage, Hotspot, VPN, NightLight, Lyrics, CalendarSync, Resources, Brightness
│   │   └── AboutPage.qml         # User profile (avatar picker), system info, credits
│   │
│   ├── osd/                        # On-screen display (6 indicators)
│   │   └── OSD.qml               # Volume/brightness/mic/media/keyboard/network
│   │
│   ├── hud/                        # Heads-up display
│   │   └── HUD.qml               # Clock, gauges, network, spectrum, media, uptime
│   │
│   ├── session/                    # Power screen
│   │   └── SessionScreen.qml     # Hold-to-confirm: lock/logout/sleep/reboot/shutdown
│   │
│   ├── dock/                       # Application dock
│   │   └── Dock.qml              # Pill + macOS styles, 4-edge, pinned+running apps
│   │
│   ├── clipboard/                  # Clipboard manager
│   │   └── ClipboardManager.qml  # Search, paste, copy, delete, superpaste
│   │
│   ├── mediaControls/              # Full media player
│   │   └── MediaControls.qml     # Vinyl art, spectrum, controls, volume, player switch
│   │
│   ├── weather/                    # Detailed weather panel
│   │   └── WeatherPanel.qml      # Hero temp, 6 stats, sunrise/sunset
│   │
│   ├── notifications/              # Notification display component
│   │   └── NotificationDisplay.qml # Grouped, reusable, configurable
│   │
│   ├── notificationPopup/          # Floating notification popups
│   │   └── NotificationPopup.qml  # Stagger entry, swipe dismiss
│   │
│   ├── cheatsheet/                 # Keybind viewer
│   │   └── Cheatsheet.qml        # Searchable, collapsible, Hyprland+Niri
│   │
│   ├── wallpaperSelector/          # Wallpaper browser
│   │   └── WallpaperSelector.qml  # Grid, directory nav, rotation status
│   │
│   ├── lock/                       # Lock screen (Niri only — Hyprland uses hyprlock)
│   │   ├── LockScreen.qml         # PAM auth, clock, avatar, password (expand-on-focus, idle dim)
│   │   ├── LockNotifications.qml  # Optional notification mirror while locked
│   │   ├── LockOSK.qml            # Optional 4-row QWERTY on-screen keyboard
│   │   └── LockStatusRow.qml      # Optional battery + wifi + clock chips
│   │
│   ├── focusTime/                  # App usage tracker (from ilyamiro)
│   │   ├── FocusTimePanel.qml    # PanelWindow wrapper with IPC
│   │   └── FocusTimeContent.qml  # Daily/weekly/monthly stats, heatmaps, app drill-down
│   │
│   ├── displayManager/             # Monitor config (from ilyamiro, Hyprland-only)
│   │   ├── DisplayManager.qml    # PanelWindow wrapper with IPC
│   │   └── DisplayManagerContent.qml # Visual layout, resolution grid, refresh slider
│   │
│   ├── screenCorners/              # Hot corners
│   │   └── ScreenCorners.qml      # 4 configurable corner triggers
│   │
│   ├── recordingOsd/               # Live screen-recording overlay
│   │   └── RecordingOsd.qml       # wf-recorder elapsed + stop button
│   │
│   ├── calendar/                   # Standalone calendar overlay
│   │   └── CalendarPanel.qml      # Month grid + event dots + upcoming events
│   │
│   └── anoSpot/                    # Dynamic-island pill (10 files)
│       ├── AnoSpot.qml            # Pill orchestrator (drag handle, drop area, event border)
│       ├── AnoSpotMpris.qml       # Now-playing + lyrics swap + scroll-to-volume
│       ├── AnoSpotNotification.qml # Toast slot
│       ├── AnoSpotRecording.qml   # Recording indicator
│       ├── AnoSpotClockWeather.qml # Compact time + temperature
│       ├── AnoSpotWorkspace.qml   # Workspace indicator + hover-preview trigger
│       ├── AnoSpotWorkspacePreview.qml # Hover-popup with live ScreencopyView thumbnails
│       ├── AnoSpotBattery.qml     # 8-tier battery glyph
│       ├── AnoSpotStashPopout.qml # Drag-and-drop stash with custom action toolbar
│       └── AnoSpotEventBorder.qml # Animated gradient halo
│
├── services/                       # 41 service singletons
│   ├── CompositorService.qml      # Auto-detect Hyprland/Niri, activeWorkspaceIndex/Name abstraction
│   ├── NiriService.qml            # Full Niri IPC via socket
│   ├── HyprlandData.qml           # hyprctl JSON
│   ├── HyprlandKeybinds.qml       # Hyprland keybind parser
│   ├── NiriKeybinds.qml           # Niri KDL config parser
│   ├── AnoSocket.qml              # Reconnecting socket wrapper
│   ├── Ai.qml                     # AI chat (6+ providers, streaming, Anthropic thinking)
│   ├── Audio.qml                  # PipeWire volume + protection
│   ├── Battery.qml                # UPower + auto-suspend
│   ├── BluetoothStatus.qml        # Device lists
│   ├── Brightness.qml             # brightnessctl + DDC/CI
│   ├── Cliphist.qml               # Clipboard history
│   ├── DateTime.qml               # Clock + uptime
│   ├── Idle.qml                   # Wayland IdleInhibitor
│   ├── IdleInhibitor.qml          # Per-app inhibit registry
│   ├── KeyboardLayoutService.qml  # XKB (Hyprland + Niri) + click-to-cycle
│   ├── MaterialThemeLoader.qml    # Wallpaper → MD3 colors (dynamic mode)
│   ├── StaticThemeLoader.qml      # JSON → MD3 colors (static mode)
│   ├── ThemeRegistry.qml          # Lists bundled + user themes
│   ├── MprisController.qml        # Media player tracking
│   ├── LyricsService.qml          # Synced lyric .lrc parser + position polling
│   ├── Network.qml                # nmcli WiFi/Ethernet + hotspot toggle
│   ├── NetworkUsage.qml           # /proc/net/dev rx/tx polling (opt-in)
│   ├── VPN.qml                    # tailscale/netbird/warp/wireguard/custom (opt-in)
│   ├── NightLight.qml             # wlsunset wrapper (opt-in)
│   ├── Notifications.qml          # Persistent notification center
│   ├── Privacy.qml                # Mic-active/cam-active detection
│   ├── GameMode.qml               # Fullscreen-app detection
│   ├── PowerProfilePersistence.qml # power-profiles-daemon restore-on-start
│   ├── RecorderStatus.qml         # wf-recorder process detection
│   ├── ResourceUsage.qml          # CPU/RAM/swap/network from /proc
│   ├── SpectrumService.qml        # Cava audio spectrum (reference counted)
│   ├── TrayService.qml            # System tray with pinning + DBus menu support
│   ├── FocusTime.qml              # App usage tracker daemon lifecycle
│   ├── AntiFlashbang.qml          # GLSL shader to darken bright screens (Hyprland)
│   ├── CalendarSync.qml           # iCal/CalDAV pull (opt-in)
│   ├── MinimizedWindows.qml       # Niri minimize-emulation registry
│   ├── ShellExec.qml              # Convenience exec wrapper
│   ├── AnoSpotState.qml           # Shared AnoSpot widget state
│   ├── AnoSpotStash.qml           # Drag-and-drop stash directory manager
│   ├── Wallpapers.qml             # Directory browsing + auto-rotation
│   └── Weather.qml                # wttr.in + GPS
│
├── panelFamilies/                  # 4 layout presets + PanelLoader
│   ├── PanelLoader.qml            # LazyLoader gated by Config.ready + extra condition
│   ├── AnoFamily.qml              # Default — everything enabled
│   ├── HeftyFamily.qml            # Morphing bar panels (polygon ShapeCanvas)
│   ├── CleanFamily.qml            # Bar + sidebars + essentials only
│   └── MinimalFamily.qml          # Bar + bare overlays
│
├── assets/themes/                  # 24 bundled static themes (dark + light variants)
│   └── *.json                     # ayu, catppuccin, dracula, eldritch, gruvbox, kanagawa,
│                                  # noctalia-default, nord, rosepine, tokyo-night,
│                                  # angel, aurora, inir
│
├── layouts/                        # 10 overview layout algorithms + manager
│
├── scripts/
│   ├── colors/switchwall.sh       # awww + matugen + pywal (with backup/restore)
│   ├── colors/applycolor.sh       # Apply colors to kitty/ghostty/foot/cava
│   ├── hyprland/get_keybinds.py   # Keybind config parser
│   ├── anoSpot/                   # LocalSend send/discover scripts
│   └── focustime/                 # App usage tracking daemon
│       ├── focus_daemon.py        # Background daemon (Hyprland + Niri, SQLite)
│       └── get_stats.py           # Historical query script (week/month/hourly)
│
├── plugins/                        # C++ extension point placeholder
├── external/                       # Symlinked Niri/Hyprland-Ano configs
└── translations/                   # Future content
```

## Configuration

All settings in `config.json`. GUI via Settings overlay (`qs -c ano ipc call settings toggle`) or standalone window (`qs -n -p settings.qml`).

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
Switch entire layout presets atomically. Each family loads a different combination of panels via `panelFamilies/*.qml`:

| Family   | Includes                                                                  | Best for                          |
|----------|---------------------------------------------------------------------------|-----------------------------------|
| `ano`    | Bar + Dock + both Sidebars + HUD + AI + Overview + everything             | Default daily driver              |
| `hefty`  | Same as `ano`, plus morphing polygon bar panels                           | Maximalist visual                 |
| `clean`  | Bar + Sidebars + essentials. No dock, no hot corners, no HUD              | Focused work                      |
| `minimal`| Bar + bare overlays only. No sidebars, no dock, no HUD                    | Lightweight / external launchers  |

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
- **`static`** — `StaticThemeLoader` reads `assets/themes/<name>.json` (or user override `~/.config/ano/themes/<name>.json`). 24 themes ship in the bundle (dark + light variants of Catppuccin, Dracula, Nord, Tokyo Night, Gruvbox, Kanagawa, Rosé Pine, Ayu, Eldritch, Noctalia, Inir, plus Angel and Aurora).

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
| `gameMode.enable` | Auto-detect fullscreen apps and dim distractions | `pollIntervalMs` |
| `powerProfiles.restoreOnStart` | Restore last `power-profiles-daemon` profile on shell start | `preferredProfile` (auto-populated when you change profiles) |
| `network.usage` | Per-interface rx/tx polling for the sidebar bandwidth panel | `intervalMs`, `historyLength` |
| `network.hotspot` | WiFi tethering toggle backed by `nmcli device wifi hotspot` | `ssid`, `password` (auto-generated on first enable) |
| `vpn` | Generic VPN status + connect/disconnect for tailscale/netbird/warp/wireguard/custom | `providers[]`, `notifyOnChange` |
| `calendar` | KHal/CalDAV pull into the calendar panel | `upcomingDays`, `externalSync.{enable, refreshMinutes, sources[]}` |
| `lyrics` | Synced lyric overlay in MediaControls + AnoSpot | `enable`, `backend`, `dir` |
| `nightLight` | wlsunset-backed warm-shift, works on any wlroots compositor | `mode` (manual/schedule), `dayTemp`, `nightTemp`, `latitude`, `longitude` |
| `lock.notifications` | Mirror notifications onto the lock screen | `maxItems` |
| `lock.osk` | On-screen keyboard for password entry | — |
| `lock.statusRow` | Battery + WiFi + clock chips on the lock screen | — |
| `lock.dim` | Auto-dim the lock background after idle | `idleMs`, `opacity` |
| `lock.passwordInput.expandOnFocus` | Animate the password field on focus | — |
| `anoSpot.showLyrics` | Swap track title for the current lyric line | requires `lyrics.enable` |
| `anoSpot.workspaceHoverPreview` | Hover the workspace pill to see live thumbnails | `openDelayMs`, `closeDelayMs`, `thumbnailWidth`, `thumbnailHeight` |
| `appearance.theme` | Switch between dynamic Material You and bundled static themes | `source` (`materialYou`/`static`), `static` (theme name) |

`appearance.theme.source = "static"` activates the StaticThemeLoader, which reads `assets/themes/<name>.json` (or `~/.config/ano/themes/<name>.json` to override). 24 themes ship in the bundle (Catppuccin, Dracula, Nord, Tokyo Night, Gruvbox, Kanagawa, Rosé Pine, Ayu, Eldritch, Noctalia, Aurora, Inir, Angel — most with dark/light variants).

### Module Enable/Disable
Every module is toggleable via the `enabledPanels` array or the Modules settings page.

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
| `idle` / `idleInhibitor` | `toggle`, `enable`, `disable` / per-app inhibit registry |
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
| `quickshell` ≥0.2.1 | Shell framework |
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
| Recording widget         | `wf-recorder` (detected by polling `pgrep -x wf-recorder`)  |
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

### Color Pipeline
```
Wallpaper → awww (apply) → matugen (Material You → colors.json) → MaterialThemeLoader
                         → pywal (terminal colors + cava gradients)
                         → applycolor.sh (kitty/ghostty/foot/GTK)
Scripts include automatic backup — restore with: switchwall.sh --restore
```

## Widget Library (50+ components)
**Foundation**: StyledText, MaterialSymbol, Circle, PointingHandInteraction, FadeLoader, Revealer, StyledImage, WavyLine, DragManager, RoundCorner
**Controls**: RippleButton, StyledSlider, StyledSwitch, StyledProgressBar, CircularProgress, CombinedCircularProgress, Graph, StyledScrollBar, StyledFlickable, Tooltips, StyledTextInput/Area
**Composite**: ToolbarButton, Toolbar, GroupButton, ButtonGroup, ConfigRow/Switch/Slider, ContentSection, NoticeBox, KeyboardKey, CalendarView, NotificationItem, StyledBlurEffect, StyledDropShadow, ScrollEdgeFade, StyledPopup, SettingsCard
**Animation**: Anim, CAnim, AbstractChoreographable, FlyFadeEnterChoreographable, ChoreographerLayout
**Morph**: ShapeCanvas, MorphedPanel, TopLayerPanel, BarWidgetPopout, BarModulePopout (16 JS shape files)
**Spectrum**: LinearSpectrum, MirroredSpectrum

## Morphing Panel System (from hefty-hype)
Set `morphingPanel: true` on any bar in `bars[]` to use polygon-based ShapeCanvas backgrounds that morph between states. The `BarModulePopout` wrapper auto-detects morph mode — 8 bar modules have rich morph-capable popouts.

## Credits
Built from: **@rebels** (base), **@hyprview** (layouts), **@inir** (Niri/dock/alt-switcher/translator), **@ilyamiro** (FocusTime/display manager/widget designs), **@caelestia** (animations/HUD), **@noctalia-shell** (spectrum/settings), **@end-4** (AI chat/anti-flashbang/systray menus), **@end-4 hefty-hype** (polygon morphing system)
