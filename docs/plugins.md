# Launcher plugins

Extra results in the launcher, beyond the built-in providers (calculator,
emoji, packages, actions, schemes, looks). A plugin is a folder with a
`plugin.json` and a QML file. Every plugin is off until you turn it on in
**Settings → Modules → App Launcher** (or with **Turn on** in **Settings → Hub
→ Plugins**); the ones that are on are listed by id in `search.userPlugins`.
Plugins load only while the launcher is open.

| Where | |
|---|---|
| `plugins/<id>/` in the shell | bundled |
| `~/.config/anoshell/plugins/<id>/` | yours; the same id overrides a bundled one |
| `~/.config/anoshell/plugins/<id>~<n>/` | installed from a catalog (a fresh folder per version) |

Bundled: **Clipboard history** (`cb ` and part of something you copied;
Enter copies it again; needs `cliphist`).

Folders are watched: a plugin you add or edit is picked up without a restart.
One whose manifest is invalid or whose QML doesn't compile is listed in
Settings with its error and can't be turned on.

## plugin.json

```json
{
  "id": "clipboard",
  "name": "Clipboard history",
  "description": "Shown in Settings and the Hub",
  "author": "you",
  "version": "1.0.0",
  "entry": "main.qml",
  "prefix": "cb ",
  "minLength": 2,
  "position": "top"
}
```

| Key | |
|---|---|
| `id` | optional; must match the folder name (before any `~<n>`) |
| `name` | required |
| `entry` | the QML file in the folder (default `main.qml`) |
| `prefix` | the plugin answers only queries that start with it, and gets the rest |
| `minLength` | without a prefix: the shortest query it answers (default 2) |
| `position` | `top` (default): above your apps; `bottom`: below them, so Enter on a plain word still opens the app |

## The QML

The root object (any `QtObject` or `Item`) can have:

| Property | Set by | |
|---|---|---|
| `active: bool` | the launcher | the query is for this plugin |
| `query: string` | the launcher | the query without the prefix; `""` while not active |
| `results: var` | the plugin | a list of results, read while active |

A result is `{ title, subtitle?, icon?, text?, run }`:

- `title` (required) and `subtitle` (defaults to the plugin's name);
- `icon`: a Material Symbols name (default `extension`), or `text`: a glyph
  shown instead (an emoji);
- `run()`: called on Enter or a click. The launcher closes after it, unless it
  returns `false`. If it throws, the launcher stays open and shows the error.

At most 20 results per plugin are shown; entries without a title are dropped.

```qml
import QtQuick
import qs.services

QtObject {
    property bool active
    property string query
    readonly property var results: active ? [{
        icon: "language", title: `Search the web for “${query}”`,
        run: () => Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent(query))
    }] : []
}
```

A plugin can import the shell's modules (`qs.services`, `qs.modules.common`)
and run processes. **It runs with the shell's rights, unsandboxed**: install
only plugins you trust. From a catalog, the Hub checks the files first and
asks (see [Hub](hub.md)).
