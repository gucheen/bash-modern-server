_bash_modern_file_mode() {
    if stat -Lc '%u %a' "$1" 2>/dev/null; then
        return
    fi
    stat -L -f '%u %Lp' "$1" 2>/dev/null
}

_bash_modern_is_private_source() {
    local path=$1 owner mode
    read -r owner mode < <(_bash_modern_file_mode "${path}") || return 1
    [[ ${owner} == "${EUID}" ]] || return 1
    (( (8#${mode} & 0022) == 0 ))
}

_BASH_MODERN_ABBR_NAMES=()
_BASH_MODERN_ABBR_VALUES=()
_BASH_MODERN_ABBR_LOCAL_NAMES=()
_BASH_MODERN_ABBR_SHARED_NAMES=()
_BASH_MODERN_ABBR_SHARED_VALUES=()
_BASH_MODERN_ABBR_FILE="${BASH_MODERN_HOME}/user/abbreviations.bash"

if [[ -r ${_BASH_MODERN_ABBR_FILE} ]]; then
    if _bash_modern_is_private_source "${_BASH_MODERN_ABBR_FILE%/*}" &&
       _bash_modern_is_private_source "${_BASH_MODERN_ABBR_FILE}"; then
        source "${_BASH_MODERN_ABBR_FILE}"
    else
        printf 'bash-modern: skipped writable or foreign-owned abbreviation file: %s\n' "${_BASH_MODERN_ABBR_FILE}" >&2
    fi
fi
if ((${#_BASH_MODERN_ABBR_NAMES[@]})); then
    _BASH_MODERN_ABBR_LOCAL_NAMES=("${_BASH_MODERN_ABBR_NAMES[@]}")
fi

_bash_modern_abbr_find() {
    local name=$1 index
    for ((index = 0; index < ${#_BASH_MODERN_ABBR_NAMES[@]}; index++)); do
        if [[ ${_BASH_MODERN_ABBR_NAMES[index]} == "${name}" ]]; then
            printf '%s\n' "${index}"
            return 0
        fi
    done
    return 1
}

_bash_modern_abbr_shared_find() {
    local name=$1 index
    for ((index = 0; index < ${#_BASH_MODERN_ABBR_SHARED_NAMES[@]}; index++)); do
        if [[ ${_BASH_MODERN_ABBR_SHARED_NAMES[index]} == "${name}" ]]; then
            printf '%s\n' "${index}"
            return 0
        fi
    done
    return 1
}

_bash_modern_abbr_save() {
    local directory temporary name index local_index
    local -a saved_names=()
    directory=${_BASH_MODERN_ABBR_FILE%/*}
    temporary="${_BASH_MODERN_ABBR_FILE}.tmp.$$"
    mkdir -p "${directory}" || return
    chmod go-w "${directory}" 2>/dev/null || return
    : >"${temporary}" || return
    chmod 600 "${temporary}" 2>/dev/null || true
    for ((local_index = 0; local_index < ${#_BASH_MODERN_ABBR_LOCAL_NAMES[@]}; local_index++)); do
        name=${_BASH_MODERN_ABBR_LOCAL_NAMES[local_index]}
        index=$(_bash_modern_abbr_find "${name}") || continue
        printf '_BASH_MODERN_ABBR_NAMES[%d]=%q\n' "${#saved_names[@]}" "${name}" >>"${temporary}"
        printf '_BASH_MODERN_ABBR_VALUES[%d]=%q\n' "${#saved_names[@]}" "${_BASH_MODERN_ABBR_VALUES[index]}" >>"${temporary}"
        saved_names+=("${name}")
    done
    mv "${temporary}" "${_BASH_MODERN_ABBR_FILE}"
}

_bash_modern_abbr_is_local() {
    local requested=$1 index
    for ((index = 0; index < ${#_BASH_MODERN_ABBR_LOCAL_NAMES[@]}; index++)); do
        [[ ${_BASH_MODERN_ABBR_LOCAL_NAMES[index]} == "${requested}" ]] && return 0
    done
    return 1
}

_bash_modern_abbr_mark_local() {
    _bash_modern_abbr_is_local "$1" || _BASH_MODERN_ABBR_LOCAL_NAMES+=("$1")
}

_bash_modern_abbr_usage() {
    cat <<'EOF'
Usage:
  abbr NAME EXPANSION...
  abbr --add NAME EXPANSION...
  abbr --define NAME EXPANSION...
  abbr --erase NAME...
  abbr --show [NAME...]
  abbr --list

Abbreviations expand when Space or Enter is pressed.
--add persists a personal abbreviation; --define declares one for this shell.
EOF
}

abbr() {
    local action=add name expansion index requested existing
    case ${1:-} in
        -a|--add) shift ;;
        -d|--define) action=define; shift ;;
        -e|--erase) action=erase; shift ;;
        -s|--show) action=show; shift ;;
        -l|--list) action=list; shift ;;
        -h|--help) _bash_modern_abbr_usage; return ;;
        '') action=list ;;
        -*) printf 'abbr: unknown option: %s\n' "$1" >&2; return 2 ;;
    esac

    case ${action} in
        add|define)
            (($# >= 2)) || { _bash_modern_abbr_usage >&2; return 2; }
            name=$1
            shift
            case ${name} in
                ''|*[![:alnum:]_.+-]*)
                    printf 'abbr: invalid name: %s\n' "${name}" >&2
                    return 2
                    ;;
            esac
            expansion=$*
            [[ ${expansion} != *$'\n'* && ${expansion} != *$'\t'* ]] || {
                printf 'abbr: expansion must be a single line without tabs\n' >&2
                return 2
            }
            if [[ ${action} == define ]]; then
                if index=$(_bash_modern_abbr_shared_find "${name}"); then
                    _BASH_MODERN_ABBR_SHARED_VALUES[index]=${expansion}
                else
                    _BASH_MODERN_ABBR_SHARED_NAMES[${#_BASH_MODERN_ABBR_SHARED_NAMES[@]}]=${name}
                    _BASH_MODERN_ABBR_SHARED_VALUES[${#_BASH_MODERN_ABBR_SHARED_VALUES[@]}]=${expansion}
                fi
            fi
            if index=$(_bash_modern_abbr_find "${name}"); then
                if [[ ${action} == add ]] || ! _bash_modern_abbr_is_local "${name}"; then
                    _BASH_MODERN_ABBR_VALUES[index]=${expansion}
                fi
            elif [[ ${action} == add ]] || ! _bash_modern_abbr_is_local "${name}"; then
                _BASH_MODERN_ABBR_NAMES[${#_BASH_MODERN_ABBR_NAMES[@]}]=${name}
                _BASH_MODERN_ABBR_VALUES[${#_BASH_MODERN_ABBR_VALUES[@]}]=${expansion}
            fi
            if [[ ${action} == add ]]; then
                _bash_modern_abbr_mark_local "${name}"
                _bash_modern_abbr_save
            fi
            ;;
        erase)
            (($#)) || { printf 'abbr: --erase requires a name\n' >&2; return 2; }
            for requested in "$@"; do
                if ! _bash_modern_abbr_is_local "${requested}"; then
                    printf 'abbr: %s is declared by a command pack; edit that source to remove it\n' "${requested}" >&2
                    continue
                fi
                if index=$(_bash_modern_abbr_find "${requested}"); then
                    unset '_BASH_MODERN_ABBR_NAMES[index]' '_BASH_MODERN_ABBR_VALUES[index]'
                    if ((${#_BASH_MODERN_ABBR_NAMES[@]})); then
                        _BASH_MODERN_ABBR_NAMES=("${_BASH_MODERN_ABBR_NAMES[@]}")
                        _BASH_MODERN_ABBR_VALUES=("${_BASH_MODERN_ABBR_VALUES[@]}")
                    else
                        _BASH_MODERN_ABBR_NAMES=()
                        _BASH_MODERN_ABBR_VALUES=()
                    fi
                fi
                for ((index = 0; index < ${#_BASH_MODERN_ABBR_LOCAL_NAMES[@]}; index++)); do
                    if [[ ${_BASH_MODERN_ABBR_LOCAL_NAMES[index]} == "${requested}" ]]; then
                        unset '_BASH_MODERN_ABBR_LOCAL_NAMES[index]'
                        if ((${#_BASH_MODERN_ABBR_LOCAL_NAMES[@]})); then
                            _BASH_MODERN_ABBR_LOCAL_NAMES=("${_BASH_MODERN_ABBR_LOCAL_NAMES[@]}")
                        else
                            _BASH_MODERN_ABBR_LOCAL_NAMES=()
                        fi
                        break
                    fi
                done
                if index=$(_bash_modern_abbr_shared_find "${requested}"); then
                    _BASH_MODERN_ABBR_NAMES[${#_BASH_MODERN_ABBR_NAMES[@]}]=${requested}
                    _BASH_MODERN_ABBR_VALUES[${#_BASH_MODERN_ABBR_VALUES[@]}]=${_BASH_MODERN_ABBR_SHARED_VALUES[index]}
                fi
            done
            _bash_modern_abbr_save
            ;;
        show)
            for ((index = 0; index < ${#_BASH_MODERN_ABBR_NAMES[@]}; index++)); do
                if (($#)); then
                    existing=0
                    for requested in "$@"; do
                        [[ ${_BASH_MODERN_ABBR_NAMES[index]} == "${requested}" ]] && existing=1
                    done
                    [[ ${existing} -eq 1 ]] || continue
                fi
                printf 'abbr --add %q %q\n' "${_BASH_MODERN_ABBR_NAMES[index]}" "${_BASH_MODERN_ABBR_VALUES[index]}"
            done
            ;;
        list)
            ((${#_BASH_MODERN_ABBR_NAMES[@]})) && printf '%s\n' "${_BASH_MODERN_ABBR_NAMES[@]}"
            ;;
    esac
}

_bash_modern_abbr_expand() {
    local LC_ALL=C line point start character name index replacement command_prefix
    line=${READLINE_LINE-}
    point=${READLINE_POINT:-0}
    start=${point}
    while ((start > 0)); do
        character=${line:start-1:1}
        case ${character} in
            [[:alnum:]_.+-]) start=$((start - 1)) ;;
            *) break ;;
        esac
    done
    ((start < point)) || return
    if ((start > 0)); then
        character=${line:start-1:1}
        case ${character} in
            [[:space:]\;\|\&\(\)]) ;;
            *) return ;;
        esac
    fi
    name=${line:start:point-start}
    command_prefix=${line:0:start}
    command_prefix=${command_prefix##*[\;\|\&\(]}
    [[ ${command_prefix} =~ ^[[:space:]]*abbr[[:space:]] ]] && return
    index=$(_bash_modern_abbr_find "${name}") || return
    replacement=${_BASH_MODERN_ABBR_VALUES[index]}
    READLINE_LINE=${line:0:start}${replacement}${line:point}
    READLINE_POINT=$((start + ${#replacement}))
}

_bash_modern_abbr_expand_space() {
    local line point
    _bash_modern_abbr_expand
    line=${READLINE_LINE-}
    point=${READLINE_POINT:-0}
    READLINE_LINE=${line:0:point}' '${line:point}
    READLINE_POINT=$((point + 1))
}

for _bash_modern_abbr_keymap in emacs-standard vi-insertion; do
    bind -m "${_bash_modern_abbr_keymap}" -x '" ":_bash_modern_abbr_expand_space' 2>/dev/null || true
    bind -m "${_bash_modern_abbr_keymap}" -x '"\C-x\C-a":_bash_modern_abbr_expand' 2>/dev/null || true
    bind -m "${_bash_modern_abbr_keymap}" '"\C-M": "\C-x\C-a\C-J"' 2>/dev/null || true
done
unset _bash_modern_abbr_keymap
