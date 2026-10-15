# Look file format

A look is `<id>.json` here (built-in) or in `~/.config/anoshell/looks/` (yours;
the same id overrides a built-in). See docs/looks.md for authoring.

| Key | Type | Rules |
|---|---|---|
| `id` | string | required; must equal the file name without `.json` |
| `name` | string | required |
| `description` | string | optional |
| `version` | number | `1` |
| `shape.radiusScale` | number | 0.2–3, multiplies every rounding token (not `full`) |
| `shape.stroke` | number | 0–4, outline width in px |
| `shape.connectedRadius` | number | 0–48, fillet radius of the connected frame |
| `shape.squircle` | bool | continuous-curvature corners where supported |
| `material.kind` | string | `solid`, `paper` or `clay` |
| `material.glass` | bool | whether the glass material may be layered on |
| `texture` | object or null | `shader` one of `caustics`, `paper_grain`, `ink_bleed`, `grid_scan`, `clay_soft`; `animate` `static` or `interaction`; `params` object |
| `typography.main/title/numbers/mono` | string | a font family, or `@main`, `@mono`, `@reading`, `@expressive` for your configured fonts |
| `motion.liquid/settle/snappy` | object | `spring` 0.5–40, `damping` 0.05–1, `mass` 0.2–3 |
| `surfaces.<surface>` | object | per-surface overrides of the keys above |
