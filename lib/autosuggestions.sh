_bash_modern_autosuggestions() {
    local action=$1 directory=${BASH_MODERN_HOME:-${HOME}/.config/bash-modern}
    local executable=${BASH} python
    if [[ ${action} == off ]]; then
        mkdir -p "${directory}/user" || return
        touch "${directory}/user/autosuggestions.disabled" || return
        printf 'disabled by user; applies to new shells\n'
        return
    fi
    if [[ ${action} == allow && -f "${directory}/user/autosuggestions.disabled" ]]; then
        return 1
    fi
    if ! python=$(type -P python3) || [[ ! -r "${directory}/lib/autosuggestions.py" ]]; then
        if [[ ${action} != allow ]]; then
            if [[ ${action} == status && -f "${directory}/user/autosuggestions.disabled" ]]; then
                printf 'disabled by user\n'
            else
                printf 'unverified (Python 3 and the installed probe are required)\n'
            fi
        fi
        [[ ${action} == status ]] && return 0
        return 1
    fi
    [[ -r /proc/$$/exe ]] && executable=/proc/$$/exe
    "${python}" "${directory}/lib/autosuggestions.py" "${action}" \
        --home "${directory}" --bash "${executable}" --version "${BASH_VERSION}"
}
