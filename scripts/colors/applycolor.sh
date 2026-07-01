#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════
# Ano Shell — applycolor.sh
# Applies generated Material You colors to external applications.
# Called by switchwall.sh after color generation.
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

primary=$(_col '.primary' '.colors.color4' '#8ab4f8')
onPrimary=$(_col '.onPrimary' '.special.background' '#000000')
background=$(_col '.background' '.special.background' '#1c1b1f')
onBackground=$(_col '.onBackground' '.special.foreground' '#e6e1e5')
surface=$(_col '.surface' '.special.background' '#1c1b1f')
onSurface=$(_col '.onSurface' '.special.foreground' '#e6e1e5')
surfaceContainer=$(_col '.surfaceContainer' '.colors.color0' '#2b2930')
secondary=$(_col '.secondary' '.colors.color2' '#ccc2dc')
error=$(_col '.error' '.colors.color1' '#f2b8b5')

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
    [[ -f "$config" ]] || return

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
    [[ -f "$config" ]] || return

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
    [[ -f "$config" ]] || return

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

# ── Qt (Kvantum + qt6ct + QuickControls2) ──────────────────────────────────
# Recolours all Qt apps — notably the polkit auth dialog (hyprpolkitagent, which
# uses Qt Widgets + QtQuick Controls) — to match the wallpaper. Approach:
#   1. A generated Kvantum theme "AnoColors" that inherits shapes from a base
#      dark theme (KvArcDark) and overrides only [GeneralColors].
#   2. qt6ct set to style=kvantum so Kvantum drives Qt Widgets.
#   3. A QtQuick Controls 2 Material config for the QML side.
# Everything is written idempotently; nothing here breaks apps if a piece is
# missing — each step guards on its dependency.
apply_qt() {
    local kvdir="$XDG_CONFIG_HOME/Kvantum"
    local theme="AnoColors"
    local base="/usr/share/Kvantum/KvArcDark"
    local tdir="$kvdir/$theme"

    # 1. Kvantum theme (needs the base theme present for its SVG shapes).
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

    # 2. qt6ct → use Kvantum as the widget style (create/patch the conf).
    local qt6dir="$XDG_CONFIG_HOME/qt6ct"
    mkdir -p "$qt6dir"
    local qt6conf="$qt6dir/qt6ct.conf"
    if [[ -f "$qt6conf" ]]; then
        if grep -q '^style=' "$qt6conf"; then
            sed -i 's/^style=.*/style=kvantum/' "$qt6conf"
        else
            # Insert under [Appearance] (or append a section).
            grep -q '^\[Appearance\]' "$qt6conf" \
                && sed -i '/^\[Appearance\]/a style=kvantum' "$qt6conf" \
                || printf '\n[Appearance]\nstyle=kvantum\n' >> "$qt6conf"
        fi
    else
        cat > "$qt6conf" <<EOF
[Appearance]
style=kvantum
icon_theme=Papirus-Dark
standard_dialogs=default
EOF
    fi
    log "Set qt6ct style=kvantum"

    # 3. QtQuick Controls 2 Material palette (QML side of hyprpolkitagent etc.).
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

    # 4. Restart hyprpolkitagent so it repaints with the new palette (harmless
    #    if it isn't running / not managed by systemd).
    systemctl --user restart hyprpolkitagent 2>/dev/null || true
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
