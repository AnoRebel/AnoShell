#!/usr/bin/env bash
# AnoShell uninstaller. Plain bash; `ano setup uninstall` runs this same script
# (embedded in `ano`).
#
#   curl -fsSL https://anoshell.anorebel.net/u | bash
#   bash uninstall.sh [--purge] [--yes] [--dry-run]
#
# By default it removes the program and keeps your settings:
#   - undoes what AnoShell changed in your own files: its include lines in the
#     Hyprland/niri configs (ano keybinds migrate --revert), its marked blocks in
#     kitty, Ghostty, foot, Alacritty and shell rc files, its block in gtk.css,
#     its Qt colour scheme lines, the share picker line in xdph.conf;
#   - resets the cursor and icon theme settings that point at AnoShell's
#     generated themes, then removes those themes;
#   - deletes files only it writes (ano-managed.* compositor includes, the
#     hyprtoolkit/Kvantum/qtquickcontrols2 files it generated);
#   - puts back the compositor configs the installer replaced;
#   - removes the shell checkout, anod/ano, the Settings launcher and caches.
# --purge also removes your settings and history: $XDG_CONFIG_HOME/anoshell,
# $XDG_STATE_HOME/{anoshell,ano}, $XDG_DATA_HOME/anoshell (asked separately).
# Never touched: your *.ano-backup* / *.bak-* files (listed at the end),
# ~/.face, downloaded wallpapers, the standalone reader's data, ~/.cache/wal.
#
# Flags:
#   --purge     also remove settings, state and history
#   --yes       don't ask (needed when there is no terminal)
#   --dir PATH  the checkout (default ~/.config/quickshell/ano)
#   --dry-run   print what would be done, change nothing
set -euo pipefail

yes=0 purge=0 dry=0 dir=""
while (( $# )); do
    case "$1" in
        --purge) purge=1 ;;
        --yes|-y) yes=1 ;;
        --dir) dir="${2:-}"; shift ;;
        --dry-run) dry=1 ;;
        -h|--help) sed -n '2,/^set -euo/{/^#/s/^# \{0,1\}//p}' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null || true; exit 0 ;;
        *) echo "uninstall.sh: unknown flag $1 (see --help)" >&2; exit 2 ;;
    esac
    shift
done
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
C="$XDG_CONFIG_HOME"
dir="${dir:-$C/quickshell/ano}"
bin="${PREFIX:-$HOME/.local}/bin"
manifest="$XDG_STATE_HOME/anoshell/install-manifest"

