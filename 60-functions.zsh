# Useful shell functions.

# Extract any archive
extract() {
  if [ -z "$1" ]; then
    echo "Usage: extract <file>"
    return 1
  fi
  if [ ! -f "$1" ]; then
    echo "'$1' is not a valid file"
    return 1
  fi
  case $1 in
    *.tar.bz2)   tar xjf "$1" ;;
    *.tar.gz)    tar xzf "$1" ;;
    *.tar.xz)    tar xJf "$1" ;;
    *.bz2)       bunzip2 "$1" ;;
    *.rar)       unrar x "$1" ;;
    *.gz)        gunzip "$1" ;;
    *.tar)       tar xf "$1" ;;
    *.tbz2)      tar xjf "$1" ;;
    *.tgz)       tar xzf "$1" ;;
    *.zip)       unzip "$1" ;;
    *.Z)         uncompress "$1" ;;
    *.7z)        7z x "$1" ;;
    *)           echo "'$1' cannot be extracted via extract()" ;;
  esac
}

# Create directory and cd into it
mkcd() { mkdir -p "$1" && cd "$1"; }

# Find files by name
ff() { find . -iname "*${1:-}*" 2>/dev/null; }

# Find text in files (uses ripgrep if available, falls back to grep)
ft() {
  if command -v rg >/dev/null 2>&1; then
    rg --color=always "${1:-}" .
  else
    grep -rnI --color=auto "${1:-}" . 2>/dev/null
  fi
}

# Fuzzy kill process
fkill() {
  local pid
  pid=$(ps -ef | sed 1d | fzf -m --header='Select process to kill' | awk '{print $2}')
  if [ -n "$pid" ]; then
    kill -${1:-9} "$pid"
  fi
}

# Quick HTTP header check
http() { curl -sI "$1" | head -20; }

# Preview file (uses bat if available)
peek() {
  if command -v bat >/dev/null 2>&1; then
    bat --style=numbers --paging=never "$1"
  else
    cat "$1"
  fi
}

# Disk usage summary for current directory
dusage() {
  du -sh * 2>/dev/null | sort -rh | head -20
}

# Largest files in current directory tree
bigfiles() {
  find . -type f -exec du -h {} + 2>/dev/null | sort -rh | head -20
}
