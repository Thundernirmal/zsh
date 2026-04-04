# Enhanced zsh completion system.
# This complements OMZ without clashing — OMZ loads compinit,
# we just tune the behavior with zstyles.

# Enable menu-based completion selection
zstyle ':completion:*' menu select

# Fuzzy matching: case-insensitive, partial word matching
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Use LS_COLORS for colored completion listings
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# Show descriptions for completion groups
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'
zstyle ':completion:*:messages' format '%F{purple}-- %d --%f'
zstyle ':completion:*:warnings' format '%F{red}-- no matches found --%f'

# Group completions by type (files, commands, aliases, etc.)
zstyle ':completion:*' group-name ''

# Sort files by modification time
zstyle ':completion:*' file-sort modification

# Don't insert common prefix when ambiguous, just show menu
zstyle ':completion:*' insert-tab false

# Squeeze consecutive slashes in path completion
zstyle ':completion:*' squeeze-slashes true

# Include options in completion results
zstyle ':completion:*' complete-options true

# Better kill completion (show process info)
zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm,cmd -w -w"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'
