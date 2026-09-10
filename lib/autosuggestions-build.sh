_bash_modern_build_autosuggestions() {
    local target=$1 display_patch=$2 bash_include=$3 renamed=0
    [[ ! -f "${target}/bash-autosuggestions.so" &&
       -f "${target}/bash-autosuggestions.so.disabled" ]] && renamed=1

    # A failed patch or rebuild must not leave an older binary eligible for loading.
    rm -f "${target}/bash-autosuggestions.so" "${target}/.bash-version" \
        "${target}/.bash-modern-display-patch" || return 1
    if ! git -C "${target}" apply --reverse --check "${display_patch}" 2>/dev/null; then
        if ! git -C "${target}" apply --check "${display_patch}" ||
           ! git -C "${target}" apply "${display_patch}"; then
            printf 'bash-modern: autosuggestions display patch does not match the source\n' >&2
            return 1
        fi
    fi
    if ! make -B -C "${target}" all BASH_INCLUDE="${bash_include}" ||
       [[ ! -f "${target}/bash-autosuggestions.so" ]]; then
        rm -f "${target}/bash-autosuggestions.so"
        return 1
    fi
    if [[ ${renamed} -eq 1 ]]; then
        mv "${target}/bash-autosuggestions.so" "${target}/bash-autosuggestions.so.disabled" || return 1
    fi
    printf '%s\n' "${BASH_VERSION}" >"${target}/.bash-version" || return 1
    cp "${display_patch}" "${target}/.bash-modern-display-patch"
}
