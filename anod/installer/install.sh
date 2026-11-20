#!/usr/bin/env bash
# AnoShell installer. Plain bash; `ano setup` (Bubble Tea) is a front end that
# runs this same script (embedded in `ano`) with the flags below.
#
#   curl -fsSL https://anoshell.anorebel.net/i | bash          # stable (main)
#   curl -fsSL https://anoshell-dev.anorebel.net/i | bash      # development (dev)
#   bash install.sh [flags]
#
# Steps, each asked about on a terminal (answers default to the safe choice):
#   1. dependencies: the missing ones from your package manager (pacman, apt,
#      dnf, zypper), after you confirm; anything your repos don't have is listed
#      with where to get it (no third-party repos are added).
#   2. the shell: a git checkout at ~/.config/quickshell/ano (main, dev or a tag).
#   3. anod + ano into ~/.local/bin (built with Go, or the checksum-verified
#      release binaries), and the AnoShell Settings launcher.
#   4. compositors: for each one installed, optionally its bundled AnoShell
#      config (symlinked; whatever was there is moved aside and restored by
#      uninstall.sh). Default: no.
#   5. `ano doctor`.
# Everything it changes outside the checkout is listed in
# $XDG_STATE_HOME/anoshell/install-manifest for uninstall.sh.
#
# Flags:
#   --channel stable|dev   which branch (default: the site's channel, else stable)
#   --version vX.Y.Z       a tagged release instead of a channel
#   --dir PATH             checkout location (default ~/.config/quickshell/ano)
#   --yes                  answer yes to installing dependencies (compositor configs stay opt-in)
#   --no-deps              skip the dependency step
#   --compositor NAME      install the bundled config for NAME (repeatable:
#                          hyprland, niri, sway, mango, labwc, umbriel)
#   --no-compositor        don't ask about compositor configs
#   --no-wizard            plain prompts even on a terminal (no `ano setup` wizard)
#   --dry-run              print what would be done, change nothing
set -euo pipefail

# The docs site that served this script sets its channel on the next line.
ANO_SITE_CHANNEL=stable

REPO="${ANO_REPO:-https://github.com/AnoRebel/AnoShell.git}"
RELEASES="https://github.com/AnoRebel/AnoShell/releases"
channel="" version="" dir="" yes=0 deps=1 compositors=() ask_compositors=1 wizard=1 dry=0 flagged=0

usage() { sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null || true; }
while (( $# )); do
    flagged=1
    case "$1" in
        --channel) channel="${2:-}"; shift ;;
        --version) version="${2:-}"; shift ;;
        --dir) dir="${2:-}"; shift ;;
        --yes|-y) yes=1 ;;
        --no-deps) deps=0 ;;
        --compositor) compositors+=("${2:-}"); shift ;;
        --no-compositor) ask_compositors=0 ;;
        --no-wizard) wizard=0 ;;
        --dry-run) dry=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "install.sh: unknown flag $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done
