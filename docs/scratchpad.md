# Scratchpad & Pins

One panel for the small things: your notes, to-do list, clipboard and the next
two weeks of events in tabs, the commands you run often pinned beside them, and
a prompt bar that takes a note, a to-do, a command or a question. It grows out
of the pill, on whichever edge the pill sits; with the pill off it opens as a
card on that edge.

Off by default: turn it on in **Settings → Sidebars → Productivity → Scratchpad
& Pins** (`scratchpad.enable`). It uses the notepad and the to-do list even
when their own switches are off.

## Opening it

- **Super+Y** in the bundled keybinds.
- `qs -c ano ipc call scratchpad toggle` (also `show`, `close`).
- A pill click: set `anoSpot.actions.leftClick`, `rightClick` or `middleClick`
  to `"scratchpad"`.

Esc closes it. Ctrl+Tab and Ctrl+Shift+Tab move between the tabs.

## The tabs

| Tab | What it shows | Clicking a row |
|---|---|---|
| Notes | The notepad's tabs (the same notes as the sidebar card) | — (edit in place) |
| To-do | The to-do list, kept in `todo.txt` | the sidebar card's own controls |
| Clipboard | Clipboard pins first, then the history | copies it |
| Calendar | Events in the next two weeks | copies "when · title" |

## Pinned commands

The right side lists your pinned commands. Click one to run it, Shift+click to
copy it. Each pin remembers where it runs, which you pick when pinning it and
can switch with its icon:

- **In a terminal**: your default terminal (Settings → Default apps) runs it
  and stays open afterwards with its exit code, until you press Enter. The
  scratchpad closes so the terminal has the keyboard.
- **In the background**: it runs on its own (as its own systemd scope where
  there is one, so it outlives the shell). If it fails, a notification shows
  the exit code and the end of its error output.

Pins are kept in `~/.local/share/anoshell/scratchpad-pins.json`. A command is
handed to `sh -c` as a single argument and nothing else is added to it.

## The prompt bar

| Type | Does |
|---|---|
| `>command` | Pins the command, asking whether it runs in a terminal or in the background |
| `>>command` | Runs the command now, in the background |
| `t text` | Adds a to-do (`due:tomorrow`, `+project`, `(A)` work as in the to-do list) |
| `? text` | Searches the web with the launcher's web search (`? g text`: only Google, and so on for each engine key) |
| `?? text` | Asks the AI chat's current model (the same conversation as the left sidebar); the answer shows over the tab with Copy and Save as note. Without a model or a key it says so |
| anything else | Is added to the end of the current note |

## With text recognition

Super+Shift+X copies the text in a region and shows it on a card
([extras](extras.md#text-recognition-ocr)); its **Add to note** adds the
text to the current note and **Pin** keeps it with the clipboard pins, which
the Clipboard tab lists first.

## What it needs

`wl-clipboard` (copying), `libnotify` (`notify-send`, the failure notices), a
terminal for terminal pins, and for `??` an AI provider set up in the left
sidebar. `ano doctor` checks the first two when the scratchpad is on.
