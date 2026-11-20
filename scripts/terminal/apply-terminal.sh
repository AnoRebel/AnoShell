#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════
# AnoShell — apply-terminal.sh: terminal looks and prompt styles (terminal.*).
#
# Looks (terminal.enable): background opacity, padding and cursor for kitty,
# foot, ghostty and alacritty (terminal.apps.<name>), in one generated file each
# under $XDG_STATE_HOME/anoshell/generated/terminal/look-*, pulled in by ONE
# marked block in the terminal's own config (backed up once to <file>.ano-backup;
# only that block is ever added or removed, through a symlink when it is one).
#
# Prompts (terminal.prompt "segments" | "minimal"; "own" adds nothing): a
# generated prompt.env (style + colours from the palette) read at each prompt,
# the prompt code for zsh, bash and fish copied next to it, a Starship config
# when Starship is installed, and ONE marked line in each enabled shell's rc file.
#
#   apply-terminal.sh            everything
#   apply-terminal.sh --prompt   only the prompt colours (the palette changed)
#
# ANOSHELL_NO_LIVE=1: don't signal running terminals (tests).
# ══════════════════════════════════════════════════════════════════════════
set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CONFIG_JSON="$XDG_CONFIG_HOME/anoshell/config.json"
COLORS_JSON="$XDG_STATE_HOME/anoshell/generated/colors.json"
DIR="$XDG_STATE_HOME/anoshell/generated/terminal"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOK_MARK="# anoshell-look: added by AnoShell (Settings > Appearance > Terminal look); removed when that is off"
PROMPT_MARK="# anoshell-prompt: added by AnoShell (Settings > Appearance > Terminal look); removed when the prompt is your own"
LIVE=1
[[ "${ANOSHELL_NO_LIVE:-}" == 1 ]] && LIVE=0
ONLY_PROMPT=0
[[ "${1:-}" == --prompt ]] && ONLY_PROMPT=1

log() { echo "[apply-terminal] $*"; }
command -v jq &>/dev/null || { log "jq not installed: nothing applied"; exit 0; }

# terminal.* from your config, with the shell's defaults (modules/common/Config.qml).
cfg() { # $1 jq path, $2 default
    local v=""
    [[ -f "$CONFIG_JSON" ]] && v=$(jq -r "$1 | if . == null then empty else . end" "$CONFIG_JSON" 2>/dev/null || true)
    echo "${v:-$2}"
}
ENABLE=$(cfg '.terminal.enable' false)
BACKGROUND=$(cfg '.terminal.background' translucent)
OPACITY=$(cfg '.terminal.opacity' 0.85)
PADDING=$(cfg '.terminal.padding' 12)
CURSOR=$(cfg '.terminal.cursor' beam)
PROMPT=$(cfg '.terminal.prompt' own)
# Font (empty family / size 0: the terminal's own). Names with characters the
# config formats treat specially (quotes, :, =, #, commas, newlines) are refused.
FONT=$(cfg '.terminal.font.family' "")
FONT_SIZE=$(cfg '.terminal.font.size' 0)
[[ "$FONT" =~ ^[[:alnum:]][[:alnum:]\ ._+\(\)-]{0,63}$ ]] || FONT=""
[[ "$FONT_SIZE" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( ${FONT_SIZE%.*} >= 6 && ${FONT_SIZE%.*} <= 32 )) || FONT_SIZE=0
case "$BACKGROUND" in solid) OPACITY=1 ;; clear) OPACITY=0 ;; translucent) ;; *) OPACITY=1 ;; esac
[[ "$OPACITY" =~ ^(0|1|0?\.[0-9]+|1\.0+)$ ]] || OPACITY=0.85
[[ "$PADDING" =~ ^[0-9]+$ ]] && (( PADDING <= 32 )) || PADDING=12
case "$CURSOR" in block|beam|underline) ;; *) CURSOR=beam ;; esac
case "$PROMPT" in own|segments|minimal) ;; *) PROMPT=own ;; esac

