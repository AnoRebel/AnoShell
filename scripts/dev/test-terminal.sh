#!/usr/bin/env bash
# Check for scripts/terminal/apply-terminal.sh against throwaway configs (nothing of yours is read or changed).
# Run: bash scripts/dev/test-terminal.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_STATE_HOME="$T/home/.local/state" ANOSHELL_NO_LIVE=1 SHELL=/usr/bin/zsh
unset ZDOTDIR
# The terminals count as installed (stubs; foot reports a version), starship as missing.
mkdir -p "$T/bin" && for t in kitty ghostty alacritty; do printf '#!/bin/sh\nexit 0\n' > "$T/bin/$t"; done
printf '#!/bin/sh\necho "foot version: 1.28.0"\n' > "$T/bin/foot"; chmod +x "$T/bin/"*
export PATH="$T/bin:/usr/bin:/bin"
fail() { echo "FAIL: $*"; exit 1; }
C=$XDG_CONFIG_HOME
mkdir -p "$C/kitty" "$C/foot" "$C/ghostty" "$C/alacritty" "$C/anoshell" "$XDG_STATE_HOME/anoshell/generated"
printf 'font_size 11\n' > "$C/kitty/kitty.conf"
printf '[main]\nfont=monospace:size=11\n' > "$C/foot/foot.ini"
printf 'font-size = 11\n' > "$C/ghostty/config"
printf '[general]\nlive_config_reload = true\n\n[font]\nsize = 11\n' > "$C/alacritty/alacritty.toml"
printf 'echo hi\n' > "$HOME/.zshrc"; printf 'echo hi\n' > "$HOME/.bashrc"
cp -r "$C" "$T/orig"; cp "$HOME/.zshrc" "$HOME/.bashrc" "$T/orig/"
printf '{"primary":"#aabbcc","on_primary":"#112233","primary_container":"#334455","on_primary_container":"#ddeeff","secondary_container":"#445566","on_secondary_container":"#eeeeee","error":"#ff0000"}\n' \
    > "$XDG_STATE_HOME/anoshell/generated/colors.json"
G="$XDG_STATE_HOME/anoshell/generated/terminal"
run() { bash "$ROOT/scripts/terminal/apply-terminal.sh" "$@" >/dev/null; }

# Off by default: nothing changes.
echo '{}' > "$C/anoshell/config.json"
run
diff -r "$T/orig/kitty" "$C/kitty" >/dev/null || fail "looks off by default changed kitty.conf"
cmp -s "$T/orig/.zshrc" "$HOME/.zshrc" || fail "own prompt changed .zshrc"

# On: one block each, the look files, backups.
echo '{"terminal":{"enable":true,"background":"translucent","opacity":0.8,"padding":10,"cursor":"underline","prompt":"segments"}}' > "$C/anoshell/config.json"
run
grep -q "^include $G/look-kitty.conf$" "$C/kitty/kitty.conf" || fail "kitty include"
grep -q '^background_opacity 0.8$' "$G/look-kitty.conf" && grep -q '^cursor_shape underline$' "$G/look-kitty.conf" || fail "kitty look"
grep -q "^config-file = ?$G/look-ghostty$" "$C/ghostty/config" || fail "ghostty include"
grep -q '^window-padding-x = 10$' "$G/look-ghostty" || fail "ghostty look"
grep -q "^include=$G/look-foot.ini$" "$C/foot/foot.ini" && grep -q '^alpha=0.8$' "$G/look-foot.ini" || fail "foot"
grep -q '^\[colors-dark\]$' "$G/look-foot.ini" || fail "foot 1.28 sections"
awk '/^\[general\]$/{g=1;next} g&&/^import = /{print;exit}' "$C/alacritty/alacritty.toml" | grep -q "$G/look-alacritty.toml" || fail "alacritty import inside [general]"
[[ $(grep -c '^\[general\]$' "$C/alacritty/alacritty.toml") == 1 ]] || fail "alacritty: one [general]"
python3 -c "import tomllib,sys;tomllib.load(open(sys.argv[1],'rb'));tomllib.load(open(sys.argv[2],'rb'))" "$C/alacritty/alacritty.toml" "$G/look-alacritty.toml" || fail "alacritty toml"
for f in kitty/kitty.conf foot/foot.ini ghostty/config alacritty/alacritty.toml; do [[ -e "$C/$f.ano-backup" ]] || fail "backup of $f"; done
grep -q "prompt.zsh" "$HOME/.zshrc" || fail "zsh line (login shell)"
grep -q "anoshell-prompt" "$HOME/.bashrc" && fail "bash line though not enabled"
grep -q '^ANO_P1_BG=#aabbcc$' "$G/prompt.env" || fail "prompt colours"