channel="${channel:-${ANO_SITE_CHANNEL:-stable}}"
case "$channel" in stable|dev) ;; *) echo "install.sh: --channel is stable or dev" >&2; exit 2 ;; esac
[[ -z "$version" || "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || { echo "install.sh: --version looks like v0.1.0" >&2; exit 2; }
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
dir="${dir:-$XDG_CONFIG_HOME/quickshell/ano}"
manifest="$XDG_STATE_HOME/anoshell/install-manifest"

# ── Output and prompts ────────────────────────────────────────────────────
if [[ -t 1 ]]; then B=$'\e[1m' D=$'\e[2m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' N=$'\e[0m'; else B='' D='' G='' Y='' R='' N=''; fi
step() { printf '\n%s==>%s %s%s%s\n' "$G" "$N" "$B" "$*" "$N"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '%s  ! %s%s\n' "$Y" "$*" "$N" >&2; }
die() { printf '%s  ✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
# Prompts read the terminal even when this script arrives on stdin (curl | bash).
tty_ok=0; { exec 3</dev/tty; } 2>/dev/null && tty_ok=1
ask() { # ask "question" default(y|n) → 0 for yes
    local q="$1" def="$2" a
    # No terminal: nothing is agreed to (pass --yes to install dependencies unattended).
    if (( ! tty_ok )); then printf '    %s → no (no terminal to ask on)\n' "$q"; return 1; fi
    printf '    %s [%s] ' "$q" "$([[ $def == y ]] && echo Y/n || echo y/N)" > /dev/tty
    IFS= read -r a <&3 || a=""
    a="${a:-$def}"; [[ "$a" =~ ^[Yy] ]]
}
run() { # run argv (printed under --dry-run)
    if (( dry )); then printf '    %s$ %s%s\n' "$D" "$*" "$N"; return 0; fi
    "$@"
}
have() { command -v "$1" >/dev/null 2>&1; }
record() { # record kind path [backup] for uninstall.sh
    (( dry )) && return 0
    mkdir -p "$(dirname "$manifest")"
    printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$manifest"
}
fetch() { # fetch URL FILE
    if have curl; then curl -fsSL -o "$2" "$1"; elif have wget; then wget -qO "$2" "$1"; else die "curl or wget is needed"; fi
}

[[ "$(uname -s)" == Linux ]] || die "AnoShell runs on Linux (Wayland)"
[[ $EUID -ne 0 ]] || die "run this as your user, not root (it asks for sudo when installing packages)"

# ── The wizard: on a terminal with no flags, `ano setup` asks the questions
#    and runs this same script (embedded in that `ano`) with the answers. ────
if (( wizard && tty_ok && ! flagged && ! dry )) && [[ -z "${ANO_FROM_WIZARD:-}" && -t 1 ]]; then
    case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *) arch="" ;; esac
    if [[ -n "$arch" ]] && (have curl || have wget) && have sha256sum && have tar; then
        tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
        rel="${version:-channel-$channel}"
        if fetch "$RELEASES/download/$rel/anoshell-linux-$arch.tar.gz" "$tmp/a.tar.gz" 2>/dev/null \
            && fetch "$RELEASES/download/$rel/SHA256SUMS" "$tmp/SHA256SUMS" 2>/dev/null \
            && (cd "$tmp" && grep " anoshell-linux-$arch.tar.gz\$" SHA256SUMS | sed "s| anoshell-linux-$arch.tar.gz\$| a.tar.gz|" | sha256sum -c --status) \
            && tar -xzf "$tmp/a.tar.gz" -C "$tmp" 2>/dev/null; then
            ano_bin="$(find "$tmp" -type f -name ano -perm -u+x | head -1)"
            if [[ -n "$ano_bin" ]]; then
                # The wizard needs the terminal as its stdin, not this piped script.
                ANO_FROM_WIZARD=1 "$ano_bin" setup wizard install --channel "$channel" ${version:+--version "$version"} < /dev/tty && exit 0
                rc=$?; [[ $rc -eq 130 ]] && exit 130   # cancelled in the wizard
                warn "the wizard exited ($rc); continuing with plain prompts"
            fi
        else
            note "${D}(no release binaries for the wizard; plain prompts)${N}"
        fi
    fi
fi

printf '%sAnoShell installer%s  %s%s%s\n' "$B" "$N" "$D" "${version:-$channel channel}" "$N"
(( dry )) && note "dry run: nothing is changed"

# ── 1. Dependencies ───────────────────────────────────────────────────────
# command → package per manager (pacman apt dnf zypper); checked against the
# repos before installing, so a name a distro lacks is only listed.
deps_table=(
    "qs        quickshell   quickshell      quickshell      quickshell"
    "awww      awww         awww            awww            awww"
    "matugen   matugen      matugen         matugen         matugen"
    "jq        jq           jq              jq              jq"
    "brightnessctl brightnessctl brightnessctl brightnessctl brightnessctl"
    "nmcli     networkmanager network-manager NetworkManager NetworkManager"
    "cliphist  cliphist     cliphist        cliphist        cliphist"
    "wl-copy   wl-clipboard wl-clipboard    wl-clipboard    wl-clipboard"
    "curl      curl         curl            curl            curl"
    "openssl   openssl      openssl         openssl         openssl"
    "ip        iproute2     iproute2        iproute         iproute2"
    "notify-send libnotify  libnotify-bin   libnotify       libnotify-tools"
    "python3   python       python3         python3         python3"
    "xdg-open  xdg-utils    xdg-utils       xdg-utils       xdg-utils"
    "git       git          git             git             git"
)
where_to_get() {
    case "$1" in
        quickshell) echo "quickshell: https://quickshell.org/docs/v0.3.1/guide/install-setup/ (Fedora COPR errornointernet/quickshell, Ubuntu PPA avengemedia/danklinux, openSUSE OBS home:AvengeMedia:danklinux, or build)" ;;
        awww) echo "awww: https://codeberg.org/LGFae/awww" ;;
        matugen) echo "matugen: https://github.com/InioX/matugen (releases, or cargo install matugen)" ;;
        cliphist) echo "cliphist: https://github.com/sentriz/cliphist" ;;
        *) echo "$1" ;;
    esac
}
if (( deps )); then
    step "Dependencies"
    pm="" col=0
    if have pacman; then pm=pacman col=1; elif have apt-get; then pm=apt col=2; elif have dnf; then pm=dnf col=3; elif have zypper; then pm=zypper col=4; fi
    missing=()
    for row in "${deps_table[@]}"; do
        read -r -a f <<< "$row"
        have "${f[0]}" || missing+=("${f[$col]:-${f[1]}}")
    done
    if (( ${#missing[@]} == 0 )); then
        note "all required programs are installed"
    elif [[ -z "$pm" ]]; then
        warn "no supported package manager (pacman, apt, dnf, zypper); install these yourself:"
        for p in "${missing[@]}"; do note "$(where_to_get "$p")"; done
    else
        avail=() unavail=()
        for p in "${missing[@]}"; do
            case "$pm" in
                pacman) pacman -Si "$p" >/dev/null 2>&1 ;;
                apt) [[ -n "$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ && $2 != "(none)"')" ]] ;;
                dnf) dnf -q info "$p" >/dev/null 2>&1 ;;
                zypper) zypper -q info "$p" 2>/dev/null | grep -q "^Name" ;;
            esac && avail+=("$p") || unavail+=("$p")
        done
        if (( ${#avail[@]} )); then
            note "missing, from $pm: ${avail[*]}"
            if (( yes )) || ask "Install them with sudo $pm?" y; then
                case "$pm" in
                    pacman) run sudo pacman -S --needed "${avail[@]}" ;;
                    apt) run sudo apt-get install -y "${avail[@]}" ;;
                    dnf) run sudo dnf install -y "${avail[@]}" ;;
                    zypper) run sudo zypper install -y "${avail[@]}" ;;
                esac || warn "the package install failed; continuing (ano doctor will list what's missing)"
            else
                note "skipped"
            fi
        fi
        if (( ${#unavail[@]} )); then
            warn "not in your $pm repos (no third-party repos are added):"
            for p in "${unavail[@]}"; do note "$(where_to_get "$p")"; done
        fi
    fi
    note "${D}optional features list their own programs in \`ano doctor\`${N}"
fi
have git || die "git is needed to get the shell"

# ── 2. The shell checkout ─────────────────────────────────────────────────
step "AnoShell at $dir"
ref="${version:-$([[ $channel == dev ]] && echo dev || echo main)}"
if [[ -f "$dir/shell.qml" && -d "$dir/.git" ]]; then
    if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
        warn "it has local changes; left as it is (update it with \`ano setup update\`)"
    elif [[ -n "$version" ]]; then
        run git -C "$dir" fetch --tags --quiet origin && run git -C "$dir" -c advice.detachedHead=false checkout --quiet "$version"
    else
        run git -C "$dir" fetch --quiet origin "$ref" && run git -C "$dir" checkout --quiet "$ref" && run git -C "$dir" merge --ff-only --quiet "origin/$ref" \
            || warn "couldn't fast-forward to origin/$ref; left as it is"
    fi
elif [[ -e "$dir" ]]; then
    die "$dir exists but isn't an AnoShell checkout; move it aside and run this again"
else
    run mkdir -p "$(dirname "$dir")"
    if [[ -n "$version" ]]; then
        run git -c advice.detachedHead=false clone --quiet --branch "$version" -- "$REPO" "$dir"
    else
        run git clone --quiet --branch "$ref" -- "$REPO" "$dir"
    fi
    record checkout "$dir"
fi

# ── 3. anod + ano ─────────────────────────────────────────────────────────
step "anod and the ano command"
if (( dry )); then
    run env ANO_CHANNEL="$channel" ${version:+ANO_RELEASE="$version"} "$dir/anod/install.sh"
else
    env ANO_CHANNEL="$channel" ${version:+ANO_RELEASE="$version"} "$dir/anod/install.sh" || die "installing anod failed"
fi
bin="${PREFIX:-$HOME/.local}/bin"
record file "$bin/ano"; record file "$bin/anod"
record file "${XDG_DATA_HOME:-$HOME/.local/share}/applications/anoshell-settings.desktop"

# ── 4. Compositor configs ─────────────────────────────────────────────────
# name → command, then bundled source → target pairs (relative to external/
# and $XDG_CONFIG_HOME). Hyprland's config requires Ano.custom.* and runs
# Ano/scripts, so ~/.config/hypr/Ano is the bundled directory.
declare -A comp_cmd=([hyprland]=Hyprland [niri]=niri [sway]=sway [mango]=mango [labwc]=labwc [umbriel]=umbriel)
comp_files() {
    case "$1" in
        hyprland) echo "hyprland/hyprland.lua hypr/hyprland.lua"; echo "hyprland hypr/Ano" ;;
        niri) echo "niri/ano.kdl niri/config.kdl" ;;
        sway) echo "sway/ano.conf sway/config" ;;
        mango) echo "mango/ano.conf mango/config.conf" ;;
        labwc) for f in rc.xml autostart shutdown environment; do echo "labwc/$f labwc/$f"; done ;;
        umbriel) echo "umbriel/ano.toml umbriel/config.toml" ;;
    esac
}
link_bundled() { # link_bundled NAME
    local src dst stamp; stamp="$(date +%Y%m%d-%H%M%S)"
    while read -r src dst; do
        src="$dir/external/$src"; dst="$XDG_CONFIG_HOME/$dst"
        [[ -e "$src" ]] || { warn "missing in the checkout: $src"; continue; }
        if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then note "$dst already links to the bundled one"; continue; fi
        run mkdir -p "$(dirname "$dst")"
        if [[ -e "$dst" || -L "$dst" ]]; then
            run mv -- "$dst" "$dst.ano-backup-$stamp"
            note "your $dst is kept as $dst.ano-backup-$stamp"
            record compositor "$dst" "$dst.ano-backup-$stamp"
        else
            record compositor "$dst"
        fi
        run ln -s -- "$src" "$dst"
    done < <(comp_files "$1")
}
if (( ${#compositors[@]} )) || (( ask_compositors )); then
    step "Compositor configs"
    if (( ${#compositors[@]} )); then
        for c in "${compositors[@]}"; do
            [[ -n "${comp_cmd[$c]:-}" ]] || { warn "unknown compositor $c"; continue; }
            link_bundled "$c"
        done
    else
        found=0
        for c in hyprland niri sway mango labwc umbriel; do
            have "${comp_cmd[$c]}" || continue
            found=1
            if ask "Use AnoShell's bundled $c config? (yours is moved aside and restored by uninstall.sh)" n; then
                link_bundled "$c"
            else
                note "$c: add \`ano start\` to its startup yourself (docs: Installation)"
            fi
        done
        (( found )) || note "no supported compositor found (Hyprland, niri, sway, mango, labwc, Umbriel)"
    fi
fi

# ── 5. Check ──────────────────────────────────────────────────────────────
step "Check"
if (( dry )); then note "(dry run: ano doctor skipped)"
elif have ano || [[ -x "$bin/ano" ]]; then
    "${bin}/ano" doctor || warn "ano doctor reported problems: see above"
fi
printf '\n%sDone.%s Start it with %sano start%s (your compositor'"'"'s startup does it with the bundled configs).\n' "$G" "$N" "$B" "$N"
printf '%sUninstall:%s curl -fsSL https://anoshell.anorebel.net/u | bash   (or ano setup uninstall)\n' "$D" "$N"
