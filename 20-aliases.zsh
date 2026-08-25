# Shared aliases.
# Startup-time tool checks use $+commands (zsh's prehashed command table) instead of
# `command -v`: a miss costs a full PATH walk, which is very slow on long PATHs.
if (( $+commands[lsd] )); then
  alias ls='lsd'
  alias ll='lsd -lah --group-dirs=first'
  alias la='lsd -A'
  alias lt='lsd --tree --depth=3 --group-dirs=first'
else
  if [[ $OSTYPE == linux* ]]; then
    alias ls='command ls --color=auto'
    alias ll='command ls -lah --color=auto'
    alias la='command ls -A --color=auto'
  else
    alias ls='command ls'
    alias ll='command ls -lah'
    alias la='command ls -A'
  fi

  if (( $+commands[tree] )); then
    alias lt='tree -L 3 -a -C'
  fi
fi

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

# File viewing
if (( $+commands[bat] )); then
  alias cat='bat --style=numbers --paging=never'
fi

if [[ $OSTYPE == linux* ]]; then
  alias grep='grep --color=auto'
  alias diff='diff --color=auto'
fi

# Network & system
alias weather='curl --http1.1 -fsSL https://wttr.in'

# Git extras (OMZ git plugin covers basics, these fill gaps)
alias glog='git log --oneline --graph --decorate -20'
alias gpr='git pull --rebase'
alias gun='git reset HEAD~1 --soft'
alias gcount='gitcount'
