# anod and the `ano` CLI

anod is ano's companion daemon. It does the work that has to outlive a crash of
the shell (the `qs -c ano` process): event hooks, optional supervision of the
shell, and config validation and migration. Later waves add the wallpaper
pipeline, the reader backend and display profiles.

The shell never depends on anod. Without it, everything native (bar, panels,
audio, notifications) keeps working and daemon features show as unavailable.

## Install

```sh
~/.config/quickshell/ano/anod/install.sh          # builds anod + ano into ~/.local/bin
~/.config/quickshell/ano/anod/install.sh --test   # runs the Go tests first
```

Requires Go ≥ 1.27. Set `PREFIX` to install elsewhere (`$PREFIX/bin`).

Without Go (or with `--prebuilt`), `install.sh` installs prebuilt static
binaries instead: from `anod/dist/linux-<arch>/` when you built them with
`anod/dist.sh`, otherwise from a GitHub release (`anoshell-linux-<arch>.tar.gz`, amd64 and
arm64), checked against the release's `SHA256SUMS` before anything is installed.

| Channel | Built from | Pick it with |
|---|---|---|
| `stable` | every push to `main` (the latest stable build; the default) | `ANO_CHANNEL=stable` |
| `dev` | every push to `dev` (development builds; the default when this checkout is on `dev`) | `ANO_CHANNEL=dev` |
| a version | a pushed `v*` tag | `ANO_RELEASE=v0.2.0` |

