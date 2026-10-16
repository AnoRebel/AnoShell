# Wallpapers

AnoShell's daemon, anod, applies wallpapers and everything that follows from
one, in this order:

1. **awww** shows the image, with the resize mode you chose
   (`background.resize`: `fit`, `crop`, `stretch` or `no`). The mode is recorded,
   so glass can sample exactly what is on screen.
2. **matugen** generates the Material colours from it, written where the shell
   reads them (`~/.local/state/anoshell/generated/colors.json`). The scheme is
   `appearance.colors.schemeType`; with several candidate colours,
   `appearance.colors.prefer` (default `saturation`) picks one.
3. **Your hooks** run one after another (`background.hooks`, below).
4. The change is announced: the shell updates, and your `hooks.wallpaperChanged`
   command runs.

In the **Fixed** colour mode (Settings → Appearance → Theme source) step 3 is
skipped: the colours don't follow the wallpaper.

## Changing it

- The wallpaper picker (Super+W by default), or the bar's wallpaper action.
- From a terminal:

```sh
ano wallpaper set ~/Pictures/Wallpapers/forest.png
ano wallpaper set ~/Pictures/Wallpapers/forest.png --output HDMI-A-1 --mode light
ano wallpaper next      # the next rotation image, now
ano wallpaper status    # what's shown, and the rotation settings
```

## Rotation

`background.randomize` changes the wallpaper on a timer:

```json
"background": {
  "randomize": { "enable": true, "directory": "~/Pictures/Wallpapers", "interval": 300 }
}
```

Each screen gets a different image; colours and hooks follow the first one. Every
image is shown once before any repeats, and that holds across restarts.

If you used `awww_randomize_multi.sh` (or a similar script) from your compositor
config, it now fights anod's rotation. `ano doctor` warns while one runs, and
`ano wallpaper migrate` replaces it: it shows the lines it will change, asks,
backs the files up, comments the lines out, and turns rotation on with the same
folder and interval.

## Hooks

`background.hooks` is a list. Each hook is a command (an argument list, never a
shell string) with:

| Key | Meaning |
|---|---|
| `name` | shown in logs and in `ano wallpaper set`'s report |
| `enable` | `false` skips it |
| `command` | the program and its arguments; `{image}`, `{mode}` (`dark`/`light`) and `{colors}` (the colours file) are filled in |
| `timeoutSeconds` | killed after this long (default 20) |
| `builtin` | `"cava"` instead of a command: recolours cava from pywal and asks it to reload |

A hook that isn't installed is skipped (and says so). Hooks also get
`ANO_WALLPAPER`, `ANO_THEME_MODE` and `ANO_COLORS` in their environment.

The defaults reproduce the usual chain:

```json
"hooks": [
  { "name": "pywal", "enable": true, "command": ["wal", "-i", "{image}", "-n", "-q"], "timeoutSeconds": 30 },
  { "name": "swaync", "enable": true, "command": ["swaync-client", "--reload-css"] },
  { "name": "apps", "enable": true, "command": ["~/.config/quickshell/ano/scripts/colors/applycolor.sh", "--mode", "{mode}"], "timeoutSeconds": 30 },
  { "name": "cava", "enable": true, "builtin": "cava" },
  { "name": "themes", "enable": true, "command": ["~/.config/awww/scripts/awww_generate_themes.sh"], "timeoutSeconds": 30 }
]
```

### Example: your own hook

Add an entry to the list in `~/.config/anoshell/config.json`. This one tells
you which wallpaper was applied:

```json
{ "name": "notify", "enable": true, "command": ["notify-send", "Wallpaper", "{image}"], "timeoutSeconds": 5 }
```

Run `ano wallpaper set …` and the report lists `notify` with `"ok": true`, or
why it was skipped.

## Video wallpapers

awww shows stills and GIFs. Video wallpapers come with the shell-drawn
background (in progress); one video decodes on one screen at a time (the
focused one), and the other screens show a still of it. Glass doesn't refract a
video wallpaper.

## Colours of every wallpaper

anod keeps a cache of each wallpaper's main colour and brightness (keyed by
file, size and modification time), so the picker can sort by colour and glass
can keep text readable. A second look at an unchanged folder costs nothing.
