if _bash_modern_fzf="$(type -P fzf 2>/dev/null)" && [[ -x ${_bash_modern_fzf} ]]; then
    if "${_bash_modern_fzf}" --bash >/dev/null 2>&1; then
        eval "$("${_bash_modern_fzf}" --bash)"
    elif [[ -r "${BASH_MODERN_HOME}/vendor/fzf/shell/key-bindings.bash" ]]; then
        source "${BASH_MODERN_HOME}/vendor/fzf/shell/key-bindings.bash"
        [[ -r "${BASH_MODERN_HOME}/vendor/fzf/shell/completion.bash" ]] && source "${BASH_MODERN_HOME}/vendor/fzf/shell/completion.bash"
    fi
fi

if _bash_modern_starship="$(type -P starship 2>/dev/null)" && [[ -x ${_bash_modern_starship} ]]; then
    export STARSHIP_CONFIG="${BASH_MODERN_HOME}/starship.toml"
    eval "$("${_bash_modern_starship}" init bash)"
fi

unset _bash_modern_fzf _bash_modern_starship
