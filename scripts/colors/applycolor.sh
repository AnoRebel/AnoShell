#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════
# Ano Shell — applycolor.sh
# Applies generated Material You colors to external applications.
# Run by anod as the "apps" wallpaper hook (background.hooks) after matugen.
#
# Currently supports: kitty, ghostty, foot, cava, Qt, hyprtoolkit
# Extend by adding functions below.
# ══════════════════════════════════════════════════════════════════════════

set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
COLORS_JSON="$XDG_STATE_HOME/anoshell/generated/colors.json"
MODE="dark"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode|-m) MODE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if ! command -v jq &>/dev/null; then
    echo "[applycolor] jq not installed — cannot parse colors"
    exit 0
fi

# colors.json (matugen) is preferred but optional — the per-colour reads below
# fall back to pywal (~/.cache/wal/colors.json). Only bail if we have NEITHER
# source, otherwise proceed so Qt/Kvantum theming still works from pywal.
if [[ ! -f "$COLORS_JSON" ]]; then
    if [[ -f "$HOME/.cache/wal/colors.json" ]]; then
        echo "[applycolor] colors.json absent — falling back to pywal colours"
    else
        echo "[applycolor] no colour source (colors.json or pywal) — nothing to apply"
        exit 0
    fi
fi

log() { echo "[applycolor] $*"; }

# Read colors. Prefer ano's Material You colors.json (matugen); fall back to a
# key from pywal's ~/.cache/wal/colors.json when a field is missing/null so the
# script still themes usefully before matugen has generated a full palette.
WAL_JSON="$HOME/.cache/wal/colors.json"
_wal() { [[ -f "$WAL_JSON" ]] && jq -r "$1 // empty" "$WAL_JSON" 2>/dev/null; }
_col() { # $1 = colors.json jq path, $2 = pywal fallback jq path, $3 = literal fallback
    local v=""
    [[ -f "$COLORS_JSON" ]] && v=$(jq -r "$1 // empty" "$COLORS_JSON" 2>/dev/null)
    [[ -n "$v" && "$v" != "null" ]] && { echo "$v"; return; }
    v=$(_wal "$2"); [[ -n "$v" ]] && { echo "$v"; return; }
    echo "${3:-#000000}"
}

# colors.json keys are snake_case (matugen's names).
primary=$(_col '.primary' '.colors.color4' '#8ab4f8')
onPrimary=$(_col '.on_primary' '.special.background' '#000000')
background=$(_col '.background' '.special.background' '#1c1b1f')
onBackground=$(_col '.on_background' '.special.foreground' '#e6e1e5')
surface=$(_col '.surface' '.special.background' '#1c1b1f')
onSurface=$(_col '.on_surface' '.special.foreground' '#e6e1e5')
onSurfaceVariant=$(_col '.on_surface_variant' '.colors.color7' '#cac4d0')
surfaceContainer=$(_col '.surface_container' '.colors.color0' '#2b2930')
surfaceContainerLowest=$(_col '.surface_container_lowest' '.special.background' '#0f0d13')
surfaceContainerLow=$(_col '.surface_container_low' '.colors.color0' '#1d1b20')
surfaceContainerHigh=$(_col '.surface_container_high' '.colors.color8' '#36343b')
surfaceContainerHighest=$(_col '.surface_container_highest' '.colors.color8' '#48464c')
inverseSurface=$(_col '.inverse_surface' '.special.foreground' '#e6e1e5')
inverseOnSurface=$(_col '.inverse_on_surface' '.special.background' '#313033')
outline=$(_col '.outline' '.colors.color8' '#938f99')
shadow=$(_col '.shadow' '.special.background' '#000000')
secondary=$(_col '.secondary' '.colors.color2' '#ccc2dc')
tertiary=$(_col '.tertiary' '.colors.color5' '#efb8c8')

# Qt: appearance.theme.qt in the shell config. "palette" (default): Breeze
# (or Fusion without it) on qt5ct/qt6ct's palette, which running apps pick up live;
# "kvantum": a recoloured Kvantum theme, which apps read when they start
# (Kvantum draws from an SVG with its colours baked in, so it can't follow a
# palette live); "off": Qt is left alone.
QT_MODE=$(jq -r '.appearance.theme.qt // empty' "$XDG_CONFIG_HOME/anoshell/config.json" 2>/dev/null || true)
QT_MODE=${QT_MODE:-palette}

