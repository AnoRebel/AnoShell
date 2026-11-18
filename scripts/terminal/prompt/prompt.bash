# AnoShell prompt for bash (terminal.prompt; scripts/terminal/apply-terminal.sh copies it next to prompt.env).
# The style and colours are read at every prompt, so a palette change shows in open terminals. With Starship
# installed, Starship draws it from the generated starship.toml instead.
[[ -n ${_ano_prompt_dir-} ]] && return 0
_ano_prompt_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if command -v starship >/dev/null 2>&1 && [[ -r $_ano_prompt_dir/starship.toml ]]; then
    export STARSHIP_CONFIG=$_ano_prompt_dir/starship.toml
    eval "$(starship init bash)"
    return 0
fi
_ano_prompt_own=$PS1
_ano_c() { # $1 38 (text) or 48 (background), $2 #rrggbb
    local h=${2#\#}
    printf '\\[\\e[%s;2;%d;%d;%dm\\]' "$1" "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}
_ano_prompt_cmd() {
    local st=$? sep=$'' b r='\[\e[0m\]'
    [[ -r $_ano_prompt_dir/prompt.env ]] && . "$_ano_prompt_dir/prompt.env"
    case ${ANO_PROMPT_STYLE-own} in
        minimal)
            local a=$ANO_P_ACCENT; (( st )) && a=$ANO_P_ERROR
            PS1="\[\e[1m\]\w$r $(_ano_c 38 "$a")❯$r "
            ;;
        segments)
            b=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
            b=${b//\\/\\\\}; b=${b//\$/\\\$}; b=${b//\`/\\\`}
            PS1="$(_ano_c 48 "$ANO_P1_BG")$(_ano_c 38 "$ANO_P1_FG") \u $(_ano_c 48 "$ANO_P2_BG")$(_ano_c 38 "$ANO_P1_BG")$sep$(_ano_c 38 "$ANO_P2_FG") \w "
            if [[ -n $b ]]; then
                PS1+="$(_ano_c 48 "$ANO_P3_BG")$(_ano_c 38 "$ANO_P2_BG")$sep$(_ano_c 38 "$ANO_P3_FG") $b $r$(_ano_c 38 "$ANO_P3_BG")$sep$r "
            else
                PS1+="$r$(_ano_c 38 "$ANO_P2_BG")$sep$r "
            fi
            (( st )) && PS1+="$(_ano_c 38 "$ANO_P_ERROR")✘$r "
            ;;
        *) PS1=$_ano_prompt_own ;;
    esac
    return $st
}
# First, so it sees the last command's status.
if [[ "$(declare -p PROMPT_COMMAND 2>/dev/null)" == "declare -a"* ]]; then
    PROMPT_COMMAND=(_ano_prompt_cmd "${PROMPT_COMMAND[@]}")
else
    PROMPT_COMMAND="_ano_prompt_cmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
