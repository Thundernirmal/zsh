# Shared aliases.
if command -v lsd >/dev/null 2>&1; then
  alias ls='lsd'
  alias ll='lsd -lah --group-dirs=first'
  alias la='lsd -A'
  alias lt='lsd --tree --depth=3 --group-dirs=first'
else
  if command ls --color=auto . >/dev/null 2>&1; then
    alias ls='command ls --color=auto'
    alias ll='command ls -lah --color=auto'
    alias la='command ls -A --color=auto'
  else
    alias ls='command ls'
    alias ll='command ls -lah'
    alias la='command ls -A'
  fi

  if command -v tree >/dev/null 2>&1; then
    alias lt='tree -L 3 -a -C'
  fi
fi

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

# Safety & productivity
alias mkdir='mkdir -p'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -iv'

# File viewing
if command -v bat >/dev/null 2>&1; then
  alias cat='bat --style=numbers --paging=never'
fi

if print -r -- x | command grep --color=auto -e x >/dev/null 2>&1; then
  alias grep='grep --color=auto'
fi

if command diff --color=auto /dev/null /dev/null >/dev/null 2>&1; then
  alias diff='diff --color=auto'
fi

# Network & system
alias weather='curl --http1.1 -fsSL https://wttr.in'

# Git extras (OMZ git plugin covers basics, these fill gaps)
alias glog='git log --oneline --graph --decorate -20'
alias gpr='git pull --rebase'
alias gun='git reset HEAD~1 --soft'
alias gcount='gitcount'