`ANO_RELEASE_URL` points at a mirror. The channels are published by
`.github/workflows/release.yml`, which also runs vet, tests and the cross-build
on every pull request. `stable` and `dev` are rolling releases under the tags
`channel-stable` and `channel-dev` (prefixed so no tag shares a branch's name):
each push moves the tag and replaces the tarballs.

## Autostart

The bundled `external/hyprland/hyprland.lua` and `external/niri/ano.kdl` start
anod next to the shell, and skip it if it isn't installed. On Hyprland, set
`ANOD_SUPERVISE = true` to let anod start the shell itself and restart it after
crashes. On niri, replace the two startup lines with `anod --supervise`.

A supervised shell runs with transparent huge pages off, which measured about
100 MB less memory with no CPU cost. `shell.hugePages: true` in your config
turns them back on (anod reads it when it starts).

Supervision restarts the shell with exponential backoff (1 s, doubling, up to
30 s). After 5 crashes within 2 minutes it stops and sends a notification with
the path of the last Quickshell crash report. A clean exit (you quit the shell)
is not restarted.

## The `ano` CLI

| Command | What it does |
|---|---|
| `ano status [--json] [--frame]` | anod and shell state (version, uptime, supervisor, backend); `--frame` lists the surfaces fused into the connected frame |
| `ano doctor [--json]` | checks required and optional dependencies, the config, sockets, the last crash and competing wallpaper rotators. Exits 1 on any FAIL |
| `ano reload` | reloads the shell |
| `ano ipc <args…>` | passes through to `qs -c ano ipc`, e.g. `ano ipc call settings open`, `ano ipc show` |
| `ano emit <event> [key=value …]` | sends a shell event to anod, which runs its hook (handy for testing hooks) |
| `ano config validate [--file F] [--json]` | checks your config against the schema: wrong types are errors (exit 1), unknown keys are warnings |
| `ano config migrate [--file F] [--prune-unknown] [--dry-run]` | rewrites old keys (`hud.enabled`, `activSpot`, `appearance.theme.static`, `bar.bars`, and `bars[0].autoHide`/`showBackground`, which shadowed the global switches). It writes a new `config.json.bak-YYYYMMDD-HHMMSS` first (never overwriting an older backup), follows a symlinked config, and keeps the file's permissions. `--prune-unknown` also removes keys the shell ignores |
| `ano setup status [--fetch] [--json]` | the shell checkout (branch, commit, uncommitted changes), how far it is ahead/behind its remote, and the CLI, anod and user-config state |
| `ano setup install [--repo URL] [--branch B]` | clones the shell into `~/.config/quickshell/ano` if it isn't there, builds anod + ano, then runs `ano doctor` |
| `ano setup update [--force]` | fast-forwards the checkout from its remote (refuses with uncommitted changes or diverged local commits), then refreshes. `--force` stashes your changes (untracked files too), keeps any local commits on an `ano-backup/<time>` branch, resets to the remote's latest and refreshes; nothing is deleted |
| `ano setup refresh` | rebuilds anod + ano, migrates your config (backup first), then restarts a running anod (keeping `--supervise`) or reloads a running shell |
| `ano backup categories` | lists what can be backed up: `config`, `themes`, `atelier` (your pieces, plugins, lock screens, looks and rices), `data` (the defaults), plus opt-in `secrets`, `compositor` (hypr/niri configs), `wallpapers` and `avatar` |
| `ano backup create [--only a,b] [--add a,b] [-o FILE]` | archives the default categories, only the ones named, or the defaults plus opt-in ones, to `~/.local/share/anoshell/backups/anoshell-<time>.tar.gz` (mode 0600; secrets keep 0600 inside) |
| `ano backup list` | lists the backups in that folder with their categories |
| `ano backup restore FILE [--only a,b] [--dry-run] [--no-snapshot]` | restores every category in the backup, or only the named ones. The files it will replace are first saved to `pre-restore-<time>.tar.gz`. It never writes outside your home, never overwrites a symlink, and follows a symlinked folder (stow-style dotfiles) only if it stays inside your home |
| `ano atelier [type]` | opens Settings on the Atelier page (that type's tab): through the running shell (`atelier open`), else standalone Settings |
| `ano atelier list [type] [--json]` / `ano atelier refresh` | local and catalog items (refresh fetches the catalogs first) |
| `ano atelier install <type> <id> [--catalog URL] [--yes]` | verified install from a catalog; code content (pieces, plugins, lock screens) shows the audit findings and declared hosts/commands and asks y/N unless `--yes` |
| `ano atelier remove <type> <id>` | removes a catalog install (never built-in items or your own files) |
| `ano atelier wallhaven [query…] [--page N] [--purity sfw\|sketchy\|nsfw] [--sorting S]` / `ano atelier wallhaven-install <id>` | searches Wallhaven through anod (beyond SFW needs your key, saved with `secret.set` as `wallhaven`), or installs one into `<wallpaper folder>/hub/wallhaven-<id>.<ext>` with a receipt |
| `ano atelier pack <dir\|file> [--type T] [--id ID] [--version V] [--url-base URL] [--out DIR]` | archives an item in the catalog format, checks it would install, prints its index entry with the SHA-256 |
| `ano version` | prints the version |

`ano setup` with no command, run in a terminal, opens an interactive menu
(Bubble Tea): pick an action, read its `--dry-run` plan, press Enter to run it.
It runs the same subcommands, so scripts can keep using them directly.

`install`, `update` and `refresh` take `--dry-run` (print each step without running
it), `--no-restart` and `--prebuilt` (use the bundled binaries; automatic
without Go). They don't touch your compositor config.

`--file` defaults to `~/.config/anoshell/config.json`, your sparse delta over the
bundled `config.json`.

## Event hooks

Set a shell command per event under `hooks` in `~/.config/anoshell/config.json`.
anod runs it with `sh -c`, asynchronously, in its own process group. A hook that
runs longer than `hooks.timeoutSeconds` (default 10) is killed and logged.
Programs a hook starts in the background (`cmd &`) keep running. Event data
arrives only through the environment (`ANO_EVENT` plus the variables below),
never spliced into the command.

While a hook is still running, repeats of the same event collapse into one more
run with the newest data. State events (Wi-Fi, Bluetooth, battery, power
profile, theme, lock) fire only on real changes, never just because the shell
started.

```json
{
  "hooks": {
    "themeModeChanged": "notify-send \"Theme\" \"$ANO_THEME_MODE\"",
    "batteryChanged": "[ \"$ANO_BATTERY_LOW\" = true ] && notify-send 'Battery low' \"$ANO_BATTERY_PERCENT%\"",
    "batteryThreshold": 15
  }
}
```

| Config key | Event | Environment |
|---|---|---|
| `started` | `started`: the shell started or reloaded | none |
| `wallpaperChanged` | `wallpaper_changed`: after the new colours are applied (or 6 s after a wallpaper change that produces no colour update) | `ANO_WALLPAPER`, `ANO_THEME_MODE` |
| `themeModeChanged` | `theme_mode_changed` | `ANO_THEME_MODE` (`dark` or `light`) |
| `sessionLocked` / `sessionUnlocked` | `session_locked` / `session_unlocked` | none |
| `loggingOut` / `rebooting` / `shuttingDown` | `logging_out` / `rebooting` / `shutting_down` | none |
| `wifiChanged` | `wifi_changed` | `ANO_WIFI` (`on` or `off`) |
| `bluetoothChanged` | `bluetooth_changed` | `ANO_BLUETOOTH` (`on` or `off`) |
| `batteryChanged` | `battery_changed`: the charge state changed, or `batteryThreshold` was crossed | `ANO_BATTERY_PERCENT`, `ANO_BATTERY_STATE` (`charging`, `discharging`, `full`, or `plugged` for on AC but not charging), `ANO_BATTERY_LOW` |
| `powerProfileChanged` | `power_profile_changed` | `ANO_POWER_PROFILE` (`power-saver`, `balanced` or `performance`) |

`hooks.enable: false` turns all hooks off. Hooks read the config on every event,
so edits apply without a restart. The logout, reboot and shutdown hooks get a
0.5 s head start before the session ends, so keep them short. Try a hook with,
for example, `ano emit theme_mode_changed themeMode=light`.

## Socket protocol (for scripts)

The socket is at `$XDG_RUNTIME_DIR/ano/anod.sock`, inside a 0700 directory, with
mode 0600. Messages are newline-delimited JSON:

```
→ {"v":1,"id":1,"method":"status"}
← {"id":1,"result":{"version":"0.1.0","api":1,"pid":1234,...}}
→ {"v":1,"id":2,"method":"subscribe","params":{"events":["theme_mode_changed"]}}   (no params = all events)
← {"event":"theme_mode_changed","data":{"themeMode":"light"}}
```

Methods: `ping`, `version`, `status`, `subscribe`, `event.emit`
(`{"event":…, "data":{…}}`) and `config.validate`. Errors look like
`{"id":…,"error":{"code":"…","message":"…"}}`, with the codes
`version_mismatch`, `unknown_method`, `bad_request` and `failed`. A client that
sends the wrong `v` gets `version_mismatch`; the shell then shows a one-time
notification and checks again the next time anod restarts.

Startup applications (`anod/internal/autostart`): `autostart.list` (the
entries of `autostart.entries` with their names, errors and when this anod
started them, plus the read-only `~/.config/autostart` files and the launch
mode) and `autostart.run` (`{"index"}`: start that entry now). The list itself
is config, edited by Settings; anod starts the enabled entries once per session
(marker `$XDG_RUNTIME_DIR/ano/autostart.session`).

Methods also include `shutdown`, which a new session's anod uses to retire a
stale one.

Wallpaper methods: `wallpaper.set` (`{"image", "outputs"?, "mode"?, "schemeType"?, "prefer"?, "transition"?, "colorsOnly"?}`;
the colour options given win over the ones remembered for the image, which win over the config's;
`"transition": "none"` skips awww's transition, for the picker whose card grows into the wallpaper;
`"colorsOnly": true` redoes colours and hooks for what's already shown, for the light/dark switch;
a video needs `background.engine: "shell"`), `wallpaper.colors` (`{"image", "mode"?, "schemeType"?,
"prefer"?, "remember"?, "reset"?, "recolor"?}`: for `image`, or by default the wallpaper the colours
follow (`appearance.colors.from`), remembers the picks (`remember`) or forgets them (`reset`), redoes
its colours and returns `{"scheme", "custom", "image"}`; with no pick, reset or recolor it only
reports; kept in `~/.local/state/anoshell/wallpaper-colors.json`), `wallpaper.focus` (`{"output"}`:
the shell's focused output; with `from: "focused"` the colours are redone from its wallpaper and a
`wallpaper_colors` event says what they were made with), `wallpaper.next`, `wallpaper.status`,
`palette.scan` (`{"dir"}`: per file its source colour, hue, luminance and a
video still, cached by path, size and mtime; saved as it goes) and
`palette.get` (`{"path"}`: the same for one file). `wallpaper.set`, `wallpaper.colors`,
`palette.scan` and `palette.get` are slow methods: they run beside the
connection's other requests, so their replies can arrive after later ones
(match replies by `id`).

Theme methods (the Theme studio, and static themes): `theme.generate`
(`{"primary", "secondary"?, "tertiary"?, "mode"?, "schemeType"?, "overrides"?}`: a full Material 3
scheme from matugen, `{"colors": {role: hex}}`, nothing written; seeds are `#rrggbb`, a secondary or
tertiary seed supplies that family, `overrides` replaces roles), `theme.save` (the same plus
`"name"`: written to `~/.config/anoshell/themes/<slug>.json` and marked as made by the studio;
returns `{"name": slug, "colors"}`; a built-in theme's name or a theme the studio didn't make is
never overwritten), `theme.delete` (`{"name"}`: studio-made themes only) and `theme.apply`
(`{"name"}`: a user or built-in theme's palette goes to `colors.json`, GTK and the colour hooks
that don't read the wallpaper image, like a wallpaper's; the shell calls it when a static theme
is picked). Under a static theme a wallpaper change leaves `colors.json` and the app colours alone.
`theme.generate`, `theme.save` and `theme.apply` are slow methods.

Downloads: `downloads.list` returns `{"dir", "active": [{"path", "name",
"size", "rate"}], "finished": [{"path", "name", "size", "at"}]}`, the
browsers' partial files (`.part`, `.crdownload`) growing in the download
folder (`XDG_DOWNLOAD_DIR` from `user-dirs.dirs`, else `~/Downloads`) and
the last five renamed to their real name while anod watched;
`downloads.clear` (`{"path"?}`) forgets finished ones (all without a path).
The `downloads` event carries the same on every change. Sizes in bytes,
rate in bytes a second; a partial that stops growing drops out after a
minute.

`secret.set` (`{"name", "value"}`, name `[a-z0-9_-]+`) stores an API key in
`$XDG_DATA_HOME/anoshell/secrets/<name>` with mode 0600 (directory 0700),
written atomically; an empty value removes it. The shell reads the file
directly, so there is no `secret.get`. The Wallhaven key lives there as
`wallhaven`, never in `config.json`.

Reader methods (see [reader.md](reader.md)): `reader.open` (`{"kind"}`:
`anime`, `manga` or `novel`; starts the backend if needed and answers its
`url`, token included; slow), `reader.close` (`{"kind"}`), `reader.status`
and `reader.stop` (ends playback).

Atelier methods (Settings → Atelier; see `anod/internal/atelier`): `atelier.list` (`{"type"?}`, cache only:
`{"revision", "items", "catalog", "catalogs"}`), `atelier.refresh` (the same after fetching every catalog
in `atelier.catalogs` with ETags; a failure keeps the cache and marks the catalog `offline`),
`atelier.prepare` (`{"type", "id", "catalog"}`: download, SHA-256 check, staged extraction, static audit
for code; returns a token valid 10 minutes), `atelier.commit` (`{"token"}` → `{"path"}`), `atelier.cancel`,
`atelier.remove` (`{"type", "id"}`), `atelier.riceApply` (`{"id", "layers"}`), `atelier.riceUndo` and
`atelier.riceExport` (`{"name"}` → `{"id", "path"}`), `atelier.wallhaven` (`{"query", "page"?, "purity"?, "sorting"?}` →
`{"items": [{"id", "url", "thumb", "resolution", "fileSize", "fileType", "source", "purity", "page", "installed"}],
"page", "lastPage", "hasKey", "error"?}`; results cached 10 minutes, at most 40 calls a minute, the key sent only as
`X-API-Key`) and `atelier.wallhavenInstall` (`{"id"}` → `{"path"}`: the image location is looked up again on Wallhaven,
only https from `w.wallhaven.cc`, JPEG/PNG/WebP up to 64 MiB). Every change bumps
`$XDG_STATE_HOME/anoshell/atelier/revision`; receipts live in `…/atelier/receipts/<type>/<id>.json`.
Archives with links, devices, absolute paths or `..`, more than 500 files or 64 MiB unpacked are
refused; nothing in an archive is ever run. A rice merges only look keys (`appearance`,
`panelFamily`, bar/dock styles, background resize/transition, anoSpot size/position, piece layout)
and applies its keybinds only when that layer is ticked.

From the shell: `qs -c ano ipc call anod status` shows whether the shell is connected.

## Files

| Path | Contents |
|---|---|
| `$XDG_RUNTIME_DIR/ano/anod.sock` | control socket (plus `anod.sock.lock`) |
| `$XDG_STATE_HOME/ano/anod.log` | log (also on stderr; starts over when it passes 1 MB) |
| `~/.config/anoshell/config.json` | your config (hooks live here) |

anod belongs to the graphical session it started in. It exits within 5 s of
that session ending, and its supervisor never restarts the shell into a dead
display. If you log out and back in quickly, the new session's anod asks the
old one to shut down and takes over. A second anod in the same session refuses
to start (an `flock` on `anod.sock.lock` guards the socket). anod idles at about
8 MB RSS and near-zero CPU.

## Developing

```sh
cd ano/anod && go test ./...            # unit tests (ipc, supervisor, config, hooks, doctor)
python3 ano/scripts/dev/export-schema.py   # regenerate the schema after editing Config.qml
python3 ano/scripts/dev/export-schema.py --check   # fails when the schema is stale
```
