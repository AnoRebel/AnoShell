# The `ano` CLI

`ano` is the command-line front end for the shell and [anod](anod.md). It is
installed next to anod by `anod/install.sh` (see [Installation](installation.md)).
`ano help` prints the summary; `ano setup help` and `ano backup` print theirs.

## Shell and daemon

| Command | What it does |
|---|---|
| `ano status [--json] [--frame]` | anod's state (version, pid, uptime, clients, supervisor) and the shell's (running, compositor backend). `--frame` also lists the surfaces fused into the connected frame |
| `ano doctor [--json]` | checks required and optional dependencies, the config, sockets, the last crash, QML warnings/errors the running shell logged and competing wallpaper rotators. Exits 1 on any FAIL |
| `ano reload` | reloads the shell |
| `ano ipc <args…>` | passes through to `qs -c ano ipc` |
| `ano emit <event> [key=value …]` | sends a shell event to anod, which runs its hook |
| `ano share-pick [--allow-token]` | the Hyprland screen-share picker, as xdph runs it (through `scripts/share-picker`); falls back to `hyprland-share-picker`. `ano share-pick status` says what xdph.conf uses; `ano share-pick install [--picker PATH] [--dry-run]` sets it, after a backup ([extras → Screen sharing](extras.md#screen-sharing-hyprland)) |
| `ano version` | prints the version and the API version |

```sh
ano ipc show                       # list the shell's IPC targets
ano ipc call settings open         # open Settings
ano emit theme_mode_changed themeMode=light   # try a hook
```

The events `ano emit` accepts are `started`, `wallpaper_changed`,
`theme_mode_changed`, `session_locked`, `session_unlocked`, `logging_out`,
`rebooting`, `shutting_down`, `wifi_changed`, `bluetooth_changed`,
`battery_changed` and `power_profile_changed`. What each hook receives is in
[anod → Event hooks](anod.md#event-hooks).

## Config

`--file` defaults to `~/.config/anoshell/config.json`, your delta over the
bundled `config.json` (see [Configuration](configuration.md)).

| Command | What it does |
|---|---|
| `ano config validate [--file F] [--json]` | checks the config against the schema: wrong types are errors (exit 1), unknown keys are warnings |
| `ano config migrate [--file F] [--prune-unknown] [--dry-run]` | rewrites old keys (`hud.enabled`, `activSpot`, `appearance.theme.static`, `bar.bars`, and `bars[0].autoHide`/`showBackground`). It first writes a new `config.json.bak-YYYYMMDD-HHMMSS`, follows a symlinked config and keeps the file's permissions. `--prune-unknown` also removes keys the shell ignores |

## Looks

| Command | What it does |
|---|---|
| `ano looks list [--json]` | every look the shell can load (built-in and yours), with what's wrong with any invalid one |
| `ano looks validate [FILE…] [--json]` | checks look files (all of them when none is given) against the rules in [Looks](looks.md#reference). Exits 1 on errors |

## Default apps

| Command | What it does |
|---|---|
| `ano run terminal\|browser\|files [args…]` | opens your default app (`apps.terminal`, `apps.browser`, `apps.fileManager`). If that program isn't installed, the first installed one of the usual ones is used (terminals: kitty, ghostty, alacritty, …). The bundled keybinds use it, so changing an app in Settings → Modules → Default Applications needs no bind change. `--print` shows the command instead of running it |

## Welcome

`ano welcome` runs the first-start wizard again. See [Welcome and presets](onboarding.md).

## Keybinds

| Command | What it does |
|---|---|
| `ano keybinds list [--json]` | the keybind set (defaults plus your changes) and which compositor each bind is for |
| `ano keybinds apply` | regenerates the managed bind files |
| `ano keybinds migrate [--dry-run]` / `--revert` | moves the binds out of your compositor configs into ano, or undoes that. See [Keybinds](keybinds.md) |

## Reader

| Command | What it does |
|---|---|
| `ano reader anime\|manga\|novel [open\|close\|toggle]` | shows or hides a reader panel (toggle by default). See [Reader](reader.md) |
| `ano reader status [--json]` | whether anod's reader backend is running, the open panels and playback |

## Setup: install, update, refresh

| Command | What it does |
|---|---|
| `ano setup status [--fetch] [--json]` | the shell checkout (branch, commit, uncommitted changes), how far it is ahead of or behind its remote (`--fetch` fetches first), and the state of the CLI, anod and your config |
| `ano setup install [--repo URL] [--branch B]` | clones the shell into `~/.config/quickshell/ano` if it isn't there (default branch `main`), builds anod and `ano`, then runs `ano doctor` |
| `ano setup update [--force]` | fast-forwards the checkout from its remote, then refreshes. It refuses when you have uncommitted changes or local commits that diverged |
| `ano setup refresh` | rebuilds anod and `ano`, migrates your config (backup first), then restarts a running anod (keeping `--supervise`) or reloads a running shell |

`install`, `update` and `refresh` also take:

- `--dry-run`: print each step without running it.
- `--no-restart`: leave anod and the shell running as they are.
- `--prebuilt`: use prebuilt binaries instead of building (automatic without Go).

They don't touch your compositor config.

`update --force` is for a checkout you've changed: it stashes your changes
(untracked files too), keeps any local commits on an `ano-backup/<time>`
branch, resets to the remote's latest and refreshes. Nothing is deleted.

### Interactive menu

`ano setup` with no command, run in a terminal, opens an interactive menu. Pick
an action, read its `--dry-run` plan, and press Enter to run it. The menu runs
the same subcommands, so scripts can keep calling them directly.

## Backup and restore

| Command | What it does |
|---|---|
| `ano backup categories` | lists what can be backed up; the defaults are marked |
| `ano backup create [--only a,b] [--add a,b] [-o FILE]` | archives the default categories, only the ones named (`--only`), or the defaults plus opt-in ones (`--add`) |
| `ano backup list` | lists the backups in the default folder with their categories |
| `ano backup restore FILE [--only a,b] [--dry-run] [--no-snapshot]` | restores every category in the backup, or only the named ones |

| Category | Contents | Default |
|---|---|---|
| `config` | `~/.config/anoshell/config.json`, including anod hooks | yes |
| `themes` | `~/.config/anoshell/themes` | yes |
| `atelier` | `~/.config/anoshell/` `pieces`, `plugins`, `lockscreens`, `looks` and `rices` | yes |
| `data` | calendar, chats, notes and other shell data (not secrets) | yes |
| `secrets` | API keys | opt-in |
| `compositor` | `~/.config/hypr` and `~/.config/niri` | opt-in |
| `wallpapers` | the wallpaper folder (large) | opt-in |
| `avatar` | `~/.face` | opt-in |

Backups go to `~/.local/share/anoshell/backups/anoshell-<time>.tar.gz` with mode
0600; secrets keep 0600 inside the archive.

Before a restore replaces anything, it saves the files it will replace to
`pre-restore-<time>.tar.gz` (skip that with `--no-snapshot`). A restore never
writes outside your home, never overwrites a symlink, and follows a symlinked
folder (stow-style dotfiles) only if it stays inside your home.

Settings → About → Backup & restore does the same through anod: pick the
categories, back up, choose a backup, pick what to restore, and Preview lists
the files a restore would replace before you run it.

```sh
ano backup create --add secrets,compositor
ano backup restore ~/.local/share/anoshell/backups/anoshell-<time>.tar.gz --only config --dry-run
```
