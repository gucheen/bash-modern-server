if [[ ${_BASH_MODERN_STARSHIP_ACTIVE:-0} -ne 1 ]]; then
    _bash_modern_git_prompt() {
        [[ -f "${BASH_MODERN_HOME}/user/git-status.enabled" ]] || return
        command -v git >/dev/null 2>&1 || return

        local output line branch= detached= dirty= ahead= behind=
        output=$(command git status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null) || return
        while IFS= read -r line; do
            case ${line} in
                '# branch.head '*) branch=${line#\# branch.head } ;;
                '# branch.oid '*) detached=${line#\# branch.oid } ;;
                '# branch.ab '*)
                    line=${line#\# branch.ab }
                    ahead=${line%% *}
                    behind=${line##* }
                    ahead=${ahead#+}
                    behind=${behind#-}
                    ;;
                [12u?]' '*) dirty='*' ;;
            esac
        done <<<"${output}"

        [[ ${branch} == '(detached)' ]] && branch="${detached:0:8}"
        [[ -n ${branch} && ${branch} != '(initial)' ]] || return
        printf ' \[\e[35m\]%s' "${branch}"
        [[ -n ${ahead} && ${ahead} != 0 ]] && printf '↑%s' "${ahead}"
        [[ -n ${behind} && ${behind} != 0 ]] && printf '↓%s' "${behind}"
        [[ -n ${dirty} ]] && printf '%s' "${dirty}"
        printf '\[\e[0m\]'
    }

    _bash_modern_prompt_update() {
        local exit_code=$? user_style='2;37' character_style='32' git_segment=
        [[ ${EUID} -eq 0 ]] && user_style='1;31'
        ((exit_code)) && character_style='1;31'
        git_segment=$(_bash_modern_git_prompt)

        PS1="\\[\\e[${user_style}m\\]\\u@\\h\\[\\e[0m\\] \\[\\e[1;36m\\]\\w\\[\\e[0m\\]${git_segment}"
        ((exit_code)) && PS1+=" \\[\\e[1;31m\\][${exit_code}]\\[\\e[0m\\]"
        PS1+=" \\[\\e[${character_style}m\\]\\$\\[\\e[0m\\] "
    }

    # systemd's PS0 substitution would print literally with promptvars disabled.
    PS0=${PS0-}
    PS0=${PS0//'$(__systemd_osc_context_ps0)'/}
    shopt -u promptvars
    if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
        _bash_modern_prompt_commands=()
        for _bash_modern_prompt_command in "${PROMPT_COMMAND[@]}"; do
            case ${_bash_modern_prompt_command} in
                _bash_modern_prompt_update|__systemd_osc_context_precmdline) ;;
                *) _bash_modern_prompt_commands+=("${_bash_modern_prompt_command}") ;;
            esac
        done
        PROMPT_COMMAND=(_bash_modern_prompt_update "${_bash_modern_prompt_commands[@]}")
        unset _bash_modern_prompt_commands _bash_modern_prompt_command
    else
        [[ ${PROMPT_COMMAND-} != __systemd_osc_context_precmdline ]] || PROMPT_COMMAND=
        case ";${PROMPT_COMMAND-};" in
            *';_bash_modern_prompt_update;'*) ;;
            *) PROMPT_COMMAND="_bash_modern_prompt_update${PROMPT_COMMAND:+; ${PROMPT_COMMAND}}" ;;
        esac
    fi
fi
unset _BASH_MODERN_STARSHIP_ACTIVE
