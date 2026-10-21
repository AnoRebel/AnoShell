# Launcher providers and productivity

Everything here is **off until you turn it on**. While off, nothing is
created, read or run.

## Launcher providers

Settings → Modules → **App Launcher**. Results appear above your apps, and the
arrow keys and Enter work across both.

| Provider | Key (`search.plugins.…`) | How to use it | Needs |
|---|---|---|---|
| Calculator | `calculator.enable` | type a sum or a conversion (`2+2*3`, `5 km to mi`); Enter copies the answer | `qalc` (libqalculate) |
| Emoji | `emoji.enable` | type a name (`fire` → 🔥); `:` alone lists only emoji; Enter copies | nothing |
| Packages | `packages.enable` | `pkg firefox`; Enter installs it in your terminal | `paru` or `yay` (`packages.helper` picks one) |
| Actions | `actions.enable` | type an action's name: Lock screen, Suspend, Reboot, Power off | nothing |
| Colour schemes | `schemes.enable` | `scheme …` switches the Material variant (tonal-spot, rainbow…) or a fixed theme, live | anod (for the variant) |
| Looks | `looks.enable` | `look …` switches the look, live | nothing |

**Actions** come from `search.plugins.actions.items`. Each item has a `name`,
an `icon` (Material Symbols), a `command` (an argument list, never run through
a shell) and `dangerous`. A dangerous action (reboot, power off) is refused,
with the reason shown, until you turn on `actions.enableDangerous`.

```json
{ "name": "Restart Wi-Fi", "icon": "wifi", "command": ["nmcli", "radio", "wifi", "off"], "dangerous": false }
```

`ano doctor` warns when a provider is on but its tool is missing.

## Productivity

Settings → Sidebars → **Productivity**.

- **Notepad** (`notepad.enable`): tabs of text in the right sidebar, saved
  as you type to `~/.local/share/anoshell/notepad.json`. A tab is named after
  its first line.
- **To-do** (`todo.enable`): a list kept in a todo.txt (one task per line,
  `x <date> ` in front when it's done). The file is `todo.file`, or
  `~/.local/share/anoshell/todo.txt` by default. Edit it in any editor and the
  sidebar updates at once; changes made in the sidebar are written straight
  back. Tick a task and it strikes through, then folds under **Done**;
  double-click a task to edit it; remove one and **Undo** brings it back for a
  few seconds. todo.txt markup shows as chips: `(A) ` priority (A red, B
  tertiary), `due:2026-10-25` (or `due:today`, `due:tomorrow`, `due:fri`),
  `+project` and `@context`.
- **Pomodoro and stopwatch** (`pomodoro.enable`): focus, short break and long
  break (`focusMinutes`, `breakMinutes`, `longBreakMinutes`,
  `cyclesBeforeLongBreak`), with a notification at each change. It is separate
  from Focus Time: it doesn't turn on Do Not Disturb or track apps.
- **Sticky note** (`stickyNotes.enable`): a note on the desktop, kept in
  `~/.local/share/anoshell/sticky.md`. With **click-through**
  (`stickyNotes.clickThrough`), clicks go to the windows below, except on its
  pin, which turns click-through off again. Also
  `qs -c ano ipc call stickyNote clickThrough`. Its place and size are
  `stickyNotes.x`, `y`, `width` and `height`.

## Password prompt (polkit)

When an app needs permission (pkexec, mounting a disk, a system setting),
AnoShell asks for your password on the focused screen: Enter authenticates,
Esc or Cancel says no. **Details** shows the polkit action, its description
and vendor (from `pkaction`) and, for pkexec, the full command waiting to run
and what started it.

Settings → General → Password prompt:

- `polkit.enable` (on): polkit takes one agent per session, so if another
  one (hyprpolkitagent, polkit-gnome…) is already running, AnoShell's stays
  quiet and the card says so. AnoShell never stops other agents; stop yours,
  then press **Retry**.
- `polkit.blur` (off): blur behind the prompt. Off, the prompt uses the
  namespace `quickshell:polkitPlain`, which the bundled Hyprland and niri
  configs leave unblurred (add the same rule to your own config if you don't
  use the bundled one).

## Clipboard history

Alt+V opens the clipboard history (cliphist). Entries show what they are:

- **Images** as thumbnails at their own shape, with type, size and weight.
- **Copied files** (from a file manager) as tiles: image files and a frame
  from each video (with a play badge), an icon for audio, PDFs and the rest.
- **Colours** (`#rrggbb`) with a swatch.

Previews are made only for rows in view, two at a time, under
`/tmp/quickshell-anoshell/media/cliphist` (cleared when the shell starts;
an image's preview goes when its entry does). Space, or the corner button,
opens a large preview; for a video, **Play** opens it in your default player.

**Pins** (the pin button, or Ctrl+P) keep an entry at the top, apart from the
history in `~/.local/share/anoshell/clipboard-pins.json` (pinned images are
copied to `clipboard-pins/` beside it), so clearing the history keeps them.
Unpinning removes the copy.

Keys: ↑↓ select, Enter pastes, Space previews (search empty), Ctrl+P pins
or unpins, Delete removes the selected entry or unpins a pin (search empty);
Esc closes the preview, then the panel. Right-click copies without pasting.

**Passwords stay out.** A copy marked sensitive (a password manager's copy,
or `wl-copy --sensitive`) is never stored: wl-paste passes it on as
`CLIPBOARD_STATE=sensitive` and `cliphist store` (0.7.0) skips it. This needs
the bundled watch lines (`wl-paste --watch … cliphist store`), or your own,
to run `cliphist store` with the environment intact.

## Screenshots

Print (screen), Shift+Print or Super+Shift+S (region), Ctrl+Print (the focused
window), or `qs -c ano ipc call screenshot region|window|screen`, and
`screenshot delayed <mode> <seconds>` for a countdown. On Hyprland they use
slurp and grim; on niri, niri's own screenshot actions. The image goes on the
clipboard (`screenshot.copyOnCapture`) and a card shows it: Copy, Save (to
`screenshot.saveDir`, or Pictures/Screenshots), Edit (satty, else swappy),
Delete, Close. It leaves after `screenshot.previewSeconds` (0 = stays) unless
the pointer is on it; `screenshot.onTimeout` then keeps the temp file, saves
it or deletes it. The card sits at `screenshot.previewEdge`.

## Screen time

`screenTime.enable` (Settings → Sidebars → Productivity) counts how long each
app, and each of its window titles, is focused: every 15 s the focused window
gets 15 s, unless there has been no input for `screenTime.idleSeconds`
(default 120) with nothing playing, or the screen is locked. Idle inhibitors
are ignored, so a forgotten "keep awake" toggle doesn't count the night.
anod keeps one file per day in `~/.local/state/anoshell/screentime/` (0600,
never sent anywhere) and deletes days older than `screenTime.keepDays`
(default 30). The sidebar card shows today's total, the top apps (click one
for its top titles) and the last 7 days.
