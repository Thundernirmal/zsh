# Shared aliases.
if command -v lsd >/dev/null 2>&1; then
  alias ls='lsd'
  alias ll='lsd -lah --group-dirs=first'
  alias la='lsd -A'
  alias lt='lsd --tree --depth=3 --group-dirs=first'
else
  alias ls='command ls --color=auto'
  alias ll='command ls -lah --color=auto'
  alias la='command ls -A --color=auto'

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
alias grep='grep --color=auto'
alias diff='diff --color=auto'

# Network & system
alias ports='ss -tulnp'
alias myip='curl -s ifconfig.me'
alias weather='curl -s wttr.in'

# Git extras (OMZ git plugin covers basics, these fill gaps)
alias glog='git log --oneline --graph --decorate -20'
alias gpr='git pull --rebase'
alias gun='git reset HEAD~1 --soft'
alias gcount='git shortlog -sn --no-merges'