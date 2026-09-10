_bash_modern_build_autosuggestions() {
    local target=$1 bash_include=$2 renamed=0
    [[ ! -f "${target}/bash-autosuggestions.so" &&
       -f "${target}/bash-autosuggestions.so.disabled" ]] && renamed=1

    # A failed rebuild must not leave an older binary eligible for loading.
    rm -f "${target}/bash-autosuggestions.so" "${target}/.bash-version" || return 1
    if ! make -B -C "${target}" all BASH_INCLUDE="${bash_include}" ||
       [[ ! -f "${target}/bash-autosuggestions.so" ]]; then
        rm -f "${target}/bash-autosuggestions.so"
        return 1
    fi
    if [[ ${renamed} -eq 1 ]]; then
        mv "${target}/bash-autosuggestions.so" "${target}/bash-autosuggestions.so.disabled" || return 1
    fi
    printf '%s\n' "${BASH_VERSION}" >"${target}/.bash-version"
}
