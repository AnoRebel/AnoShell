# Looks

A **look** is AnoShell's visual identity: the shape of corners, the panel
material and texture, the typefaces and the motion. Colours are separate (see
"Colour modes" below), so any look works with any wallpaper or theme.

## Built-in looks

| Look | Feel |
|---|---|
| **Liquid** (default) | One fluid body: droplet pills, meniscus joins, caustic light that moves while you hover a panel. |
| **Ink** | Tighter corners, paper grain, calm motion. |
| **Neo-tech** | Crisp, small radii, mono numbers, a faint grid with a scan line on hover. |
| **Clay** | Round, soft inner light, springy motion. |

Pick one in **Settings → Appearance → Look**, or leave it on **Auto** to use
your layout's default (Ano and Hefty: Liquid; Clean: Neo-tech; Minimal: Ink).
Switching morphs every surface; nothing restarts.

From a terminal:

```sh
ano looks list                 # every look, with problems if any
ano looks validate my.json     # check a file (exit 1 on errors)
ano ipc call looks set clay    # switch now ("" goes back to Auto)
```

## Your own looks

Put `<id>.json` in `~/.config/anoshell/looks/`. It appears in Settings as you
save it. A look only has to set what it changes; everything else comes from
Liquid. A file with the same id as a built-in replaces that built-in.

Example, `~/.config/anoshell/looks/midnight.json`:

```json
{
  "id": "midnight",
  "name": "Midnight",
  "description": "Neo-tech's lines with softer corners and a slow scan.",
  "version": 1,
  "shape": { "radiusScale": 0.8, "stroke": 1, "connectedRadius": 14 },
  "texture": { "shader": "grid_scan", "animate": "interaction", "params": { "spacing": 32, "strength": 0.06 } },
  "typography": { "numbers": "@mono" },
  "motion": { "settle": { "spring": 6.0, "damping": 0.7 } }
}
```

If something is wrong (an unknown shader, a number out of range, an `id` that
doesn't match the file name) the look is listed with a red badge saying why and
can't be applied until it's fixed.

## Reference

| Key | Values |
|---|---|
| `id` | required; the file name without `.json` |
| `name` | required |
| `description` | shown under the name in Settings |
| `shape.radiusScale` | 0.2–3; multiplies every corner radius (pills stay pills) |
| `shape.stroke` | 0–4 px outline on panels |
| `shape.connectedRadius` | 0–48 px; the fillet of the connected frame |
| `material.kind` | `solid`, `paper` or `clay` |
| `texture.shader` | `caustics`, `paper_grain`, `grid_scan`, `clay_soft` (`ink_bleed` is accepted and drawn as paper grain for now) |
| `texture.animate` | `static`, or `interaction` (moves only while you hover) |
| `texture.params` | `strength` (or `grain` / `light`), and `spacing` px for `grid_scan` |
| `transition` | `none`, or `ink_bleed`: panels soak in like ink when they open (Ink uses it) |
| `typography.main/title/numbers/mono` | a font family, or `@main`, `@mono`, `@reading`, `@expressive` for the fonts set in Settings → Appearance → Fonts |
| `motion.liquid/settle/snappy` | `spring` 0.5–40, `damping` 0.05–1, `mass` 0.2–3 |
| `surfaces.<surface>` | the same keys again, for one surface only (`hud`, `settings`, `controlPanel`, `media`, `weather`, `cheatsheet`, `wallpaper`, `calendar`) |

Fonts you set yourself in Settings always win over a look's typography.
Textures can be switched off in Settings → Appearance → Look → Surface textures.

## Colour modes

Settings → Appearance → Theme source:

- **Wallpaper + accent** (default): the palette follows your wallpaper; the
  AnoShell violet → teal signature stays fixed for brand moments.
- **Wallpaper**: the wallpaper's colours everywhere, accent included.
- **Fixed**: the AnoShell palette. Changing the wallpaper leaves the shell's and
  your apps' colours alone.

**Apps** sets light or dark for your applications independently of the shell
(GTK's color-scheme, and Qt apps through the desktop portal). A GTK theme you
picked yourself is never replaced; only adw-gtk3 is switched between its light
and dark variants.
