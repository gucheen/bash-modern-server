# Long-lived, append-only history is useful when administering multiple servers.
HISTCONTROL=ignoreboth:erasedups
HISTSIZE=20000
HISTFILESIZE=50000
HISTTIMEFORMAT='%F %T  '
shopt -s histappend

_bash_modern_history_sync() {
    builtin history -a
    builtin history -n
}

if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
    _bash_modern_has_history_sync=0
    for _bash_modern_prompt_hook in "${PROMPT_COMMAND[@]}"; do
        [[ ${_bash_modern_prompt_hook} == _bash_modern_history_sync ]] && _bash_modern_has_history_sync=1
    done
    if [[ ${_bash_modern_has_history_sync} -eq 0 ]]; then
        PROMPT_COMMAND=(_bash_modern_history_sync "${PROMPT_COMMAND[@]}")
    fi
    unset _bash_modern_has_history_sync _bash_modern_prompt_hook
else
    case ";${PROMPT_COMMAND-};" in
        *';_bash_modern_history_sync;'*) ;;
        *) PROMPT_COMMAND="_bash_modern_history_sync${PROMPT_COMMAND:+; ${PROMPT_COMMAND}}" ;;
    esac
fi
