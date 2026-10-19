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

## For scripts

anod's socket: `display.get`, `display.apply` (`{"outputs": [...]}`),
`display.confirm`, `display.revert`, `display.saveProfile` (`{"name"}`),
`display.outputsChanged`, `cursor.themes` and `cursor.apply`
(`{"theme", "size"}`). Events: `display_pending`, `display_confirmed`,
`display_reverted` and `display_profile`.

To try the Settings flow without touching the screen, start anod with
`ANOD_DISPLAY_DRYRUN=1`. It reads the real monitors but only logs what it
would apply or run.
