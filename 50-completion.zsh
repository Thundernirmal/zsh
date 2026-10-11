# Lighter zsh completion tuning.
# OMZ already runs compinit; keep this file small to avoid slow completion lists.

# Case-insensitive matching is cheap and useful; avoid heavier fuzzy matchers.
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Clean up path completion without changing default completion flow.
zstyle ':completion:*' squeeze-slashes true

# Better kill completion (show process info)
# EUID is always set by zsh, unlike USER in minimal containers.
zstyle ':completion:*:*:*:*:processes' command "ps -u $EUID -o pid,user,comm,cmd -w -w"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'
