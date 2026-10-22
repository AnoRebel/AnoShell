# Displays and cursor

Settings → **Displays** arranges your monitors and sets each one's mode,
scale, rotation, variable refresh rate and on/off, on Hyprland and niri. It
also holds display profiles and the cursor. anod does the work
([anod.md](anod.md)), so it has to be running.

## Changing a monitor

- Drag a monitor in the arrangement to move it. It snaps to the edges of the
  others. Click one to change its settings below.
- **Apply** sends the change to the compositor straight away:
  `hl.monitor{…}` on Hyprland, `niri msg output …` on niri.
- A change that could leave you without a usable screen asks
  **Keep these display settings?** on every monitor, with a 15 s countdown:
  a new mode, scale, rotation, or turning a monitor off. Enter keeps it and
  Esc reverts it. If you do nothing, anod puts the old settings back. The
  countdown runs in anod, so this works even if the shell has crashed.
- Moving a monitor or switching VRR applies without asking.
- anod refuses to turn every monitor off.

## Where it is saved

Kept settings go to a file anod owns. Your own compositor config is never
rewritten:

| Compositor | File |
|---|---|
| Hyprland | `~/.config/hypr/ano-managed.lua` |
| niri | `~/.config/niri/ano-managed.kdl` |

Your config includes that file through one line, which
`ano keybinds migrate` adds (with a backup; `--revert` removes it again):

```lua
pcall(dofile, (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/ano-managed.lua")
```

```kdl
include optional=true "ano-managed.kdl"
```

## Profiles

Each kept arrangement is remembered as **Last used** for that set of
monitors, identified by make, model and serial rather than port. You can also
save named profiles (for example "Desk"). When you plug or unplug a monitor,
anod applies the profile saved for the monitors now connected, preferring a
named one, and a short notification names it. Profiles are kept in
`~/.config/anoshell/display-profiles.json`.

## Cursor

The **Cursor** card lists the installed cursor themes, with a preview of each
theme's arrow, and a size. Choosing one:

- applies it live (Hyprland: `hyprctl setcursor`; niri reads the managed file);
- sets GTK's `cursor-theme` and `cursor-size` (gsettings) and updates the
  cursor keys in `~/.config/gtk-3.0` and `gtk-4.0/settings.ini` where they
  already exist;
- writes `XCURSOR_THEME`/`XCURSOR_SIZE` (and `HYPRCURSOR_*`) or niri's
  `cursor {}` into the managed file, so apps started later use it.

The choice is `cursor.theme` and `cursor.size` in your config. "Leave the
cursor to my compositor config" sets the theme to `""`.

**AnoShell** and **AnoShell Cell** are cursors drawn in your wallpaper's
colours (ported from Bioma). They're listed before they exist; choosing one
builds it into `~/.local/share/icons` (`scripts/themes/cursors`, needs
`rsvg-convert` and `magick`), and every palette change rebuilds it. Apps keep
a cursor theme loaded by name, so each has two empty slots,
`anoshell-cursor.a` and `.b`, and the shell moves between them after a
rebuild; that's the name you'll see in gsettings.

## Icons

The **Icons** card sets the desktop icon theme (GTK through gsettings, Qt
through `icon_theme` in qt5ct/qt6ct, which needs the qt6ct package and
`QT_QPA_PLATFORMTHEME=qt6ct`); type to find one of the installed
themes. **AnoShell** and **AnoShell Primary** draw folders and file types in
the wallpaper's colours and inherit everything else (apps first) from the
last other theme you picked (`icons.base`, default Papirus-Dark).
**AnoShell Tint** keeps that theme's own folder and place icons and turns
their colours to the palette's hue (greys and whites stay); colour variants
such as Papirus's `folder-red-*` are left out. A first build takes a few
seconds. They're rebuilt and slot-switched like the cursors. "Leave icons to my desktop
settings" sets `icons.theme` to `""`.

**On the first start** the shell puts AnoShell Tint on, over the icon theme
your desktop had (that becomes `icons.base`), so folders follow the wallpaper
from the start. That happens once (`icons.adopted`); whatever you pick
afterwards, including "Leave icons to my desktop settings", is kept. GTK apps
switch live, and so do Qt apps through qt6ct/qt5ct (about 3 s later); the
shell itself reads it when it starts.

## For scripts

anod's socket: `display.get`, `display.apply` (`{"outputs": [...]}`),
`display.confirm`, `display.revert`, `display.saveProfile` (`{"name"}`),
`display.outputsChanged`, `cursor.themes` and `cursor.apply`
(`{"theme", "size"}`). Events: `display_pending`, `display_confirmed`,
`display_reverted` and `display_profile`.

To try the Settings flow without touching the screen, start anod with
`ANOD_DISPLAY_DRYRUN=1`. It reads the real monitors but only logs what it
would apply or run.
