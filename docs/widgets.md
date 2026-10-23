# Desktop widgets

Cards on the desktop, over the wallpaper and under every window, laid out on
a grid in pages. Off by default (`widgets.enable`): until you turn them on in
**Settings → Modules → Desktop widgets** there is no widget surface and no
widget code runs.

## Using them

- **Add**: the Desktop widgets card lists every widget (the bundled ones and
  yours) with **Add**, which puts it on the shown page of the chosen screen at
  the first free spot. A widget that's broken is listed with its error and
  can't be added.
- **Pages**: with more than one page, arrows at the screen's edges and dots at
  the bottom switch them; so do a horizontal drag across a widget, a
  two-finger touchpad swipe, and keys you bind to
  `qs ipc call widgets next` / `prev` / `page N` (the focused screen).
  Only the shown page's widgets exist; the one you leave slides out and is
  destroyed.
- **Grid**: `widgets.cell` (the square, 96 px) and `widgets.gap` (12 px).
  The layer fills the area your bars leave free and centres whole cells in it.
- The layout is kept per screen in `widgets.screens`:
  `{ "eDP-1": { "page": 0, "pages": [[{ "uid", "id", "x", "y", "w", "h", "settings" }]] } }`,
  positions and sizes in cells.

Clicks only reach a widget's card and the page controls; anywhere else they go
to the desktop, and a window over the widgets gets its own clicks. Widgets
pause while the screen is locked or a maximised/fullscreen window covers it.
A tiled window covering the desktop isn't detected (niri doesn't report where
tiled windows are); the window hides them, but their timers keep running.

## Built-in widgets

| Widget | Shows | Settings |
|---|---|---|
| Clock | the time, large, with the date | seconds |
| Profile | your picture (`~/.face`), name, uptime, a status line; lock, settings, power | status, picture |
| Weather | current weather; today's hours and the next days when tall enough (wttr.in, the city from Settings → Bar → Weather) | hourly, daily |
| Media | cover, title, artist, controls (the sidebar's media card) | |
| Photo frame | a picture, or a folder's pictures in turn | path, interval, shuffle |
| System | CPU, memory, battery; CPU temperature and disk use of `/` if you want them | temperature, disk |
| Timer | focus (Pomodoro), stopwatch or countdown: the same timers as the sidebar's | mode |
| To-do | your tasks: the sidebar's to-do and `todo.txt`, both ways | |
| Calendar | the month with your events and holidays | |

The to-do and timer widgets keep their service running while they're placed,
even with the sidebar's to-do or Pomodoro turned off. Until edit mode lands,
per-widget settings are set in `widgets.screens` (the `settings` of each
placed widget).

## Making a widget

A widget is a folder in `~/.config/anoshell/widgets/<id>/` with a manifest and
a QML file. The shell watches the folder: a new widget shows up in the list
without a restart, and editing `widget.json` reloads it. A widget with the id
of a bundled one replaces it.

`widget.json`:

```json
{
  "id": "hello",
  "name": "Hello",
  "description": "Says hello",
  "author": "you",
  "version": "1.0.0",
  "entry": "main.qml",
  "size": { "w": 2, "h": 1 },
  "minSize": { "w": 1, "h": 1 },
  "frame": true,
  "settings": [
    { "key": "greeting", "type": "string", "label": "Greeting", "default": "Hello" }
  ]
}
```

- `id` must match the folder name (or be left out). `name` is required.
- `entry` defaults to `main.qml`; it must be a file in the folder.
- `size` and `minSize` are in grid cells (1–12).
- `frame: true` (the default) draws the card behind your QML, in the active
  look's colours, with a 12 px inset; `false` gives your QML the whole cell
  area and no card.
- `settings` describes the widget's options (`bool`, `int`, `real`, `string`,
  `choice` with `options`); each placed widget's values are in its `settings`.

The entry file's root item fills the card. The host sets two properties on it
if it declares them:

```qml
import QtQuick
import qs.modules.common
import qs.modules.common.widgets

Item {
    property var ctx        // { live, screenName, cell }
    property var settings   // the manifest defaults, overridden by this widget's values

    Timer {
        running: ctx?.live ?? false   // only while the desktop can be seen
        interval: 1000; repeat: true
        onTriggered: ...
    }
    StyledText {
        anchors.centerIn: parent
        text: settings.greeting
        color: Appearance.colors.colOnLayer1
    }
}
```

The shell's own modules are importable (`qs.modules.common` for `Appearance`
and `Config`, `qs.modules.common.widgets`, `qs.services`). Bind every timer,
animation and poll to `ctx.live`: that is what keeps the desktop free when
nobody can see it.

A widget whose manifest is invalid or whose QML doesn't compile is listed with
the error (`Broken.qml:2:38: Cannot assign to non-existent property "colr"`)
and isn't placed; one that fails later shows the reason in its card. The rest
keep working.

`qs ipc call widgets list` prints every widget with its source and errors.
