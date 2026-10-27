# Hub

One place for shareable content: **themes**, **looks**, **desktop widgets**,
**wallpapers** and **rices** (a whole setup). Open it at **Settings → Hub**,
or from a terminal:

```sh
ano hub              # the Hub page
ano hub wallpapers   # on the Wallpapers tab
```

With the shell's Settings overlay open, `ano hub` switches it to the Hub;
otherwise it opens the standalone Settings window. The Hub needs anod (the
AnoShell daemon) running.

## Where items come from

Each tab merges three sources, and every card says which one it is:

| Label | Where | Notes |
|---|---|---|
| Built-in | shipped with AnoShell (`assets/themes/`, `looks/`, `widgets/`) | can't be removed |
| Yours | `~/.config/anoshell/<type>/` (wallpapers: your wallpaper folder) | your files: the Hub never deletes them |
| Installed · *catalog* | installed from a catalog; a receipt in `~/.local/state/anoshell/hub/receipts/` | can be updated and removed |
| *catalog name* | in a catalog, not installed yet | Install |

Theme cards show the theme's colours; wallpapers show the picture; catalog
items show their preview image when the catalog gives one.

## Applying

Installing never changes your setup; **Apply** is a separate button:

- **Themes** switch the colour theme (`appearance.theme.name`, static source).
- **Looks** set `appearance.look`.
- **Wallpapers** go through the normal wallpaper pipeline (colours included).
- **Widgets** are put on the desktop page you're on, at the first free spot
  (desktop widgets must be on). A widget that fails to load shows its error
  instead.
- **Rices**: see below.

## Catalogs

A catalog is a JSON index on an `https://` address that lists items with
their download URL and SHA-256 checksum. Add or remove catalogs at the bottom
of the Hub page (`hub.catalogs` in `config.json`); **Check catalogs** fetches
them. Anyone can publish a catalog, so add only those you trust. Without a
network the Hub shows what was fetched last and says the catalog is offline.

The AnoShell community catalog doesn't exist yet; until it does, the list
starts empty.

### What an install does

1. Downloads the item (https only) and checks it against the catalog's
   SHA-256. A mismatch stops here: nothing is installed.
2. Unpacks it into a staging folder next to its destination, refusing
   symlinks, device files, absolute paths, `..`, too many or too large files,
   and ids other than `a-z`, `0-9` and `-`.
3. For **widgets** (code that runs with your rights, no sandbox), checks the
   files for risky patterns: downloading and running scripts, `sudo` or
   undeclared `pkexec`, writing to `~/.ssh`, `/etc` or your shell config,
   reading the secrets folder, binaries, and network hosts or commands the
   item doesn't declare. You see the author, the catalog, what it declares and
   what the check found, and choose **Install** (or **Install anyway**) or
   **Cancel**. The check is not a security audit, and neither is a catalog's
   review. An update that declares different hosts or commands asks again.
4. Moves it into place in one step and writes the receipt. Widgets get a
   fresh folder per installed version (`<id>~<n>`), so an update never runs
   old cached code.

Nothing from an item is ever executed while installing: there are no install
scripts. If you changed an installed item's files, an update tells you which
ones before replacing them. A catalog can revoke an item: it can't be
installed any more, and installed copies are marked.

## Rices

A rice is a folder in `~/.config/anoshell/rices/<id>/` with a `rice.json`
(name, author, the settings it carries) and optionally its own themes, looks,
widgets, wallpapers and keybinds.

- **Apply rice** first snapshots your current setup, then merges only
  appearance settings (look, theme, bar style, pill position, widget layout
  and similar; never hooks, apps or commands), copies its files and sets its
  wallpaper.
- **Its keybinds** apply only when you tick that switch. A compositor layer
  (raw Hyprland or niri config) is not applied.
- **Undo last rice** puts the snapshot back exactly and deletes the files the
  rice added.
- **Export** saves what you have now as a rice: your appearance settings, your
  own theme or look, and the current wallpaper.

To publish one, `ano hub pack <folder> --url-base https://…/` writes the
archive and prints the catalog entry with its checksum (see
[anod](anod.md) for the CLI and methods).

## Not yet

Launcher plugins and lock screens are listed in the spec as Hub content, but
the shell has no way to load user-made ones yet, so the Hub doesn't offer
them. Wallhaven search for wallpapers is also still to come.
