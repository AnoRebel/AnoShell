# Installation

AnoShell is a Quickshell config, so installing it means putting the repository
where Quickshell looks for configs, then (optionally) installing anod and the
`ano` CLI.

## 1. Clone the shell

```sh
git clone https://github.com/AnoRebel/AnoShell.git ~/.config/quickshell/ano
```

Quickshell finds it as the config `ano`. Install Quickshell and the packages
listed under *External Packages* in the [README](../README.md) (the required
ones, plus any recommended or optional ones for the features you want).

Clone the `dev` branch instead (`git clone -b dev …`) to follow development.

## 2. Install anod and the `ano` CLI

```sh
~/.config/quickshell/ano/anod/install.sh          # builds anod + ano into ~/.local/bin
~/.config/quickshell/ano/anod/install.sh --test   # runs the Go tests first
```

Building needs Go ≥ 1.27. Set `PREFIX` to install into `$PREFIX/bin` instead of
`~/.local/bin`. The script tells you when that directory isn't in your `PATH`.

### Prebuilt binaries

Without Go, or with `--prebuilt`, `install.sh` installs prebuilt static
binaries instead (amd64 and arm64):

- from `anod/dist/linux-<arch>/`, if you built them there with `anod/dist.sh`;
- otherwise from a GitHub release: it downloads
  `anoshell-linux-<arch>.tar.gz` and the release's `SHA256SUMS`, and installs
  nothing unless the checksum matches.

### Release channels

| Channel | Release tag | Built from | Pick it with |
|---|---|---|---|
| stable | `channel-stable` | every push to `main`; the default | `ANO_CHANNEL=stable` |
| dev | `channel-dev` | every push to `dev`; the default when the checkout is on `dev` | `ANO_CHANNEL=dev` |
| a version | `vX.Y.Z` | a pushed version tag | `ANO_RELEASE=vX.Y.Z` |

`channel-stable` and `channel-dev` are rolling: each push moves the tag and
replaces the tarballs. `ANO_RELEASE_URL` points the download at a mirror.

```sh
ANO_CHANNEL=dev ~/.config/quickshell/ano/anod/install.sh --prebuilt
ANO_RELEASE=v0.2.0 ~/.config/quickshell/ano/anod/install.sh --prebuilt
```

## 3. Start it with your compositor

The bundled compositor configs start the shell and anod (and skip anod if it
isn't installed):

- **Hyprland:** `external/hyprland/hyprland.lua`. Set `ANOD_SUPERVISE = true`
  in it to let anod start the shell itself and restart it after crashes.
- **niri:** `external/niri/ano.kdl` (copy or symlink it to
  `~/.config/niri/config.kdl`; it needs niri ≥ 26.04). For crash supervision,
  replace its two startup lines with `anod --supervise`.
- **sway:** `external/sway/ano.conf` → `~/.config/sway/config` (sway ≥ 1.12).
- **mango:** `external/mango/ano.conf` → `~/.config/mango/config.conf`
  (mango ≥ 0.18).
- **labwc:** `external/labwc/` → `~/.config/labwc/` (`rc.xml`, `autostart`,
  `shutdown`, `environment`; labwc ≥ 0.20).
- **Umbriel:** `external/umbriel/ano.toml` → `~/.config/umbriel/config.toml`
  (umbriel ≥ 0.1).

For the last four, crash supervision is the same swap as on niri: replace the
two startup lines with `anod --supervise`. Each file's header says how to
check it ([compositors](compositors.md#bundled-configs)).

To start the shell by hand: `qs -c ano`. From your own compositor config,
raise the open-file limit first, as the bundled ones do:
`ulimit -Sn 65536 2>/dev/null || ulimit -Sn $(ulimit -Hn); exec qs -c ano`
(`anod --supervise` does it itself).

`install.sh` also adds **AnoShell Settings** to your app launcher
(`~/.local/share/applications/anoshell-settings.desktop`), which opens the
standalone Settings window.

## 4. Check the install

```sh
ano doctor
```

It checks required and optional dependencies, your config, the sockets, the
last crash and competing wallpaper rotators, and exits 1 on any failure.

## Updating

```sh
ano setup update      # fast-forward the checkout, rebuild, migrate the config, reload
```

`ano setup` with no arguments, in a terminal, opens an interactive menu for the
same actions. On another machine where `ano` is already installed,
`ano setup install` clones the shell into `~/.config/quickshell/ano` if it
isn't there, builds anod and `ano`, and runs `ano doctor`. See
[The `ano` CLI](cli.md) for every option.
