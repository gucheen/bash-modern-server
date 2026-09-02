if _bash_modern_fzf="$(type -P fzf 2>/dev/null)" && [[ -x ${_bash_modern_fzf} ]]; then
    if "${_bash_modern_fzf}" --bash >/dev/null 2>&1; then
        eval "$("${_bash_modern_fzf}" --bash)"
    elif [[ -r "${BASH_MODERN_HOME}/vendor/fzf/shell/key-bindings.bash" ]]; then
        source "${BASH_MODERN_HOME}/vendor/fzf/shell/key-bindings.bash"
        [[ -r "${BASH_MODERN_HOME}/vendor/fzf/shell/completion.bash" ]] && source "${BASH_MODERN_HOME}/vendor/fzf/shell/completion.bash"
    fi
fi

_bash_modern_autosuggestions_version=
if [[ -r "${BASH_MODERN_HOME}/vendor/bash-autosuggestions/.bash-version" ]]; then
    _bash_modern_autosuggestions_version=$(<"${BASH_MODERN_HOME}/vendor/bash-autosuggestions/.bash-version")
fi
if [[ ${_bash_modern_autosuggestions_version} == "${BASH_VERSION}" &&
      -r "${BASH_MODERN_HOME}/vendor/bash-autosuggestions/bash-autosuggestions.bash" &&
      -f "${BASH_MODERN_HOME}/vendor/bash-autosuggestions/bash-autosuggestions.so" ]]; then
    : "${BASH_AUTOSUGGEST_STRATEGY:=match_prev_cmd history}"
    : "${BASH_AUTOSUGGEST_USE_ASYNC:=auto}"
    source "${BASH_MODERN_HOME}/vendor/bash-autosuggestions/bash-autosuggestions.bash"
fi
unset _bash_modern_autosuggestions_version

if [[ -f "${BASH_MODERN_HOME}/user/starship.enabled" ]] &&
   _bash_modern_starship="$(type -P starship 2>/dev/null)" && [[ -x ${_bash_modern_starship} ]]; then
    if [[ -f "${BASH_MODERN_HOME}/user/git-status.enabled" ]]; then
        export STARSHIP_CONFIG="${BASH_MODERN_HOME}/starship-git.toml"
    else
        export STARSHIP_CONFIG="${BASH_MODERN_HOME}/starship.toml"
    fi
    if _bash_modern_starship_init=$("${_bash_modern_starship}" init bash 2>/dev/null); then
        eval "${_bash_modern_starship_init}"
        _BASH_MODERN_STARSHIP_ACTIVE=1
    fi
fi

unset _bash_modern_fzf _bash_modern_starship _bash_modern_starship_init
