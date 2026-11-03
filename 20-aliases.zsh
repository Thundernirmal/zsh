# Shared aliases.
# Startup-time tool checks use $+commands (zsh's prehashed command table) instead of
# `command -v`: a miss costs a full PATH walk, which is very slow on long PATHs.
if (( $+commands[lsd] )); then
  alias ls='lsd'
  alias ll='lsd -lah --group-dirs=first'
  alias la='lsd -A'
  alias lt='lsd --tree --depth=3 --group-dirs=first'
else
  alias ls='command ls --color=auto'
  alias ll='command ls -lah --color=auto'
  alias la='command ls -A --color=auto'

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
# Debian and Ubuntu install bat as batcat.
if (( $+commands[bat] || $+commands[batcat] )); then
  typeset -g _ZSH_CAT_VIEWER=bat
  (( $+commands[bat] )) || _ZSH_CAT_VIEWER=batcat

  # bat rejects these GNU cat flags, so they go to the real cat. -n, -A, and -u
  # mean the same in both, and bat's own options such as -l and -p stay with bat.
  _zsh_cat() {
    emulate -L zsh

    local arg
    for arg in "$@"; do
      [[ $arg == -- ]] && break
      case $arg in
        --show-ends|--show-tabs|--show-nonprinting|--number-nonblank|--squeeze-blank)
          command cat "$@"
          return
          ;;
      esac
      if [[ $arg == -* && $arg != --* && $arg != *[^-AbeEnstTuv]* && $arg == *[beEstTv]* ]]; then
        command cat "$@"
        return
      fi
    done
    command "$_ZSH_CAT_VIEWER" --style=numbers --paging=never "$@"
  }
  alias cat='_zsh_cat'
fi

alias grep='grep --color=auto'
alias diff='diff --color=auto'

# Git extras (OMZ git plugin covers basics, these fill gaps)
alias glog='git log --oneline --graph --decorate -20'
alias gpr='git pull --rebase'
alias gun='git reset HEAD~1 --soft'
alias gcount='gitcount'
