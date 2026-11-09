# Actions

An action is a macro: a name, an icon and a list of steps that run one after
another. "Focus" might turn on do not disturb, set the volume to 30 %, open
your notes and start your editor; "Stream" might apply a look, switch the
power profile to performance and launch OBS.

Write them in **Settings → Actions**. There are none until you make one.

(Not to be confused with the launcher's **Actions** provider,
`search.plugins.actions`, which lists single commands such as Lock screen;
see [Launcher providers](extras.md).)

## Running one

- **The ring**: Super+Ctrl+X in the bundled keybinds, or
  `qs -c ano ipc call actions ring`. Your first 8 actions sit on a ring in
  the middle of the focused screen. Press 1–8, or move with the arrows (or
  Tab) and press Enter; Esc closes it. With no actions yet, Enter opens
  Settings → Actions. The ring is a module like the others: turn it off in
  Settings → Modules → **Actions Ring** (the IPC `run` keeps working).
- **By name**: `qs -c ano ipc call actions run "Focus"`, from a key of your
  own or a script. `qs -c ano ipc call actions list` prints the names.
- **Run now** on the Settings page.

Asked for while another action is running, an action waits its turn (the IPC
answers `queued … after …`); nothing is cancelled.

If a step fails, the action stops there and the shell posts a notification
naming the step and why ("Step 3 (Apply look: Ink) failed: no usable look").
The steps before it have already run.

## The steps

| Step | What it does | Fields |
|---|---|---|
| Launch app | Starts an application, in its own unit like the launcher | name or desktop id (suggestions as you type) |
| Open file or URL | `xdg-open` on a path (`~` works) or a URL | file or URL |
| Set volume | The default output's volume | 0–100 % |
| Set brightness | Every display whose brightness can be set | 0–100 % |
| Do not disturb | Notification popups off or on | on / off |
| Power profile | power-profiles-daemon's profile | power saver, balanced, performance |
| Performance mode | The shell's performance mode, by hand (still on while a game holds GameMode) | on / off |
| Wallpaper | Applies a wallpaper the usual way (anod: colours and hooks) | image or video path |
| Apply preset | A preset from Settings → About → Presets (bundled or yours), read when the step runs | preset |
| Apply look | Liquid, Ink, Neo-tech, Clay or one of yours | look |
| Wait | Pauses before the next step | seconds |
| Shell command | Runs your command with `sh -c`, detached, in its own unit | command |
| Set a setting | Sets one config key to the value it had when you chose it | key (`bar.style`); **Take the current value** captures it again |

A shell command is passed to `sh` as a single argument, as you typed it; the
shell can't tell whether it succeeded once it has started. A **Set a setting**
step can't change `actions` itself.

## The config

`actions.macros` in `~/.config/anoshell/config.json`:

```json
"actions": {
  "macros": [
    {
      "name": "Focus",
      "icon": "self_improvement",
      "steps": [
        { "type": "dnd", "on": true },
        { "type": "volume", "percent": 30 },
        { "type": "launch", "app": "obsidian" },
        { "type": "wait", "seconds": 2 },
        { "type": "command", "command": "notify-send 'Focus' 'Go'" }
      ]
    }
  ]
}
```

Step types and their fields: `launch` (`app`), `open` (`target`), `volume`
(`percent`), `brightness` (`percent`), `dnd` (`on`), `powerProfile`
(`profile`: `power-saver` | `balanced` | `performance`), `performance` (`on`),
`wallpaper` (`path`), `preset` (`path` of the preset file), `look` (`id`),
`wait` (`seconds`), `command` (`command`), `config` (`key`, `value`). The
icon is a [Material Symbols](https://fonts.google.com/icons) name.

Each kind of step is one entry in `services/Actions.qml` (`kinds`): its label,
icon, defaults, fields, how it reads and what it runs. The Settings editor is
drawn from the same entries.

## Needs

Open-file steps need `xdg-utils`; brightness needs `brightnessctl` (or
`ddcutil` for external monitors); the power profile needs
`power-profiles-daemon`. `ano doctor` checks `xdg-open` and `sh`.