# Again: nothing more is added.
cp "$C/kitty/kitty.conf" "$T/k1"; cp "$C/alacritty/alacritty.toml" "$T/a1"; run
cmp -s "$T/k1" "$C/kitty/kitty.conf" && cmp -s "$T/a1" "$C/alacritty/alacritty.toml" || fail "second run changed the configs"

# With Starship installed it draws the prompt from the generated config (zsh in a real pty, fish).
pty_zsh() { printf 'exit\n' | script -qec "env HOME=$HOME ZDOTDIR=$HOME zsh -i" /dev/null 2>/dev/null || true; }
if command -v starship >/dev/null; then
    [[ -s "$G/starship.toml" ]] || fail "starship.toml not generated"
    out=$(pty_zsh); [[ "$out" == *'48;2;170;187;204'* ]] || fail "zsh via starship: $(printf '%q' "${out:0:200}")"
    if command -v fish >/dev/null; then
        out=$(fish --no-config -c "source '$G/prompt.fish'; fish_prompt")
        [[ "$out" == *'48;2;170;187;204'* ]] || fail "fish via starship: $(printf '%q' "${out:0:200}")"
    fi
    rm "$G/starship.toml"   # the native prompts below
fi
# The native prompt renders: in a real pty (zsh), expanded (bash), and fish.
out=$(pty_zsh)
[[ "$out" == *$'\e[48;2;170;187;204m'* ]] || fail "zsh segments prompt in a pty: $(printf '%q' "${out:0:200}")"
if command -v fish >/dev/null; then
    out=$(fish --no-config -c "source '$G/prompt.fish'; fish_prompt")
    [[ "$out" == *'aabbcc'* || "$out" == *'48;2;170;187;204'* ]] || fail "fish segments: $(printf '%q' "${out:0:200}")"
fi
out=$(bash --norc -c ". '$G/prompt.bash'; _ano_prompt_cmd; echo \"\${PS1@P}\"")
[[ "$out" == *$'\e[48;2;170;187;204m'*"$USER"* ]] || fail "bash segments prompt"
sed -i 's/^ANO_PROMPT_STYLE=.*/ANO_PROMPT_STYLE=minimal/' "$G/prompt.env"
out=$(bash --norc -c ". '$G/prompt.bash'; false; _ano_prompt_cmd; echo \"\${PS1@P}\"")
[[ "$out" == *$'\e[38;2;255;0;0m'* ]] || fail "bash minimal: the arrow takes the error colour after a failure"
out=$(zsh -fc "source '$G/prompt.zsh'; _ano_prompt_precmd; print -P \"\$PROMPT\"")
[[ "$out" == *'❯'* ]] || fail "zsh minimal"
if command -v fish >/dev/null; then
    out=$(fish --no-config -c "source '$G/prompt.fish'; false; fish_prompt")
    [[ "$out" == *'❯'* && ( "$out" == *'38;2;255;0;0'* || "$out" == *'ff0000'* ) ]] || fail "fish minimal error arrow: $(printf '%q' "$out")"
fi

# Palette change: --prompt rewrites the colours only.
sed -i 's/#aabbcc/#010203/' "$XDG_STATE_HOME/anoshell/generated/colors.json"
cp "$C/kitty/kitty.conf" "$T/k2"; run --prompt
grep -q '^ANO_P1_BG=#010203$' "$G/prompt.env" || fail "--prompt new colours"
cmp -s "$T/k2" "$C/kitty/kitty.conf" || fail "--prompt touched kitty"

# A user's own alacritty import list is left alone.
printf 'import = ["~/x.toml"]\n' > "$C/alacritty/alacritty.toml"; run
[[ "$(cat "$C/alacritty/alacritty.toml")" == 'import = ["~/x.toml"]' ]] || fail "own import list touched"

# Off again: every config back as it was.
cp "$T/orig/alacritty/alacritty.toml" "$C/alacritty/alacritty.toml"; run
echo '{"terminal":{"enable":false,"prompt":"own"}}' > "$C/anoshell/config.json"; run
for f in kitty/kitty.conf foot/foot.ini ghostty/config alacritty/alacritty.toml; do cmp -s "$T/orig/$f" "$C/$f" || fail "$f not restored: $(diff "$T/orig/$f" "$C/$f")"; done
cmp -s "$T/orig/.zshrc" "$HOME/.zshrc" || fail ".zshrc not restored"
[[ ! -e "$G/look-kitty.conf" ]] || fail "look file left behind"
echo "terminal: ok"
