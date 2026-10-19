# Keybinds

AnoShell keeps **one keybind set** for every compositor. Each bind maps a key
chord to an action. From that set anod writes Hyprland's and niri's bind files,
so a chord does the same thing on both.

- **Neutral actions:** close a window, focus or move left/right/up/down, go to
  or move a window to workspace N, toggle a shell panel, run a command, and so
  on. On Hyprland they render as `hl.bind(…)`, on niri as `binds { … }`.
- **Compositor-only actions:** a niri column operation or a Hyprland global
  shortcut are kept as that compositor's own action and generated only there.
  `ano keybinds list` shows which compositor each bind is for.

## The defaults

The shipped set is built from the binds bundled in `ano/external/` (Hyprland
Lua and niri `ano.kdl`) by a dev tool:

```sh
cd ano/anod && go run ./cmd/keybinds-import   # needs lua
```

Where the two bundled sets bind the same chord to different things, Hyprland's
bind wins, unless it only exists on Hyprland (then each compositor keeps its
own). Every clash is listed in `anod/internal/keybinds/import-report.md`.

## Your changes

Your changes are kept apart from the defaults, in
`~/.config/anoshell/keybinds.json`, so new default binds still reach you:

```json
{
  "binds": [ { "chord": "Super+D", "action": "shell", "args": ["search", "toggle"] } ],
  "remove": [ "Super+Space" ]
}
```

A bind there replaces the defaults on its chord, on the compositors it applies
to (`"only": "hyprland"` or `"niri"` limits it). `remove` takes a chord away.

| Command | |
|---|---|
| `ano keybinds list [--json]` | the effective set |
| `ano keybinds apply` | regenerate `~/.config/hypr/ano-managed-binds.lua` and `~/.config/niri/ano-managed-binds.kdl` (and reload Hyprland) |
| `ano keybinds migrate --dry-run` | show what a migration would do; writes nothing |
| `ano keybinds migrate` | move the binds out of your configs (below) |
| `ano keybinds migrate --revert` | put your configs back exactly as they were |

anod's socket offers the same to Settings: `keybinds.list`, `keybinds.set`
(`{"chord", "bind" | null, "replace"?}`; a chord already in use answers a
`conflict` error naming what is bound there, unless `replace` is set) and
`keybinds.reset` (`{"chord"?}`; no chord resets everything).

The cheatsheet (Super+/) asks anod for `keybinds.active`: what the running
compositor binds right now (ano's set once migrated, else your own config,
read the same way), grouped and searchable, plus the AnoShell actions that no
key triggers.

## Migration

Until you migrate, your compositor configs keep their own binds and the
generated files are unused. `ano keybinds migrate`:

1. Backs up `~/.config/hypr/hyprland.lua`, any file it `require`s that has
   binds, and `~/.config/niri/config.kdl` (next to them, with a timestamp).
2. Turns every live bind that differs from the defaults into one of your
   changes, for that compositor, so nothing you had stops working.
3. Removes the bind statements from those files (Hyprland `hl.bind` calls,
   niri's `binds {}` block) and adds one include line at the end of each.
4. Writes the managed files and reloads Hyprland. niri picks up the included
   file itself.

`--revert` restores the backed-up files byte for byte.

Reading a Hyprland config runs it with the `lua` interpreter against a
recording stand-in for `hl`, so loops and helper functions are understood.
Binds whose action is a Lua function are carried over as written, together
with the local helpers they use.