# #RRGGBB → 0xFFRRGGBB (opaque) for hyprland/hyprtoolkit color syntax.
_hexToHl() { local h="${1#\#}"; [[ "${#h}" -eq 6 ]] && echo "0xFF${h^^}" || echo "0xFF181818"; }

# ── Terminals (kitty, ghostty, foot) ───────────────────────────────────────
# One colours file per terminal (16-colour palette, fg/bg, cursor, selection)
# under generated/terminal/, and ONE marked include in the terminal's own
# config that pulls it in. The user's file is never rewritten wholesale: only
# our marker block is added or removed, through a symlink when it is one (the
# target is edited in place), and the file is backed up once to <file>.ano-backup.
# appearance.theme.terminals.<name> = false takes the block out again.
TERM_DIR="$XDG_STATE_HOME/anoshell/generated/terminal"
TERM_MARK="# anoshell-colors: added by AnoShell (Settings > Appearance > Terminals); removed when that switch is off"
CONFIG_JSON="$XDG_CONFIG_HOME/anoshell/config.json"
# ANOSHELL_NO_LIVE=1: don't signal running terminals (tests).
LIVE=1
[[ "${ANOSHELL_NO_LIVE:-}" == 1 ]] && LIVE=0

_term_on() { # $1 = kitty|ghostty|foot → true unless its switch is false
    [[ -f "$CONFIG_JSON" ]] || return 0
    [[ "$(jq -r --arg t "$1" '.appearance.theme.terminals[$t] | if . == false then "off" else "on" end' "$CONFIG_JSON" 2>/dev/null)" != off ]]
}

