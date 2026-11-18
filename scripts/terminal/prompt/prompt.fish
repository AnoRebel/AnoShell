# AnoShell prompt for fish (terminal.prompt; scripts/terminal/apply-terminal.sh copies it next to prompt.env).
# The style and colours are read at every prompt, so a palette change shows in open terminals. With Starship
# installed, Starship draws it from the generated starship.toml instead.
set -q _ano_prompt_dir; and return 0
set -g _ano_prompt_dir (path dirname (status filename))
if command -q starship; and test -r $_ano_prompt_dir/starship.toml
    set -gx STARSHIP_CONFIG $_ano_prompt_dir/starship.toml
    starship init fish | source
    return 0
end
functions -q fish_prompt; and functions -c fish_prompt _ano_own_fish_prompt
function _ano_hex
    string replace '#' '' -- $argv[1]
end
function fish_prompt
    set -l st $status
    if test -r $_ano_prompt_dir/prompt.env
        for line in (string match -r '^ANO_[A-Z0-9_]+=.*$' < $_ano_prompt_dir/prompt.env)
            set -l kv (string split -m1 = -- $line)
            set -g $kv[1] $kv[2]
        end
    end
    set -l sep 
    switch "$ANO_PROMPT_STYLE"
        case minimal
            set -l a (_ano_hex $ANO_P_ACCENT)
            test $st -ne 0; and set a (_ano_hex $ANO_P_ERROR)
            set_color --bold; echo -n (prompt_pwd)
            set_color normal; echo -n ' '
            set_color $a; echo -n '❯ '
            set_color normal
        case segments
            set -l b (git symbolic-ref --short HEAD 2>/dev/null; or git rev-parse --short HEAD 2>/dev/null)
            set_color -b (_ano_hex $ANO_P1_BG) (_ano_hex $ANO_P1_FG); echo -n " $USER "
            set_color -b (_ano_hex $ANO_P2_BG) (_ano_hex $ANO_P1_BG); echo -n $sep
            set_color (_ano_hex $ANO_P2_FG); echo -n ' '(prompt_pwd)' '
            if test -n "$b"
                set_color -b (_ano_hex $ANO_P3_BG) (_ano_hex $ANO_P2_BG); echo -n $sep
                set_color (_ano_hex $ANO_P3_FG); echo -n " $b "
                set_color normal; set_color (_ano_hex $ANO_P3_BG); echo -n $sep
            else
                set_color normal; set_color (_ano_hex $ANO_P2_BG); echo -n $sep
            end
            set_color normal; echo -n ' '
            if test $st -ne 0
                set_color (_ano_hex $ANO_P_ERROR); echo -n '✘ '; set_color normal
            end
        case '*'
            functions -q _ano_own_fish_prompt; and _ano_own_fish_prompt; or echo -n '> '
    end
end
