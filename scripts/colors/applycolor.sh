#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════
# Ano Shell — applycolor.sh
# Applies generated Material You colors to external applications.
# Run by anod as the "apps" wallpaper hook (background.hooks) after matugen.
#
# Currently supports: kitty, ghostty, foot, cava, GTK dark/light
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
error=$(_col '.error' '.colors.color1' '#f2b8b5')

# Qt: appearance.theme.qt in the shell config. "palette" (default): the
# Fusion style on qt5ct/qt6ct's palette, which running apps pick up live;
# "kvantum": a recoloured Kvantum theme, which apps read when they start
# (Kvantum draws from an SVG with its colours baked in, so it can't follow a
# palette live); "off": Qt is left alone.
QT_MODE=$(jq -r '.appearance.theme.qt // empty' "$XDG_CONFIG_HOME/anoshell/config.json" 2>/dev/null || true)
QT_MODE=${QT_MODE:-palette}

# #RRGGBB → 0xFFRRGGBB (opaque) for hyprland/hyprtoolkit color syntax.
_hexToHl() { local h="${1#\#}"; [[ "${#h}" -eq 6 ]] && echo "0xFF${h^^}" || echo "0xFF181818"; }

# ── Kitty ────────────────────────────────────────────────────────────────
apply_kitty() {
    if ! command -v kitty &>/dev/null; then return; fi
    # Send OSC escape sequences to all kitty instances
    for sock in /tmp/kitty-*/; do
        [[ -d "$sock" ]] || continue
        kitty @ --to "unix:${sock}control" set-colors \
            "foreground=$onBackground" \
            "background=$background" \
            "cursor=$primary" \
            "selection_foreground=$onPrimary" \
            "selection_background=$primary" \
            2>/dev/null || true
    done
    log "Applied colors to kitty"
}

# ── Ghostty ──────────────────────────────────────────────────────────────
apply_ghostty() {
    local config="$XDG_CONFIG_HOME/ghostty/config"
    [[ -f "$config" ]] || return 0 # (a bare return is 1 here and set -e ends the script)

    # Backup
    cp "$config" "$config.bak" 2>/dev/null || true

    # Update colors using sed
    sed -i \
        -e "s/^background = .*/background = ${background}/" \
        -e "s/^foreground = .*/foreground = ${onBackground}/" \
        -e "s/^cursor-color = .*/cursor-color = ${primary}/" \
        -e "s/^selection-foreground = .*/selection-foreground = ${onPrimary}/" \
        -e "s/^selection-background = .*/selection-background = ${primary}/" \
        "$config" 2>/dev/null || true

    log "Applied colors to ghostty config"
}

# ── Foot ─────────────────────────────────────────────────────────────────
apply_foot() {
    local config="$XDG_CONFIG_HOME/foot/foot.ini"
    [[ -f "$config" ]] || return 0 # (a bare return is 1 here and set -e ends the script)

    cp "$config" "$config.bak" 2>/dev/null || true

    # Strip # from hex colors for foot format
    local bg="${background/#\#/}"
    local fg="${onBackground/#\#/}"

    sed -i \
        -e "s/^background=.*/background=${bg}/" \
        -e "s/^foreground=.*/foreground=${fg}/" \
        "$config" 2>/dev/null || true

    log "Applied colors to foot config"
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

    pkill -USR2 cava 2>/dev/null || true
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
        # palette: a style you set that draws with the palette (Breeze, …) is
        # kept; only Kvantum, which doesn't, or none becomes Fusion
        local want="$style" cur
        cur=$(sed -n 's/^style=//p' "$dir/$tool.conf" | head -n1)
        [[ "$QT_MODE" == palette && -n "$cur" && "${cur,,}" != kvantum ]] && want="$cur"
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
apply_kitty
apply_ghostty
apply_foot
apply_cava
apply_qt
apply_hyprtoolkit

log "Done applying colors to external apps"
