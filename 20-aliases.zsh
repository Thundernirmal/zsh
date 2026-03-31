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