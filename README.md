# Ano Shell

A comprehensive QuickShell (v0.2.1+) desktop shell for Wayland compositors.
Supports **Hyprland** and **Niri** with runtime auto-detection.

**175+ QML files • 22,000+ lines • 26 modules • 30+ IPC targets • 10 settings pages**

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
│   │   └── modules/                # 15 bar modules (8 with morph-capable popouts)
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
│   │       ├── KeyboardModule.qml  # XKB layout indicator
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
│   ├── sidebarRight/               # 7 files — configurable widget stack
│   │   ├── SidebarRight.qml       # PanelWindow shell
│   │   ├── SidebarRightContent.qml # enabledWidgets array
│   │   ├── QuickSliders.qml       # Volume / Brightness / Mic
│   │   ├── QuickToggles.qml       # WiFi / BT / DND / Idle pills
│   │   ├── CompactMediaPlayer.qml  # Vinyl art + controls
│   │   ├── NotificationCenter.qml  # Recent notifications
│   │   └── SystemInfoPanel.qml    # CPU/RAM/Battery gauges + net speed
│   │
│   ├── controlPanel/               # Floating notification-shade
│   │   └── ControlPanel.qml       # Toggles, sliders, media, gauges, power
│   │
│   ├── settings/                   # 11 files — 9-page settings system
│   │   ├── SettingsOverlay.qml    # Floating overlay (9 nav pages)
│   │   ├── SettingsCard.qml       # Collapsible card component
│   │   ├── GeneralConfig.qml      # Audio, battery, time, notifications, scrolling
│   │   ├── ModulesConfig.qml      # Module enable/disable, OSD, corners, alt-tab, apps
│   │   ├── BarConfig.qml          # Edge, layout, spacing, actions, weather, tray
│   │   ├── DockConfig.qml         # Position, style, sizing, behavior, pinned apps
│   │   ├── SidebarsConfig.qml     # Behavior, widget toggles, sliders
│   │   ├── AppearanceConfig.qml   # Colors, bezel, animations, wallpaper rotation
│   │   ├── OverviewConfig.qml     # Layout selector (11 cards)
│   │   ├── ServicesConfig.qml     # AI models, resources, brightness
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
│   ├── lock/                       # Lock screen (Niri only)
│   │   └── LockScreen.qml        # PAM auth, clock, avatar, password
│   │
│   ├── focusTime/                  # App usage tracker (from ilyamiro)
│   │   ├── FocusTimePanel.qml    # PanelWindow wrapper with IPC
│   │   └── FocusTimeContent.qml  # Daily/weekly/monthly stats, heatmaps, app drill-down
│   │
│   ├── displayManager/             # Monitor config (from ilyamiro, Hyprland-only)
│   │   ├── DisplayManager.qml    # PanelWindow wrapper with IPC
│   │   └── DisplayManagerContent.qml # Visual layout, resolution grid, refresh slider
│   │
│   └── screenCorners/              # Hot corners
│       └── ScreenCorners.qml      # 4 configurable corner triggers
│
├── services/                       # 24 service singletons
│   ├── CompositorService.qml      # Auto-detect Hyprland/Niri
│   ├── NiriService.qml            # Full Niri IPC via socket (1321 lines)
│   ├── AnoSocket.qml              # Reconnecting socket wrapper
│   ├── Ai.qml                     # AI chat (6+ providers, streaming, Anthropic thinking)
│   ├── Audio.qml                  # PipeWire volume + protection
│   ├── Battery.qml                # UPower + auto-suspend
│   ├── BluetoothStatus.qml       # Device lists
│   ├── Brightness.qml            # brightnessctl + DDC/CI
│   ├── Cliphist.qml              # Clipboard history
│   ├── DateTime.qml              # Clock + uptime
│   ├── HyprlandData.qml          # hyprctl JSON
│   ├── HyprlandKeybinds.qml      # Keybind parser
│   ├── NiriKeybinds.qml          # KDL config parser
│   ├── Idle.qml                   # Wayland IdleInhibitor
│   ├── KeyboardLayoutService.qml  # XKB (Hyprland + Niri)
│   ├── MaterialThemeLoader.qml   # Wallpaper → MD3 colors
│   ├── MprisController.qml       # Media player tracking
│   ├── Network.qml               # nmcli WiFi/Ethernet
│   ├── Notifications.qml         # Persistent notification center
│   ├── ResourceUsage.qml         # CPU/RAM/swap/network from /proc
│   ├── SpectrumService.qml       # Cava audio spectrum (reference counted)
│   ├── TrayService.qml           # System tray with pinning + DBus menu support
│   ├── FocusTime.qml             # App usage tracker daemon lifecycle
│   ├── AntiFlashbang.qml         # GLSL shader to darken bright screens (Hyprland)
│   ├── Wallpapers.qml            # Directory browsing + auto-rotation
│   └── Weather.qml               # wttr.in + GPS
│
├── layouts/                        # 10 overview layout algorithms + manager
│
├── scripts/
│   ├── colors/switchwall.sh       # awww + matugen + pywal (with backup/restore)
│   ├── colors/applycolor.sh       # Apply colors to kitty/ghostty/foot/cava
│   ├── hyprland/get_keybinds.py   # Keybind config parser
│   └── focustime/                 # App usage tracking daemon
│       ├── focus_daemon.py        # Background daemon (Hyprland + Niri, SQLite)
│       └── get_stats.py           # Historical query script (week/month/hourly)
│
├── plugins/                        # C++ extension point placeholder
└── assets/, translations/, panelFamilies/  # Future content
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
Available bar modules: `clock`, `workspaces`, `battery`, `network`, `bluetooth`, `tray`, `media`, `resources`, `activeWindow`, `sidebarButton`, `weather`, `keyboard`, `notifications`, `idle`

