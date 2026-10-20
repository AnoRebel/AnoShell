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