if [[ -t 1 ]]; then B=$'\e[1m' D=$'\e[2m' G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' N=$'\e[0m'; else B='' D='' G='' Y='' R='' N=''; fi
step() { printf '\n%s==>%s %s%s%s\n' "$G" "$N" "$B" "$*" "$N"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '%s  ! %s%s\n' "$Y" "$*" "$N" >&2; }
die() { printf '%s  ✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
tty_ok=0; { exec 3</dev/tty; } 2>/dev/null && tty_ok=1
ask() { # ask "question" default → 0 for yes; --yes answers the default
    local q="$1" def="$2" a
    if (( yes )); then [[ "$def" == y ]]; return; fi
    (( tty_ok )) || return 1
    printf '    %s [%s] ' "$q" "$([[ $def == y ]] && echo Y/n || echo y/N)" > /dev/tty
    IFS= read -r a <&3 || a=""
    a="${a:-$def}"; [[ "$a" =~ ^[Yy] ]]
}
run() { if (( dry )); then printf '    %s$ %s%s\n' "$D" "$*" "$N"; return 0; fi; "$@"; }
have() { command -v "$1" >/dev/null 2>&1; }
rmf() { [[ -e "$1" || -L "$1" ]] || return 0; run rm -rf -- "$1"; (( dry )) || note "removed ${1/#$HOME/\~}"; }
# Rewrite a file through a filter (an awk program), only when it changes.
rewrite() { # rewrite FILE AWK-PROGRAM [awk -v args…]
    local f="$1" prog="$2"; shift 2
    [[ -f "$f" ]] || return 0
    local tmp; tmp="$(mktemp)"
    awk "$@" "$prog" "$f" > "$tmp"
    if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
    if (( dry )); then note "would edit ${f/#$HOME/\~}"; rm -f "$tmp"; return 0; fi
    cat "$tmp" > "$f"; rm -f "$tmp"   # in place, through a symlink if it is one
    note "edited ${f/#$HOME/\~}"
}

[[ $EUID -ne 0 ]] || die "run this as your user, not root"
packaged=0
[[ ! -f "$dir/shell.qml" && -d /etc/xdg/quickshell/ano ]] && packaged=1

printf '%sAnoShell uninstaller%s\n' "$B" "$N"
(( dry )) && note "dry run: nothing is changed"
note "removes: the shell, anod/ano, the Settings launcher, AnoShell's changes to your files, its generated themes and caches"
if (( purge )); then note "and (--purge): your AnoShell settings, state and history"
else note "keeps: your settings and history ($C/anoshell, $XDG_STATE_HOME/anoshell, $XDG_DATA_HOME/anoshell); --purge removes them"; fi
(( packaged )) && note "the shell itself came from a package: remove that with your package manager (e.g. sudo pacman -R anoshell)"
if ! (( dry )); then
    (( yes || tty_ok )) || die "no terminal to confirm on: pass --yes (or --dry-run to see the steps)"
    (( yes )) || ask "Uninstall AnoShell?" n || { echo "nothing done"; exit 1; }
fi

# ── 1. Stop it ────────────────────────────────────────────────────────────
step "Stopping AnoShell"
ano_cmd=""
for c in "$bin/ano" "$(command -v ano 2>/dev/null || true)" /usr/bin/ano; do [[ -n "$c" && -x "$c" ]] && { ano_cmd="$c"; break; }; done
if [[ -n "$ano_cmd" ]]; then run "$ano_cmd" stop >/dev/null 2>&1 || true; note "stopped"; else note "ano not found; nothing to stop"; fi

# ── 2. Undo its changes to your files (while settings and ano still exist) ──
step "Undoing AnoShell's changes to your files"
# Keybinds: the include lines and moved binds in hyprland.lua / niri config.kdl.
if [[ -f "$C/anoshell/keybinds-migration.json" ]]; then
    if [[ -n "$ano_cmd" ]]; then
        if (( dry )); then note "would run: ano keybinds migrate --revert"
        elif "$ano_cmd" keybinds migrate --revert; then :
        elif ask "Your compositor config changed since the keybinds were moved. Revert anyway (your edited copy is kept as *.edited-<time>)?" n; then
            "$ano_cmd" keybinds migrate --revert --force || warn "keybinds revert failed: see ~/.config/anoshell/keybinds-migration.json"
        else warn "keybinds left as they are; run \`ano keybinds migrate --revert --force\` before removing ano to undo them"; fi
    else warn "keybinds were moved into ano-managed files but ano is missing: restore your compositor config from its *.ano-backup-<time> copy"; fi
fi
# Marked blocks: terminal colours and looks, prompt lines.
strip_marked='
    skip && ($0 == "[main]" || $0 == "[general]" || index($0, "/anoshell/generated/terminal/")) { next }
    { skip = 0 }
    /^# anoshell-(colors|look|prompt): added by AnoShell/ { skip = 1; next }
    { print }'
for f in "$C/kitty/kitty.conf" "$C/ghostty/config" "$C/ghostty/config.ghostty" "$C/foot/foot.ini" "$C/alacritty/alacritty.toml" \
         "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc" "$C/fish/config.fish"; do
    [[ -f "$f" ]] && grep -q '^# anoshell-\(colors\|look\|prompt\): added by AnoShell' "$f" || continue
    rewrite "$f" "$strip_marked"
    # A terminal config AnoShell created only for its block is empty now: remove
    # it (never a shell rc file).
    case "$f" in *rc|*config.fish) continue ;; esac
    if (( ! dry )) && [[ -f "$f" ]] && ! grep -q '[^[:space:]]' "$f"; then rmf "$f"; fi
done
# gtk.css: drop the colour block; a file that was a link becomes the link again.
for g in "$C/gtk-3.0/gtk.css" "$C/gtk-4.0/gtk.css"; do
    [[ -f "$g" && ! -L "$g" ]] && grep -qF '/* >>> AnoShell colours' "$g" || continue
    body="$(awk 'index($0, "/* >>> AnoShell colours") { skip = 1; next } skip && index($0, "/* <<< AnoShell colours <<< */") { skip = 0; next } !skip { print }' "$g")"
    if [[ "$body" == "/* AnoShell: this file was a link to "* ]] && [[ -z "$(printf '%s\n' "$body" | sed -n '3,$p' | tr -d '[:space:]')" ]]; then
        target="$(printf '%s\n' "$body" | head -1 | sed 's|^/\* AnoShell: this file was a link to ||; s| \*/$||')"
        run rm -f -- "$g"; run ln -s -- "$target" "$g"; note "${g/#$HOME/\~} is a link to $target again"
    elif [[ -z "$(printf '%s' "$body" | tr -d '[:space:]')" ]]; then
        if [[ -f "$g.ano-backup" ]]; then run mv -- "$g.ano-backup" "$g"; note "restored ${g/#$HOME/\~} from its .ano-backup"
        else rmf "$g"; fi
    else
        if (( dry )); then note "would edit ${g/#$HOME/\~}"; else printf '%s\n' "$body" > "$g"; note "edited ${g/#$HOME/\~}"; fi
    fi
done
# Qt: the colour scheme it points qt5ct/qt6ct at.
for q in qt5ct qt6ct; do
    f="$C/$q/$q.conf"
    if [[ -f "$f" ]] && grep -q '^color_scheme_path=.*/anoshell\.conf$' "$f"; then
        rewrite "$f" '/^color_scheme_path=.*\/anoshell\.conf$/ { next } /^custom_palette=true$/ { next } { print }'
    fi
    rmf "$C/$q/colors/anoshell.conf"
done
# Files only AnoShell writes.
rmf "$C/Kvantum/AnoColors"
[[ -f "$C/Kvantum/kvantum.kvconfig" ]] && grep -qx 'theme=AnoColors' "$C/Kvantum/kvantum.kvconfig" \
    && [[ "$(grep -cv '^\(\[General\]\|theme=AnoColors\|\)$' "$C/Kvantum/kvantum.kvconfig")" == 0 ]] && rmf "$C/Kvantum/kvantum.kvconfig"
[[ -f "$C/hypr/hyprtoolkit.conf" ]] && head -1 "$C/hypr/hyprtoolkit.conf" | grep -q '^# Generated by ano applycolor.sh' && rmf "$C/hypr/hyprtoolkit.conf"
# qtquickcontrols2.conf carries no marker: only a file with exactly the keys it writes.
qc="$C/qtquickcontrols2.conf"
if [[ -f "$qc" ]] && grep -qx 'Style=Material' "$qc" \
    && [[ "$(grep -cv '^\(\[Controls\]\|Style=Material\|\[Material\]\|Theme=\(Dark\|Light\)\|Accent=#.*\|Primary=#.*\|Background=#.*\|Foreground=#.*\|\)$' "$qc")" == 0 ]]; then rmf "$qc"; fi
# Share picker (xdph.conf): the line pointing at the checkout.
xd="$C/hypr/xdph.conf"
[[ -f "$xd" ]] && grep -q "custom_picker_binary.*quickshell/ano/scripts/share-picker" "$xd" \
    && rewrite "$xd" 'index($0, "custom_picker_binary") && index($0, "quickshell/ano/scripts/share-picker") { next } { print }'
# Compositor includes it writes. Hyprland's and niri's includes are optional
# (pcall / optional=true) and mango's source_optional; a sway include is the
# user's own line, so that file stays while something includes it.
for m in "$C/hypr/ano-managed.lua" "$C/hypr/ano-managed-binds.lua" "$C/niri/ano-managed.kdl" "$C/niri/ano-managed-binds.kdl" "$C/mango/ano-managed.conf"; do rmf "$m"; done
if [[ -f "$C/sway/ano-managed.conf" ]]; then
    if grep -rqs --exclude=ano-managed.conf 'ano-managed.conf' "$C/sway"; then warn "${C/#$HOME/\~}/sway/ano-managed.conf kept: your sway config includes it (remove the include, then the file)"
    else rmf "$C/sway/ano-managed.conf"; fi
fi
# Cursor and icon theme settings pointing at AnoShell's generated themes.
if have gsettings; then
    for k in cursor-theme icon-theme; do
        v="$(gsettings get org.gnome.desktop.interface "$k" 2>/dev/null | tr -d "'")" || continue
        if [[ "$v" == anoshell* ]]; then run gsettings reset org.gnome.desktop.interface "$k"; note "reset the $k setting (was $v)"; fi
    done
fi
for s in "$C/gtk-3.0/settings.ini" "$C/gtk-4.0/settings.ini"; do
    [[ -f "$s" ]] && grep -q '^gtk-cursor-theme-name *= *anoshell' "$s" && rewrite "$s" '/^gtk-cursor-theme-name *= *anoshell/ { next } { print }'
done
for q in qt5ct qt6ct; do
    [[ -f "$C/$q/$q.conf" ]] && grep -q '^icon_theme=anoshell' "$C/$q/$q.conf" && rewrite "$C/$q/$q.conf" '/^icon_theme=anoshell/ { next } { print }'
done
shopt -s nullglob
for t in "$XDG_DATA_HOME"/icons/anoshell-* "$XDG_DATA_HOME"/icons/.anoshell-*; do rmf "$t"; done
shopt -u nullglob

# ── 3. Compositor configs the installer replaced ──────────────────────────
if [[ -f "$manifest" ]]; then
    step "Compositor configs"
    while IFS=$'\t' read -r kind path backup; do
        [[ "$kind" == compositor ]] || continue
        if [[ -L "$path" && "$(readlink -f "$path")" == "$(readlink -f "$dir")"/* ]]; then
            run rm -f -- "$path"
            if [[ -n "$backup" && ( -e "$backup" || -L "$backup" ) ]]; then run mv -- "$backup" "$path"; note "restored your ${path/#$HOME/\~}"
            else note "removed the link ${path/#$HOME/\~}"; fi
        elif [[ -e "$path" ]]; then
            warn "${path/#$HOME/\~} isn't the installer's link any more; left as it is${backup:+ (your old one: ${backup/#$HOME/\~})}"
        fi
    done < "$manifest"
fi

# ── 4. The program ────────────────────────────────────────────────────────
step "Removing AnoShell"
if (( ! packaged )) && [[ -d "$dir" ]]; then
    keep=0
    if [[ -d "$dir/.git" ]]; then
        if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]] || [[ -n "$(git -C "$dir" log --branches --not --remotes --oneline 2>/dev/null | head -1)" ]]; then
            warn "the checkout has local changes or unpushed commits"
            ask "Remove ${dir/#$HOME/\~} anyway?" n || keep=1
        fi
    fi
    (( keep )) && note "kept ${dir/#$HOME/\~}" || rmf "$dir"
fi
rmf "$bin/ano"; rmf "$bin/anod"
rmf "$XDG_DATA_HOME/applications/anoshell-settings.desktop"
rmf "$XDG_CACHE_HOME/anoshell"; rmf "$XDG_CACHE_HOME/quickshell/anoshell"; rmf "$XDG_CACHE_HOME/anospot"
rmf "/tmp/quickshell-anoshell"
if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    for r in ano anoshell anoSpot anoshell-greeted anoshell-scale-reload; do rmf "$XDG_RUNTIME_DIR/$r"; done
fi

# ── 5. Settings and history (--purge) ─────────────────────────────────────
if (( purge )); then
    step "Settings, state and history"
    for p in "$C/anoshell" "$XDG_STATE_HOME/anoshell" "$XDG_STATE_HOME/ano" "$XDG_DATA_HOME/anoshell"; do
        [[ -e "$p" ]] || continue
        if ask "Remove ${p/#$HOME/\~} ($(du -sh "$p" 2>/dev/null | cut -f1))?" y; then rmf "$p"; else note "kept ${p/#$HOME/\~}"; fi
    done
else
    [[ -f "$manifest" ]] && run rm -f -- "$manifest"
fi

# ── 6. What's left for you ────────────────────────────────────────────────
step "Left alone"
mapfile -t backups < <(find "$C" -maxdepth 3 \( -name '*.ano-backup' -o -name '*.ano-backup-*' -o -name '*.bak-2*' \) 2>/dev/null | sort)
if (( ${#backups[@]} )); then
    note "backups of your configs from before AnoShell changed them (yours to keep or delete):"
    for b in "${backups[@]}"; do note "  ${b/#$HOME/\~}"; done
fi
mapfile -t refs < <(grep -rlsE 'quickshell/ano|ano start|qs -c ano' "$C"/{hypr,niri,sway,mango,labwc,umbriel} 2>/dev/null | grep -v '\.ano-backup\|\.bak-' || true)
if (( ${#refs[@]} )); then
    warn "these compositor files still start or use AnoShell; edit them:"
    for r in "${refs[@]}"; do note "  ${r/#$HOME/\~}"; done
fi
(( purge )) || note "your settings stay in ${C/#$HOME/\~}/anoshell and ${XDG_DATA_HOME/#$HOME/\~}/anoshell (installing again picks them up)"
printf '\n%sDone.%s Log out and back in (or restart your compositor) to drop anything still running.\n' "$G" "$N"