### AnoSpot (dynamic-island overlay)
Top/bottom/left/right pill overlay aggregating now-playing (Mpris), latest notification, recording indicator (with elapsed timer), and clock/weather. Compositor-agnostic (Hyprland + Niri).

```json
"anoSpot": {
  "enable": false,
  "position": "top",            // top | bottom | left | right (invalid → top)
  "widthPx": 420, "heightPx": 36,
  "showMpris": true, "showNotification": true, "showRecording": true, "showClockWeather": true,
  "notificationTimeoutMs": 4000
}
```

Toggle from Settings → AnoSpot. The Settings page warns when `anoSpot.position` collides with `bars[0].edge` (visual overlap likely).

> **Renamed** from `ActivSpot`. If your existing `config.json` still uses the old `activSpot` key, it is migrated automatically on first start (values copied to `anoSpot`, old key removed; one-shot, idempotent).

### Overview (AnoView)
Layouts: `smartgrid`, `justified`, `bands`, `masonry`, `hero`, `spiral`, `satellite`, `staggered`, `columnar`, `vortex`, `random`

### AI Chat
Providers: **Gemini** (2.5 Flash, 3 Flash), **Anthropic** (Claude Sonnet 4, Haiku 3.5), **OpenAI** (GPT-4.1 Mini), **Mistral** (Medium 3), **OpenRouter** (dynamic free models), **Ollama** (local auto-detect). Commands: `/model`, `/key`, `/temp`, `/prompt`, `/save`, `/load`, `/clear`

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
| `settings` / `settingsStandalone` | `toggle`, `open` / `open` |
| `audio` | `toggleMute`, `toggleMicMute`, `increment`, `decrement` |
| `brightness` | `increment`, `decrement` |
| `mpris` | `pauseAll`, `playPause`, `previous`, `next` |
| `idle` | `toggle`, `enable`, `disable` |
| `hud` | `toggle`, `open`, `close` |
| `session` | `toggle`, `open`, `close` |
| `dock` | `toggle`, `pin`, `unpin` |
| `clipboard` | `toggle`, `open`, `close` |
| `altSwitcher` | `show`, `hide`, `next`, `prev`, `activate` |
| `search` | `toggle`, `open`, `close` |
| `taskView` | `toggle`, `open`, `close` |
| `mediaControls` | `toggle`, `open`, `close` |
| `controlPanel` | `toggle`, `open`, `close` |
| `weatherPanel` | `toggle`, `open`, `close` |
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
| `zoom` | `zoomIn`, `zoomOut` |
| `TEST_ALIVE` | _(no methods — existence check)_ |

## Keybinds (Hyprland)

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
| `cliphist` + `wl-clipboard` | Clipboard |
| `curl` | HTTP (weather, AI chat) |
| `libnotify` | Notifications |
| `python3` | Scripts |

For the Niri session specifically, **niri ≥ 26.04** is required — `~/.config/niri/ano.kdl` uses the `background-effect { blur }` and window-rule `popups { … }` blocks introduced in 26.04 for visual parity with Hyprland-Ano.

### Recommended
`pyprland` (dropdown terminal, minimize, lost windows), `pywal` (terminal colors), `ddcutil` (external monitors), `cava` (spectrum), `zenity` (file picker), `ydotool` (paste), `translate-shell` (translator)

### Optional
`ffmpeg`, `hyprpicker`, `qalc` (calculator), `grim`+`slurp` (screenshot)

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
