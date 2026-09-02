_BASH_MODERN_ABBR_NAMES=()
_BASH_MODERN_ABBR_VALUES=()
_BASH_MODERN_ABBR_FILE="${BASH_MODERN_HOME}/user/abbreviations.bash"

if [[ -r ${_BASH_MODERN_ABBR_FILE} ]]; then
    source "${_BASH_MODERN_ABBR_FILE}"
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

_bash_modern_abbr_save() {
    local directory temporary index
    directory=${_BASH_MODERN_ABBR_FILE%/*}
    temporary="${_BASH_MODERN_ABBR_FILE}.tmp.$$"
    mkdir -p "${directory}" || return
    : >"${temporary}" || return
    chmod 600 "${temporary}" 2>/dev/null || true
    for ((index = 0; index < ${#_BASH_MODERN_ABBR_NAMES[@]}; index++)); do
        printf '_BASH_MODERN_ABBR_NAMES[%d]=%q\n' "${index}" "${_BASH_MODERN_ABBR_NAMES[index]}" >>"${temporary}"
        printf '_BASH_MODERN_ABBR_VALUES[%d]=%q\n' "${index}" "${_BASH_MODERN_ABBR_VALUES[index]}" >>"${temporary}"
    done
    mv "${temporary}" "${_BASH_MODERN_ABBR_FILE}"
}

_bash_modern_abbr_usage() {
    cat <<'EOF'
Usage:
  abbr NAME EXPANSION...
  abbr --add NAME EXPANSION...
  abbr --erase NAME...
  abbr --show [NAME...]
  abbr --list

Abbreviations expand when Space or Enter is pressed.
EOF
}

abbr() {
    local action=add name expansion index requested existing
    case ${1:-} in
        -a|--add) shift ;;
        -e|--erase) action=erase; shift ;;
        -s|--show) action=show; shift ;;
        -l|--list) action=list; shift ;;
        -h|--help) _bash_modern_abbr_usage; return ;;
        '') action=list ;;
        -*) printf 'abbr: unknown option: %s\n' "$1" >&2; return 2 ;;
    esac

    case ${action} in
        add)
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
            if index=$(_bash_modern_abbr_find "${name}"); then
                _BASH_MODERN_ABBR_VALUES[index]=${expansion}
            else
                _BASH_MODERN_ABBR_NAMES[${#_BASH_MODERN_ABBR_NAMES[@]}]=${name}
                _BASH_MODERN_ABBR_VALUES[${#_BASH_MODERN_ABBR_VALUES[@]}]=${expansion}
            fi
            _bash_modern_abbr_save
            ;;
        erase)
            (($#)) || { printf 'abbr: --erase requires a name\n' >&2; return 2; }
            for requested in "$@"; do
                if index=$(_bash_modern_abbr_find "${requested}"); then
                    unset '_BASH_MODERN_ABBR_NAMES[index]' '_BASH_MODERN_ABBR_VALUES[index]'
                    _BASH_MODERN_ABBR_NAMES=("${_BASH_MODERN_ABBR_NAMES[@]}")
                    _BASH_MODERN_ABBR_VALUES=("${_BASH_MODERN_ABBR_VALUES[@]}")
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
    local LC_ALL=C line point start character name index replacement
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
