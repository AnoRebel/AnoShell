# Terminal looks and prompts

**Settings → Appearance → Terminal look** (`terminal.*`). Off until you turn on
**Manage terminal looks**; the prompt is your own until you pick a style.
Inspired by Anserin's terminal settings (reimplemented, no code copied).

## Looks

For kitty, foot, Ghostty and Alacritty (`terminal.apps.<name>`, each on by
default when it's installed or has a config):

| Key | | |
|---|---|---|
| `background` | `solid`, `translucent` (`opacity`, 0.85) or `clear` | the terminal's own background opacity, so text stays solid |
| `blur` | blur behind translucent terminals | see below |
| `padding` | 0–32 px (12) | |
| `cursor` | `block`, `beam` (default) or `underline` | programs and shell integration can still change it |

Each terminal gets one generated file in
`~/.local/state/anoshell/generated/terminal/look-*` and **one marked block** in
its own config that pulls it in (the config is backed up once to
`<file>.ano-backup`; nothing else in it is changed, and switching off takes the
block out again):

| Terminal | Pulled in by | Changes reach |
|---|---|---|
| kitty | `include …/look-kitty.conf` at the end of `kitty.conf` | running windows (SIGUSR1) |
| Ghostty | `config-file = ?…/look-ghostty` | running windows (SIGUSR2) |
| Alacritty | `import = ["…/look-alacritty.toml"]` in `[general]` | running windows (it watches its config) |
| foot | `[main]` `include=…/look-foot.ini` at the end of `foot.ini` | new windows |

Alacritty loads imports *before* its own file, so a value you set in
`alacritty.toml` wins over these. If your `alacritty.toml` already has an
`import` list, it's left alone and the log says which file to add to it.

The colours are separate: **Settings → Appearance → Colour kitty / Ghostty /
foot** (`appearance.theme.terminals`) add their own block.

### Blur

Blur is the compositor's: anod writes a window rule for the terminals into its
managed file (`~/.config/hypr/ano-managed.lua`, `~/.config/niri/ano-managed.kdl`,
pulled in by `ano keybinds migrate` or one line of your own, see
[keybinds](keybinds.md)).

- **Hyprland** blurs translucent windows whenever its own blur is on
  (`decoration.blur`), so **Blur behind** on needs nothing; off writes a
  `no_blur` rule, which applies after Hyprland reloads its config.
- **niri** 26.04 or newer: on writes a `background-effect { blur true }` rule,
  applied live.
- sway, labwc, mango, Umbriel: no window blur (the switch is greyed out).

## Prompts

`terminal.prompt`:

- `own` (default): your prompt, untouched, and nothing added to your rc files.
- `segments`: connected powerline segments (user, folder, git branch) in the
  palette's accent and two shades of it, each with its readable text colour; a
  red ✘ after a failed command. Needs a font with powerline glyphs (any Nerd Font).
- `minimal`: the folder and an arrow in the accent colour (red after a failure).

The shells in `terminal.shells` (zsh, bash, fish; none picked: your login
shell) get **one marked line** at the end of `~/.zshrc`, `~/.bashrc` or
`~/.config/fish/config.fish` (backed up once; only existing files). It sources
`~/.local/state/anoshell/generated/terminal/prompt.<shell>`, which reads the style
and colours from `prompt.env` at every prompt: a new wallpaper's palette (or a
new style) shows at the next prompt in open terminals. Picking `own` takes the
line out; open shells go back to the prompt they had.

With **Starship** installed, the line runs Starship with a generated
`starship.toml` next to `prompt.env` (`STARSHIP_CONFIG` for that session only;
your own `starship.toml` isn't read or changed), regenerated with the palette.

## By hand

`~/.config/quickshell/ano/scripts/terminal/apply-terminal.sh` applies
everything from your config (`--prompt`: only the prompt colours; the palette
script runs that after each wallpaper change). `ANOSHELL_NO_LIVE=1` leaves
running terminals alone.