mkdir -p "$DIR"

# ── The marked blocks ─────────────────────────────────────────────────────
# Prints $1 without the block that follows $2 (the marker, and right after it
# the lines that are ours: a [main]/[general] header, or a path into $DIR).
_strip() {
    awk -v mark="$2" -v dir="$DIR/" '
        skip && ($0 == "[main]" || $0 == "[general]" || index($0, dir)) { next }
        { skip = 0 }
        $0 == mark { skip = 1; next }
        { print }' "$1"
}
# $1 file, $2 marker, $3 on|off, $4 block lines, $5 "end" (default) or "after:<header line>".
_block() {
    local f="$1" mark="$2" want="$3" lines="$4" where="${5:-end}" tmp
    if [[ -L "$f" && ! -e "$f" ]]; then log "WARN: $f is a broken symlink, left alone"; return 0; fi
    if [[ ! -e "$f" ]]; then
        [[ "$want" == on ]] || return 0
        mkdir -p "$(dirname "$f")"
        printf '%s\n%s\n' "$mark" "$lines" > "$f"
        return 0
    fi
    tmp=$(mktemp)
    _strip "$f" "$mark" > "$tmp"
    if [[ "$want" == on ]]; then
        if [[ "$where" == after:* ]]; then
            local t2; t2=$(mktemp)
            awk -v h="${where#after:}" -v mark="$mark" -v lines="$lines" '
                { print } !done && $0 == h { print mark; print lines; done = 1 }' "$tmp" > "$t2"
            mv "$t2" "$tmp"
        else
            [[ -s "$tmp" && -n "$(tail -c1 "$tmp")" ]] && echo >> "$tmp"
            printf '%s\n%s\n' "$mark" "$lines" >> "$tmp"
        fi
    fi
    if cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 0; fi
    if [[ ! -w "$f" ]]; then log "WARN: $f is not writable, left alone"; rm -f "$tmp"; return 0; fi
    [[ -e "$f.ano-backup" ]] || cp -L -- "$f" "$f.ano-backup"
    cat "$tmp" > "$f"
    rm -f "$tmp"
}

# "on" when looks are on, this terminal's switch is on, and it's in use.
_state() { # $1 name, $2 config file
    local sw
    sw=$(cfg ".terminal.apps.$1" true)
    if [[ "$ENABLE" == true && "$sw" != false ]] && { [[ -e "$2" ]] || command -v "$1" &>/dev/null; }; then echo on; else echo off; fi
}

# ── Looks ────────────────────────────────────────────────────────────────
look_kitty() {
    local conf="$XDG_CONFIG_HOME/kitty/kitty.conf" gen="$DIR/look-kitty.conf" on
    on=$(_state kitty "$conf")
    if [[ "$on" == on ]]; then
        {
            printf '# Generated by AnoShell apply-terminal.sh (terminal.*).\nbackground_opacity %s\nwindow_padding_width %s\ncursor_shape %s\n' \
                "$OPACITY" "$PADDING" "$CURSOR"
            [[ -n "$FONT" ]] && echo "font_family $FONT"
            [[ "$FONT_SIZE" != 0 ]] && echo "font_size $FONT_SIZE"
        } > "$gen"
    fi
    _block "$conf" "$LOOK_MARK" "$on" "include $gen"
    [[ "$on" == off ]] && rm -f "$gen"
    # SIGUSR1: every running kitty re-reads its config (opacity included).
    if [[ "$LIVE" == 1 ]]; then pkill -USR1 -x kitty 2>/dev/null || true; fi
    log "kitty look: $on"
}

