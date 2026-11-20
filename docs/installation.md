# Installation

## One line

```sh
curl -fsSL https://anoshell.anorebel.net/i | bash        # stable (main)
curl -fsSL https://anoshell-dev.anorebel.net/i | bash    # development (dev)
```

`/i` is short for `/install.sh` (both work). On a terminal it opens a small
wizard (the `ano` from the release, checksum-verified) that asks what to do,
then runs the installer:

1. **Dependencies:** the required programs you're missing, from your package
   manager (pacman, apt, dnf or zypper), after you confirm, with `sudo`.
   Anything your distribution's own repositories don't have is listed with
   where to get it; no third-party repository (COPR, PPA, OBS) is added for you.
2. **The shell:** a git checkout at `~/.config/quickshell/ano` (`main`, `dev`,
   or a release tag with `--version v0.1.0`). An existing checkout is
   fast-forwarded, or left alone if it has your changes.
3. **anod and `ano`** in `~/.local/bin` (built with Go when it's installed,
   otherwise the release binaries) and the AnoShell Settings launcher.
4. **Compositors:** for each one installed (Hyprland, niri, sway, mango,
   labwc, Umbriel), whether to use AnoShell's bundled config. It is linked from
   the checkout; your own config is moved aside to `<file>.ano-backup-<time>`
   and the uninstaller puts it back. The default is no: then add `ano start`
   to your compositor's startup (step 3 below).
5. `ano doctor`.

Without a terminal (or with any flag) it asks nothing and installs no packages
unless you say so:

```sh
curl -fsSL https://anoshell.anorebel.net/i | bash -s -- --yes --compositor niri
```

| Flag | |
|---|---|
| `--channel stable\|dev` | which branch (default: the site's) |
| `--version vX.Y.Z` | a tagged release instead |
| `--dir PATH` | where the checkout goes |
| `--yes` | install missing dependencies without asking |
| `--no-deps` | skip the dependency step |
| `--compositor NAME` | use the bundled config for NAME (repeatable) |
| `--no-compositor` | don't ask about compositor configs |
| `--no-wizard` | plain prompts instead of the wizard |
| `--dry-run` | print the steps, change nothing |

The scripts are in the repository too (`anod/installer/install.sh`,
`uninstall.sh`), and `ano setup wizard install` / `ano setup script install …`
run the copies built into `ano`. What the installer changes outside the checkout
is listed in `~/.local/state/anoshell/install-manifest` for the uninstaller.

The rest of this page is the same by hand.

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

One line in your compositor's startup does it:

```sh
ano start
```

It runs anod, which starts the shell (`qs -c ano`), restarts it after crashes
and raises its open-file limit. `ano stop` stops both, `ano restart` restarts
them, and `ano start -d` starts them in the background from a terminal.

The bundled compositor configs already use it (and start just the shell when
`ano` isn't installed):

- **Hyprland:** `external/hyprland/hyprland.lua`.
- **niri:** `external/niri/ano.kdl` (copy or symlink it to
  `~/.config/niri/config.kdl`; it needs niri ≥ 26.04).
- **sway:** `external/sway/ano.conf` → `~/.config/sway/config` (sway ≥ 1.12).
- **mango:** `external/mango/ano.conf` → `~/.config/mango/config.conf`
  (mango ≥ 0.18).
- **labwc:** `external/labwc/` → `~/.config/labwc/` (`rc.xml`, `autostart`,
  `shutdown`, `environment`; labwc ≥ 0.20).
- **Umbriel:** `external/umbriel/ano.toml` → `~/.config/umbriel/config.toml`
  (umbriel ≥ 0.1).

Each file's header says how to check it
([compositors](compositors.md#bundled-configs)). Their Super+Ctrl+R runs
`ano restart`.

Your own compositor config: `exec-once = ano start` (Hyprland),
`spawn-at-startup "ano start"` (niri), `exec ano start` (sway). If its startup
`PATH` lacks `~/.local/bin`, give the full path. To run just the shell
without anod: `qs -c ano`, after raising the open-file limit
(`ulimit -Sn 65536 2>/dev/null || ulimit -Sn $(ulimit -Hn); exec qs -c ano`).

`install.sh` also adds **AnoShell Settings** to your app launcher
(`~/.local/share/applications/anoshell-settings.desktop`), which opens the
standalone Settings window.

## 4. Check the install

```sh
ano doctor
```

It checks required and optional dependencies, your config, the sockets, the
last crash and competing wallpaper rotators, and exits 1 on any failure.

## Uninstalling

```sh
curl -fsSL https://anoshell.anorebel.net/u | bash    # or: ano setup uninstall
```

It asks first (on a terminal, as a small wizard), then:

- stops anod and the shell;
- undoes AnoShell's changes to your own files: the include lines and moved
  binds in your Hyprland/niri config (`ano keybinds migrate --revert`), its
  marked blocks in kitty, Ghostty, foot, Alacritty and your shell's rc file, its
  block in `gtk.css` (a `gtk.css` that was a link becomes the link again), its
  Qt colour scheme lines, and the share-picker line in `xdph.conf`;
- resets the cursor and icon theme settings that point at AnoShell's generated
  themes, then removes those themes;
- deletes the files only AnoShell writes (`ano-managed.*` compositor includes;
  a sway include you added by hand keeps its file until you remove the line;
  the hyprtoolkit, Kvantum and QtQuick Controls files it generated);
- puts back the compositor configs the installer replaced;
- removes the checkout (asking first if it has local changes or commits), anod,
  `ano`, the Settings launcher and the caches.

Your settings and history stay (`~/.config/anoshell`, `~/.local/state/anoshell`,
`~/.local/share/anoshell`), so installing again picks them up; `--purge` removes
them too, asking for each. Never touched: your `*.ano-backup*` and `*.bak-*`
copies (listed at the end; they are yours to keep or delete), `~/.face`,
downloaded wallpapers, and other apps' data. It also lists compositor files that
still start AnoShell. Flags: `--purge`, `--yes` (needed without a terminal),
`--dir`, `--dry-run`.

A package install (AUR) is removed with the package manager; the uninstaller
still undoes the changes to your files and leaves `/usr` alone.

## Updating

```sh
ano setup update      # fast-forward the checkout, rebuild, migrate the config, reload
```

`ano setup` with no arguments, in a terminal, opens an interactive menu for the
same actions. On another machine where `ano` is already installed,
`ano setup install` clones the shell into `~/.config/quickshell/ano` if it
isn't there, builds anod and `ano`, and runs `ano doctor`. See
[The `ano` CLI](cli.md) for every option.
