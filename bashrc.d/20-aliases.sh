alias grep='grep --color=auto'

if command -v eza >/dev/null 2>&1; then
    alias ll='eza -lah --group-directories-first'
    alias la='eza -a --group-directories-first'
    alias lt='eza --tree --level=2'
else
    alias ll='ls -lah'
    alias la='ls -A'
fi

if command -v bat >/dev/null 2>&1; then
    alias bcat='bat'
elif command -v batcat >/dev/null 2>&1; then
    alias bcat='batcat'
fi

if command -v fd >/dev/null 2>&1; then
    alias fdf='fd'
elif command -v fdfind >/dev/null 2>&1; then
    alias fdf='fdfind'
fi