look_ghostty() {
    local d="$XDG_CONFIG_HOME/ghostty" conf gen="$DIR/look-ghostty" on c
    conf="$d/config"; [[ -e "$d/config.ghostty" ]] && conf="$d/config.ghostty"
    on=$(_state ghostty "$conf")
    c=$CURSOR; [[ "$c" == beam ]] && c=bar
    if [[ "$on" == on ]]; then
        {
            printf '# Generated by AnoShell apply-terminal.sh (terminal.*).\nbackground-opacity = %s\nwindow-padding-x = %s\nwindow-padding-y = %s\ncursor-style = %s\n' \
                "$OPACITY" "$PADDING" "$PADDING" "$c"
            [[ -n "$FONT" ]] && echo "font-family = \"$FONT\""
            [[ "$FONT_SIZE" != 0 ]] && echo "font-size = $FONT_SIZE"
        } > "$gen"
    fi
    _block "$conf" "$LOOK_MARK" "$on" "config-file = ?$gen"
    [[ "$on" == off ]] && rm -f "$gen"
    if [[ "$LIVE" == 1 ]]; then pkill -USR2 -x ghostty 2>/dev/null || true; fi
    log "ghostty look: $on"
}

look_foot() {
    local conf="$XDG_CONFIG_HOME/foot/foot.ini" gen="$DIR/look-foot.ini" on ver sections="colors-dark colors-light" s
    on=$(_state foot "$conf")
    if [[ "$on" == on ]]; then
        ver=$(foot --version 2>/dev/null | sed -n 's/^foot version: \([0-9]*\)\.\([0-9]*\).*/\1 \2/p' || true)
        if [[ -n "$ver" ]] && (( ${ver% *} == 1 && ${ver#* } < 26 )); then sections="colors"; fi
        {
            echo "# Generated by AnoShell apply-terminal.sh (terminal.*)."
            echo "[main]"; echo "pad=${PADDING}x${PADDING}"
            # foot names the family and size together (its default family: monospace).
            if [[ -n "$FONT" || "$FONT_SIZE" != 0 ]]; then
                echo "font=${FONT:-monospace}$([[ "$FONT_SIZE" != 0 ]] && echo ":size=$FONT_SIZE")"
            fi
            echo "[cursor]"; echo "style=$CURSOR"
            for s in $sections; do echo "[$s]"; echo "alpha=$OPACITY"; done
        } > "$gen"
    fi
    _block "$conf" "$LOOK_MARK" "$on" $'[main]\ninclude='"$gen"
    [[ "$on" == off ]] && rm -f "$gen"
    log "foot look: $on (new windows)"
}

# Alacritty imports load before its own file, so your own values win; the
# import goes into your [general] table, or a [general] of its own at the end.
# An import list of your own is left alone (add the file to it yourself).
look_alacritty() {
    local conf="$XDG_CONFIG_HOME/alacritty/alacritty.toml" gen="$DIR/look-alacritty.toml" on shape where=end lines
    on=$(_state alacritty "$conf")
    shape=$CURSOR; shape="${shape^}"
    if [[ "$on" == on && -e "$conf" ]] && _strip "$conf" "$LOOK_MARK" | grep -qE '^[[:space:]]*(general\.)?import[[:space:]]*='; then
        log "WARN: $conf has its own import list: add \"$gen\" to it for the look"
        on=manual
    fi
    if [[ "$on" != off ]]; then
        {
            printf '# Generated by AnoShell apply-terminal.sh (terminal.*).\n[window]\nopacity = %s\n\n[window.padding]\nx = %s\ny = %s\n\n[cursor.style]\nshape = "%s"\n' \
                "$OPACITY" "$PADDING" "$PADDING" "$shape"
            [[ "$FONT_SIZE" != 0 ]] && printf '\n[font]\nsize = %s\n' "$FONT_SIZE"
            [[ -n "$FONT" ]] && printf '\n[font.normal]\nfamily = "%s"\n' "$FONT"
            true
        } > "$gen"
    fi
    [[ "$on" == manual ]] && { log "alacritty look: manual"; return 0; }
    lines="import = [\"$gen\"]"
    if [[ -e "$conf" ]] && _strip "$conf" "$LOOK_MARK" | grep -qx '\[general\]'; then where="after:[general]"
    else lines=$'[general]\n'"$lines"; fi
    _block "$conf" "$LOOK_MARK" "$on" "$lines" "$where"
    [[ "$on" == off ]] && rm -f "$gen"
    log "alacritty look: $on (running windows reload it)"
}

# ── Prompt ───────────────────────────────────────────────────────────────
_col() { # $1 colors.json key, $2 fallback
    local v=""
    [[ -f "$COLORS_JSON" ]] && v=$(jq -r --arg k "$1" '.[$k] // empty' "$COLORS_JSON" 2>/dev/null || true)
    [[ "$v" =~ ^#[0-9a-fA-F]{6}$ ]] && echo "$v" || echo "$2"
}

prompt_files() {
    # Segments: the accent and two quieter shades of it, each with its own
    # readable text colour (the palette's on-colours).
    local p op pc opc sc osc er
    p=$(_col primary '#8ab4f8'); op=$(_col on_primary '#00315f')
    pc=$(_col primary_container '#2c4a76'); opc=$(_col on_primary_container '#d6e3ff')
    sc=$(_col secondary_container '#3e4759'); osc=$(_col on_secondary_container '#dae2f9')
    er=$(_col error '#ffb4ab')
    cat > "$DIR/prompt.env.tmp" <<EOF
# Generated by AnoShell apply-terminal.sh: the prompt style and its colours.
ANO_PROMPT_STYLE=$PROMPT
ANO_P1_BG=$p
ANO_P1_FG=$op
ANO_P2_BG=$pc
ANO_P2_FG=$opc
ANO_P3_BG=$sc
ANO_P3_FG=$osc
ANO_P_ACCENT=$p
ANO_P_ERROR=$er
EOF
    mv "$DIR/prompt.env.tmp" "$DIR/prompt.env"
    cp -f "$SRC/prompt/prompt.zsh" "$SRC/prompt/prompt.bash" "$SRC/prompt/prompt.fish" "$DIR/"
    if command -v starship &>/dev/null && [[ "$PROMPT" != own ]]; then
        "$SRC/prompt/starship.sh" "$PROMPT" "$p" "$op" "$pc" "$opc" "$sc" "$osc" "$er" > "$DIR/starship.toml.tmp" \
            && mv "$DIR/starship.toml.tmp" "$DIR/starship.toml"
    else
        rm -f "$DIR/starship.toml"
    fi
}

prompt_rc() {
    local shells sh rc on
    shells=$(cfg '.terminal.shells | if type == "array" and length > 0 then join(" ") else empty end' "")
    [[ -n "$shells" ]] || shells=$(basename "${SHELL:-bash}")
    for sh in zsh bash fish; do
        case "$sh" in
            zsh) rc="${ZDOTDIR:-$HOME}/.zshrc" ;;
            bash) rc="$HOME/.bashrc" ;;
            fish) rc="$XDG_CONFIG_HOME/fish/config.fish" ;;
        esac
        on=off
        if [[ "$PROMPT" != own && " $shells " == *" $sh "* ]]; then on=on; fi
        # Only files that exist get a line (a new rc file is the shell's business).
        [[ "$on" == on && ! -e "$rc" ]] && { log "$sh: $rc doesn't exist, no prompt line"; continue; }
        if [[ "$sh" == fish ]]; then
            _block "$rc" "$PROMPT_MARK" "$on" "test -r \"$DIR/prompt.fish\"; and source \"$DIR/prompt.fish\""
        else
            _block "$rc" "$PROMPT_MARK" "$on" "[ -r \"$DIR/prompt.$sh\" ] && . \"$DIR/prompt.$sh\""
        fi
        log "$sh prompt: $on"
    done
}

if [[ "$ONLY_PROMPT" == 0 ]]; then
    look_kitty
    look_ghostty
    look_foot
    look_alacritty
    prompt_rc
fi
prompt_files
log "done (looks: $ENABLE, prompt: $PROMPT)"