# 6 hues (red green yellow blue magenta cyan), normal then bright, at the
# primary's saturation and nudged 20 % towards it so they sit in the palette.
_ansi_hues() { # $1 primary, $2 mode → 12 lines
    awk -v p="$1" -v mode="$2" '
        function hx(s, i) { return index("0123456789abcdef", tolower(substr(s, i, 1))) - 1 }
        function ch(s, i) { return (hx(s, i) * 16 + hx(s, i + 1)) / 255 }
        function h2r(a, b, t) { if (t < 0) t += 1; if (t > 1) t -= 1
            if (t < 1/6) return a + (b - a) * 6 * t; if (t < 1/2) return b
            if (t < 2/3) return a + (b - a) * (2/3 - t) * 6; return a }
        function out(h, s, l,   q, a) { q = l < 0.5 ? l * (1 + s) : l + s - l * s; a = 2 * l - q
            printf "#%02x%02x%02x\n", (h2r(a, q, h + 1/3) * 0.8 + pr * 0.2) * 255 + 0.5,
                (h2r(a, q, h) * 0.8 + pg * 0.2) * 255 + 0.5, (h2r(a, q, h - 1/3) * 0.8 + pb * 0.2) * 255 + 0.5 }
        BEGIN {
            c = p; sub(/^#/, "", c); pr = ch(c, 1); pg = ch(c, 3); pb = ch(c, 5)
            mx = pr; if (pg > mx) mx = pg; if (pb > mx) mx = pb
            mn = pr; if (pg < mn) mn = pg; if (pb < mn) mn = pb
            l = (mx + mn) / 2; s = mx == mn ? 0 : (l > 0.5 ? (mx - mn) / (2 - mx - mn) : (mx - mn) / (mx + mn))
            if (s < 0.4) s = 0.4; if (s > 0.7) s = 0.7
            split("0 120 45 215 295 180", H, " ")
            for (b = 0; b < 2; b++) for (i = 1; i <= 6; i++)
                out(H[i] / 360, s, mode == "light" ? (b ? 0.32 : 0.40) : (b ? 0.78 : 0.68))
        }'
}

# term[0..15]: pywal's own when matugen's colors.json is absent, else built
# from the Material roles.
declare -a term
_term_palette() {
    local -a hues
    local i
    if [[ ! -f "$COLORS_JSON" && -n "$(_wal '.colors.color15')" ]]; then
        for i in {0..15}; do term[i]=$(_wal ".colors.color$i"); done
        return
    fi
    mapfile -t hues < <(_ansi_hues "$primary" "$MODE")
    if [[ "$MODE" == light ]]; then
        term[0]=$inverseSurface term[7]=$surfaceContainerHighest term[8]=$outline term[15]=$surfaceContainerLowest
    else
        term[0]=$surfaceContainerHigh term[7]=$onSurfaceVariant term[8]=$outline term[15]=$onSurface
    fi
    for i in {1..6}; do term[i]=${hues[i-1]} term[i+8]=${hues[i+5]}; done
}

# Prints the file without our block: the marker line and the lines right
# after it that are ours ([main], or a path into generated/terminal/).
_strip_block() {
    awk -v mark="$TERM_MARK" '
        skip && ($0 == "[main]" || index($0, "/anoshell/generated/terminal/")) { next }
        { skip = 0 }
        $0 == mark { skip = 1; next }
        { print }' "$1"
}

# $1 config file, $2 on|off, $3 the block's lines (newline-separated).
# The block goes last; the file is written only when that changes it.
_include_block() {
    local f="$1" want="$2" lines="$3" tmp
    if [[ -L "$f" && ! -e "$f" ]]; then log "WARN: $f is a broken symlink, left alone"; return 0; fi
    if [[ ! -e "$f" ]]; then
        [[ "$want" == on ]] || return 0
        mkdir -p "$(dirname "$f")"
        printf '%s\n%s\n' "$TERM_MARK" "$lines" > "$f"
        return 0
    fi
    tmp=$(mktemp)
    _strip_block "$f" > "$tmp"
    if [[ "$want" == on ]]; then
        [[ -s "$tmp" && -n "$(tail -c1 "$tmp")" ]] && echo >> "$tmp"
        printf '%s\n%s\n' "$TERM_MARK" "$lines" >> "$tmp"
    fi
    if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
    if [[ ! -w "$f" ]]; then log "WARN: $f is not writable, left alone"; rm -f "$tmp"; return 0; fi
    [[ -e "$f.ano-backup" ]] || cp -L -- "$f" "$f.ano-backup"
    # Through a symlink into its target, never replacing the link itself.
    cat "$tmp" > "$f"
    rm -f "$tmp"
}

# $1 name, $2 config file: "on" when its switch is on and it's in use
# (the config exists or the terminal is installed).
_term_state() {
    if _term_on "$1" && { [[ -e "$2" ]] || command -v "$1" &>/dev/null; }; then echo on; else echo off; fi
}

apply_kitty() {
    local conf="$XDG_CONFIG_HOME/kitty/kitty.conf" gen="$TERM_DIR/kitty.conf" on i
    on=$(_term_state kitty "$conf")
    if [[ "$on" == on ]]; then
        {
            echo "# Generated by AnoShell applycolor.sh from the wallpaper palette."
            echo "foreground $onBackground"; echo "background $background"
            echo "cursor $primary"; echo "cursor_text_color $background"
            echo "selection_foreground $onPrimary"; echo "selection_background $primary"
            echo "url_color $tertiary"
            for i in {0..15}; do echo "color$i ${term[i]}"; done
        } > "$gen"
    fi
    # Last in kitty.conf, so it wins over earlier colour lines and themes.
    _include_block "$conf" "$on" "include $gen"
    [[ "$on" == off ]] && rm -f "$gen"
    # SIGUSR1 makes every running kitty re-read kitty.conf, include and all.
    if [[ "$LIVE" == 1 ]]; then pkill -USR1 -x kitty 2>/dev/null || true; fi
    log "kitty colours: $on"
}

apply_ghostty() {
    local dir="$XDG_CONFIG_HOME/ghostty" conf gen="$TERM_DIR/ghostty" on i
    conf="$dir/config"; [[ -e "$dir/config.ghostty" ]] && conf="$dir/config.ghostty"
    on=$(_term_state ghostty "$conf")
    if [[ "$on" == on ]]; then
        {
            echo "# Generated by AnoShell applycolor.sh from the wallpaper palette."
            echo "background = $background"; echo "foreground = $onBackground"
            echo "cursor-color = $primary"; echo "cursor-text = $background"
            echo "selection-foreground = $onPrimary"; echo "selection-background = $primary"
            for i in {0..15}; do echo "palette = $i=${term[i]}"; done
        } > "$gen"
    fi
    # config-file is read after the whole file, so it wins over theme= and
    # colour lines wherever it sits; "?" keeps a missing file from erroring.
    _include_block "$conf" "$on" "config-file = ?$gen"
    [[ "$on" == off ]] && rm -f "$gen"
    # Ghostty reloads its configuration on SIGUSR2.
    if [[ "$LIVE" == 1 ]]; then pkill -USR2 -x ghostty 2>/dev/null || true; fi
    log "ghostty colours: $on"
}

apply_foot() {
    local conf="$XDG_CONFIG_HOME/foot/foot.ini" gen="$TERM_DIR/foot.ini" on i s ver sections h=()
    on=$(_term_state foot "$conf")
    if [[ "$on" == on ]]; then
        # [colors-dark]/[colors-light] since foot 1.26; 1.28 dropped [colors].
        sections="colors-dark colors-light"
        ver=$(foot --version 2>/dev/null | sed -n 's/^foot version: \([0-9]*\)\.\([0-9]*\).*/\1 \2/p')
        if [[ -n "$ver" ]] && (( ${ver% *} == 1 && ${ver#* } < 26 )); then sections="colors"; fi
        for i in {0..15}; do h[i]=${term[i]#\#}; done
        {
            echo "# Generated by AnoShell applycolor.sh from the wallpaper palette."
            for s in $sections; do
                echo "[$s]"
                echo "foreground=${onBackground#\#}"; echo "background=${background#\#}"
                echo "cursor=${background#\#} ${primary#\#}"
                echo "selection-foreground=${onPrimary#\#}"; echo "selection-background=${primary#\#}"
                for i in {0..7}; do echo "regular$i=${h[i]}"; echo "bright$i=${h[i+8]}"; done
            done
        } > "$gen"
    fi
    # include= is a [main] key read where it stands, so it goes last (after
    # the user's own colours) under a [main] of its own.
    _include_block "$conf" "$on" $'[main]\ninclude='"$gen"
    [[ "$on" == off ]] && rm -f "$gen"
    log "foot colours: $on (new windows; a running foot server keeps its colours until restarted)"
}

# ── Cava (if pywal didn't already handle it) ─────────────────────────────
apply_cava() {
    local config="$HOME/.config/cava/config"
    [[ -f "$config" ]] || return 0 # (a bare return is 1 here and set -e ends the script)

    # Only update if pywal didn't already
    if [[ -f "$HOME/.cache/wal/colors.sh" ]]; then return; fi

    cp "$config" "$config.bak" 2>/dev/null || true

    sed -i \
        -e "s/^background = .*/background = '${background}'/" \
        -e "s/^foreground = .*/foreground = '${primary}'/" \
        "$config" 2>/dev/null || true

    if [[ "$LIVE" == 1 ]]; then pkill -USR2 cava 2>/dev/null || true; fi
    log "Applied colors to cava"
}

# ── Qt (qt5ct/qt6ct palette, Kvantum, QuickControls2) ───────────────────────
# qt5ct/qt6ct get a colour scheme in the palette and are pointed at it
# (color_scheme_path, custom_palette), as Bioma does. They watch their config
# directory and, 3 s after a change, re-apply the palette and icon theme to
# running apps; the style is only read at start. Kvantum draws with its own
# colours, not the palette, so in "kvantum" mode a palette change reaches an
# app when it next starts.

# The 22 QPalette roles in qt5ct's order (WindowText, Button, Light, Midlight,
# Dark, Mid, Text, BrightText, ButtonText, Base, Window, Shadow, Highlight,
# HighlightedText, Link, LinkVisited, AlternateBase, NoRole, ToolTipBase,
# ToolTipText, PlaceholderText, Accent); $1 is the text colour.
_qt_roles() {
    echo "$1, $surfaceContainerHigh, $surfaceContainerHighest, $surfaceContainerHigh, $surfaceContainerLowest, $surfaceContainer, $1, $onBackground, $1, $surfaceContainerLow, $surface, $shadow, $primary, $onPrimary, $primary, $tertiary, $surfaceContainer, $surface, $inverseSurface, $inverseOnSurface, $onSurfaceVariant, $primary"
}

# Points <tool>.conf at the scheme and sets the style, keeping every other
# line; written beside it and renamed, so the tool's directory watch fires.
_qt_point() {
    local dir="$1" scheme="$2" style="$3" conf="$1/${1##*/}.conf"
    local tmp
    tmp=$(mktemp "$dir/.conf-XXXXXX")
    awk -v scheme="$scheme" -v style="$style" '
        function put() { print "color_scheme_path=" scheme; print "custom_palette=true"; if (style != "") print "style=" style; done = 1 }
        /^\[/ { if (inside && !done) put(); inside = ($0 == "[Appearance]") }
        inside && /^(color_scheme_path|custom_palette|style)=/ { next }
        { print }
        inside && !done { put() }
        END { if (!seen && !done) { print "[Appearance]"; put() } }
        $0 == "[Appearance]" { seen = 1 }
    ' "$conf" 2>/dev/null > "$tmp" || true
    mv "$tmp" "$conf"
}

# A Kvantum theme in the palette, shapes from KvArcDark.
_qt_kvantum() {
    local kvdir="$XDG_CONFIG_HOME/Kvantum"
    local theme="AnoColors"
    local base="/usr/share/Kvantum/KvArcDark"
    local tdir="$kvdir/$theme"

    if [[ -d "$base" ]]; then
        mkdir -p "$tdir"
        # Copy the base SVG once (widget shapes); we only recolour, not reshape.
        [[ -f "$tdir/$theme.svg" ]] || cp "$base/KvArcDark.svg" "$tdir/$theme.svg" 2>/dev/null || true

        # A translucent-ish container tone for menus/tooltips.
        cat > "$tdir/$theme.kvconfig" <<EOF
# Generated by ano applycolor.sh — recoloured from the current wallpaper.
# Inherits widget shapes/metrics from KvArcDark; only colours are overridden.
[%General]
author=anorebel
comment=Ano wallpaper-generated colours
x11drag=all
alt_mnemonic=true
left_tabs=true
attach_active_tab=false
mirror_doc_tabs=true
group_toolbar_buttons=false
spread_progressbar=true
composite=true
menu_shadow_depth=7
tooltip_shadow_depth=6
scroll_width=6
scroll_arrows=false
scrollbar_in_view=true
transient_scrollbar=true
transient_groove=true
submenu_overlap=0
tooltip_delay=0
[GeneralColors]
window.color=$background
base.color=$surface
alt.base.color=$surfaceContainer
button.color=$surfaceContainer
light.color=$surfaceContainer
mid.light.color=$surface
dark.color=$background
mid.color=$surfaceContainer
highlight.color=$primary
inactive.highlight.color=$secondary
text.color=$onSurface
window.text.color=$onBackground
button.text.color=$onSurface
disabled.text.color=${onSurface}78
tooltip.text.color=$onBackground
highlight.text.color=$onPrimary
inactive.highlight.text.color=$onBackground
link.color=$primary
link.visited.color=$secondary
progress.indicator.text.color=$onPrimary
EOF

        # Select the generated theme.
        cat > "$kvdir/kvantum.kvconfig" <<EOF
[General]
theme=$theme
EOF
        log "Wrote Kvantum theme $theme"
    else
        log "Kvantum base $base not found — skipping Kvantum theme"
    fi
}

# Off: qt5ct/qt6ct stop pointing at our scheme (if they do) and it goes.
_qt_unpoint() {
    local tool dir conf tmp
    for tool in qt5ct qt6ct; do
        dir="$XDG_CONFIG_HOME/$tool" conf="$XDG_CONFIG_HOME/$tool/$tool.conf"
        if [[ -f "$conf" ]] && grep -q '^color_scheme_path=.*/colors/anoshell\.conf$' "$conf"; then
            tmp=$(mktemp "$dir/.conf-XXXXXX")
            grep -v -e '^color_scheme_path=.*/colors/anoshell\.conf$' -e '^custom_palette=true$' "$conf" > "$tmp" || true
            mv "$tmp" "$conf"
        fi
        rm -f "$dir/colors/anoshell.conf"
    done
}

apply_qt() {
    if [[ "$QT_MODE" == "off" ]]; then _qt_unpoint; return 0; fi
    local style=""
    case "$QT_MODE" in
        palette) style="Fusion" ;;
        kvantum) style="kvantum" ;;
    esac

    local active disabled tool dir
    active=$(_qt_roles "$onSurface")
    disabled=$(_qt_roles "$outline")
    for tool in qt5ct qt6ct; do
        dir="$XDG_CONFIG_HOME/$tool"
        # qt6ct always (Qt 6 apps); qt5ct only when it's set up
        [[ "$tool" == qt5ct && ! -d "$dir" ]] && continue
        mkdir -p "$dir/colors"
        printf '[ColorScheme]\nactive_colors=%s\ndisabled_colors=%s\ninactive_colors=%s\n' \
            "$active" "$disabled" "$active" > "$dir/colors/anoshell.conf"
        [[ -f "$dir/$tool.conf" ]] || printf '[Appearance]\nicon_theme=Papirus-Dark\nstandard_dialogs=default\n' > "$dir/$tool.conf"
        # palette: a style you set that draws with the palette is kept; Kvantum,
        # which doesn't, or none becomes Breeze when it's installed for this
        # Qt (breeze6.so / breeze5.so), else Fusion
        local want="$style" cur
        cur=$(sed -n 's/^style=//p' "$dir/$tool.conf" | head -n1)
        if [[ "$QT_MODE" == palette ]]; then
            if [[ -n "$cur" && "${cur,,}" != kvantum ]]; then
                want="$cur"
            elif compgen -G "/usr/lib/qt${tool:2:1}/plugins/styles/breeze*.so" >/dev/null \
                || compgen -G "/usr/lib/qt/plugins/styles/breeze${tool:2:1}.so" >/dev/null; then
                want="Breeze"
            fi
        fi
        _qt_point "$dir" "$dir/colors/anoshell.conf" "$want"
        log "Wrote the $tool palette (style: $want)"
    done

    [[ "$QT_MODE" == "kvantum" ]] && _qt_kvantum

    # QtQuick Controls 2 Material palette (QML side of hyprpolkitagent etc.).
    local qc2="$XDG_CONFIG_HOME/qtquickcontrols2.conf"
    cat > "$qc2" <<EOF
[Controls]
Style=Material

[Material]
Theme=Dark
Accent=$primary
Primary=$primary
Background=$background
Foreground=$onBackground
EOF
    log "Wrote QtQuick Controls 2 Material palette"
}

# ── hyprtoolkit (hyprpolkitagent) ──────────────────────────────────────────
# hyprpolkitagent is built on hyprtoolkit (NOT Qt), so it's themed by
# ~/.config/hypr/hyprtoolkit.conf — the qt6ct/Kvantum path above does NOT
# affect it. hyprtoolkit reads this file live (next dialog picks up changes,
# no restart needed). Colours use hyprland's 0xAARRGGBB syntax.
apply_hyprtoolkit() {
    local conf="$XDG_CONFIG_HOME/hypr/hyprtoolkit.conf"
    mkdir -p "$(dirname "$conf")"
    cat > "$conf" <<EOF
# Generated by ano applycolor.sh — recoloured from the current wallpaper.
# Keys: https://wiki.hypr.land/Hypr-Ecosystem/hyprtoolkit/
background = $(_hexToHl "$background")
base = $(_hexToHl "$surface")
alternate_base = $(_hexToHl "$surfaceContainer")
text = $(_hexToHl "$onSurface")
bright_text = $(_hexToHl "$onBackground")
accent = $(_hexToHl "$primary")
accent_secondary = $(_hexToHl "$secondary")
rounding_large = 12
rounding_small = 6
EOF
    log "Wrote hyprtoolkit.conf (hyprpolkitagent theme)"
}

# ── Run all ──────────────────────────────────────────────────────────────
mkdir -p "$TERM_DIR"
_term_palette
apply_kitty
apply_ghostty
apply_foot
apply_cava
apply_qt
apply_hyprtoolkit

log "Done applying colors to external apps"
