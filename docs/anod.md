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

## Autostart

The bundled `external/hyprland/hyprland.lua` and `external/niri/ano.kdl` start
anod next to the shell, and skip it if it isn't installed. On Hyprland, set
`ANOD_SUPERVISE = true` to let anod start the shell itself and restart it after
crashes. On niri, replace the two startup lines with `anod --supervise`.

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
| `ano setup update` | fast-forwards the checkout from its remote (refuses with uncommitted changes or diverged local commits; never rewrites history), then refreshes |
| `ano setup refresh` | rebuilds anod + ano, migrates your config (backup first), then restarts a running anod (keeping `--supervise`) or reloads a running shell |
| `ano version` | prints the version |

`install`, `update` and `refresh` take `--dry-run` (print each step without running
it) and `--no-restart`. They don't touch your compositor config.

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

Methods also include `shutdown`, which a new session's anod uses to retire a
stale one.

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
