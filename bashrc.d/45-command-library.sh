_BASH_MODERN_COMMAND_SOURCES=()

_bash_modern_source_command_file() {
    local path=$1 trust=${2:-managed}
    [[ -f ${path} && -r ${path} ]] || return 0
    if [[ ${trust} == private ]] && ! _bash_modern_is_private_source "${path}"; then
        printf 'bash-modern: skipped writable or foreign-owned command source: %s\n' "${path}" >&2
        return
    fi
    source "${path}"
    _BASH_MODERN_COMMAND_SOURCES+=("${path}")
}

_bash_modern_source_command_dir() {
    local directory=$1 trust=${2:-managed} path
    [[ -d ${directory} ]] || return 0
    if [[ ${trust} == private ]] && ! _bash_modern_is_private_source "${directory}"; then
        printf 'bash-modern: skipped writable or foreign-owned command directory: %s\n' "${directory}" >&2
        return
    fi
    for path in "${directory}"/*.sh; do
        [[ -e ${path} ]] || continue
        _bash_modern_source_command_file "${path}" "${trust}"
    done
}

_bash_modern_trim() {
    local value=$1
    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "${value}"
}

cmds() {
    local query= line payload category remainder signature description haystack found=0 index order_index source_index width
    local -a categories=() signatures=() descriptions=() category_order=()
    local source

    case ${1:-} in
        -h|--help)
            printf 'Usage: cmds [SEARCH]\n       cmds --sources\n'
            return
            ;;
        --sources)
            ((${#_BASH_MODERN_COMMAND_SOURCES[@]})) && printf '%s\n' "${_BASH_MODERN_COMMAND_SOURCES[@]}"
            return
            ;;
    esac
    (($# <= 1)) || { printf 'cmds: expected zero or one search term\n' >&2; return 2; }
    query=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')

    for ((source_index = 0; source_index < ${#_BASH_MODERN_COMMAND_SOURCES[@]}; source_index++)); do
        source=${_BASH_MODERN_COMMAND_SOURCES[source_index]}
        while IFS= read -r line || [[ -n ${line} ]]; do
            [[ ${line} =~ ^[[:space:]]*#[[:space:]]*@cmd[[:space:]]+(.+) ]] || continue
            payload=${BASH_REMATCH[1]}
            [[ ${payload} == *'|'* ]] || continue
            category=$(_bash_modern_trim "${payload%%|*}")
            remainder=${payload#*|}
            [[ ${remainder} == *'|'* ]] || continue
            signature=$(_bash_modern_trim "${remainder%%|*}")
            description=$(_bash_modern_trim "${remainder#*|}")
            [[ -n ${category} && -n ${signature} && -n ${description} ]] || continue
            haystack=$(printf '%s %s %s' "${category}" "${signature}" "${description}" | tr '[:upper:]' '[:lower:]')
            [[ -z ${query} || ${haystack} == *"${query}"* ]] || continue
            categories+=("${category}")
            signatures+=("${signature}")
            descriptions+=("${description}")
        done <"${source}"
    done

    for ((index = 0; index < ${#categories[@]}; index++)); do
        category=${categories[index]}
        for ((order_index = 0; order_index < ${#category_order[@]}; order_index++)); do
            [[ ${category_order[order_index]} == "${category}" ]] && continue 2
        done
        category_order+=("${category}")
    done

    for ((order_index = 0; order_index < ${#category_order[@]}; order_index++)); do
        category=${category_order[order_index]}
        ((found)) && printf '\n'
        printf '%s\n' "${category}"
        width=0
        for ((index = 0; index < ${#categories[@]}; index++)); do
            [[ ${categories[index]} == "${category}" ]] || continue
            ((${#signatures[index]} > width)) && width=${#signatures[index]}
        done
        for ((index = 0; index < ${#categories[@]}; index++)); do
            [[ ${categories[index]} == "${category}" ]] || continue
            printf '  %-*s  %s\n' "${width}" "${signatures[index]}" "${descriptions[index]}"
            found=1
        done
    done

    ((found)) || { printf 'cmds: no commands match %q\n' "${1:-}" >&2; return 1; }
}

_bash_modern_source_command_dir "${BASH_MODERN_HOME}/commands.d"

: "${BASH_MODERN_COMMANDS_HOME:=${XDG_CONFIG_HOME:-${HOME}/.config}/bash-modern-commands}"
if [[ -d ${BASH_MODERN_COMMANDS_HOME} ]]; then
    if _bash_modern_is_private_source "${BASH_MODERN_COMMANDS_HOME}"; then
        _bash_modern_source_command_dir "${BASH_MODERN_COMMANDS_HOME}/commands.d" private
        _bash_modern_source_command_file "${BASH_MODERN_COMMANDS_HOME}/abbreviations.sh" private
    else
        printf 'bash-modern: skipped writable or foreign-owned command directory: %s\n' "${BASH_MODERN_COMMANDS_HOME}" >&2
    fi
fi

if [[ ! -e ${BASH_MODERN_HOME}/user/local.sh ]] || _bash_modern_is_private_source "${BASH_MODERN_HOME}/user"; then
    _bash_modern_source_command_file "${BASH_MODERN_HOME}/user/local.sh" private
else
    printf 'bash-modern: skipped writable or foreign-owned local config directory: %s\n' "${BASH_MODERN_HOME}/user" >&2
fi

true
