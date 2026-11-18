# AnoShell prompt for zsh (terminal.prompt; scripts/terminal/apply-terminal.sh copies it next to prompt.env).
# The style and colours are read at every prompt, so a palette change shows in open terminals. With Starship
# installed, Starship draws it from the generated starship.toml instead.
[[ -n ${_ano_prompt_dir-} ]] && return 0
typeset -g _ano_prompt_dir=${${(%):-%x}:A:h}
if (( $+commands[starship] )) && [[ -r $_ano_prompt_dir/starship.toml ]]; then
    export STARSHIP_CONFIG=$_ano_prompt_dir/starship.toml
    eval "$(starship init zsh)"
    return 0
fi
typeset -g _ano_prompt_own=$PROMPT
_ano_prompt_precmd() {
    local st=$? sep=$'' b
    [[ -r $_ano_prompt_dir/prompt.env ]] && source $_ano_prompt_dir/prompt.env
    case ${ANO_PROMPT_STYLE-own} in
        minimal)
            PROMPT="%B%~%b %F{${ANO_P_ACCENT}}❯%f "
            (( st )) && PROMPT="%B%~%b %F{${ANO_P_ERROR}}❯%f "
            ;;
        segments)
            b=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
            b=${b//\%/%%}
            PROMPT="%K{${ANO_P1_BG}}%F{${ANO_P1_FG}} %n %K{${ANO_P2_BG}}%F{${ANO_P1_BG}}${sep}%F{${ANO_P2_FG}} %~ "
            if [[ -n $b ]]; then
                PROMPT+="%K{${ANO_P3_BG}}%F{${ANO_P2_BG}}${sep}%F{${ANO_P3_FG}} ${b} %k%F{${ANO_P3_BG}}${sep}%f "
            else
                PROMPT+="%k%F{${ANO_P2_BG}}${sep}%f "
            fi
            (( st )) && PROMPT+="%F{${ANO_P_ERROR}}✘%f "
            ;;
        *) PROMPT=$_ano_prompt_own ;;
    esac
    return $st
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _ano_prompt_precmd
