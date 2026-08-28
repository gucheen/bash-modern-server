shopt -s checkwinsize
shopt -s globstar 2>/dev/null || true
bind 'set completion-ignore-case on' 2>/dev/null || true
bind 'set show-all-if-ambiguous on' 2>/dev/null || true
bind '"\e\C-h": backward-kill-word' 2>/dev/null || true
bind '"\e\C-?": backward-kill-word' 2>/dev/null || true
bind '"\C-x\C-h": backward-kill-word' 2>/dev/null || true
bind '"\C-x\C-?": backward-kill-word' 2>/dev/null || true
