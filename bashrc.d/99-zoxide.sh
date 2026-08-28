# zoxide must initialize after prompt tools so its directory-change hook remains last.
if _bash_modern_zoxide="$(type -P zoxide 2>/dev/null)" && [[ -x ${_bash_modern_zoxide} ]]; then
    eval "$("${_bash_modern_zoxide}" init bash)"
fi
unset _bash_modern_zoxide
