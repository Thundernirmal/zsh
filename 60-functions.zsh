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
    *.tar.zst)   tar --zstd -xf "$1" ;;
    *.bz2)       bunzip2 "$1" ;;
    *.rar)       unrar x "$1" ;;
    *.gz)        gunzip "$1" ;;
    *.tar)       tar xf "$1" ;;
    *.tbz2)      tar xjf "$1" ;;
    *.tgz)       tar xzf "$1" ;;
    *.tzst)      tar --zstd -xf "$1" ;;
    *.zip)       unzip "$1" ;;
    *.Z)         uncompress "$1" ;;
    *.7z)        7z x "$1" ;;
    *)           echo "'$1' cannot be extracted via extract()"; return 1 ;;
  esac
}

# Create directory and cd into it
mkcd() { mkdir -p "$1" && cd "$1"; }

# Find files by name
ff() {
  if [ -z "$1" ]; then
    echo "Usage: ff <pattern> [path]"
    return 1
  fi

  local pattern=$1
  local search_root=${2:-.}

  if [ ! -d "$search_root" ]; then
    echo "'$search_root' is not a directory"
    return 1
  fi

  if command -v fd >/dev/null 2>&1; then
    fd --hidden --follow --glob --ignore-case -- "*$pattern*" "$search_root"
  elif command -v fdfind >/dev/null 2>&1; then
    fdfind --hidden --follow --glob --ignore-case -- "*$pattern*" "$search_root"
  else
    find "$search_root" -iname "*$pattern*" 2>/dev/null
  fi
}

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
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required for fkill"
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "fkill requires an interactive terminal"
    return 1
  fi

  local signal=${1:-9}
  local selected pid
  local -a pids

  signal=${signal#-}
  selected=$(
    ps -ef | sed 1d | awk '
      {
        pid = $2
        $1 = $2 = $3 = $4 = $5 = $6 = $7 = ""
        sub(/^ +/, "")
        print pid "\t" $0
      }
    ' | fzf -m --delimiter=$'\t' --with-nth=2.. --header="Select process(es) to kill with SIG${signal}"
  ) || return 0

  while IFS=$'\t' read -r pid _; do
    [ -n "$pid" ] && pids+=("$pid")
  done <<< "$selected"

  (( ${#pids[@]} > 0 )) || return 0
  kill "-$signal" "${pids[@]}"
}

# Quick HTTP header check
http() {
  if [ -z "$1" ]; then
    echo "Usage: http <url>"
    return 1
  fi

  curl -sIL "$1"
}

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
  local target=${1:-.}
  local limit=${2:-20}
  local -a entries

  if [ ! -d "$target" ]; then
    echo "'$target' is not a directory"
    return 1
  fi

  case $limit in
    ''|*[!0-9]*)
      echo "Usage: dusage [path] [count]"
      return 1
      ;;
  esac

  entries=( "$target"/*(DN) )
  if (( ${#entries[@]} == 0 )); then
    echo "No entries found in '$target'"
    return 0
  fi

  du -sh -- "${entries[@]}" 2>/dev/null | sort -rh | head -n "$limit"
}

# Largest files in current directory tree
bigfiles() {
  local target=${1:-.}
  local limit=${2:-20}

  if [ ! -e "$target" ]; then
    echo "'$target' does not exist"
    return 1
  fi

  case $limit in
    ''|*[!0-9]*)
      echo "Usage: bigfiles [path] [count]"
      return 1
      ;;
  esac

  find "$target" -type f -exec du -h {} + 2>/dev/null | sort -rh | head -n "$limit"
}

# Jump to the root of the current git repository
croot() {
  local root

  root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Not in a git repo"
    return 1
  }

  cd "$root" || return
}

# Print PATH one entry per line
path() {
  print -l -- ${(s/:/)PATH}
}

# Fuzzy-pick and checkout a git branch
fbr() {
  if ! command -v fzf >/dev/null 2>&1; then
    echo "fzf is required for fbr"
    return 1
  fi

  if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "fbr requires an interactive terminal"
    return 1
  fi

  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "Not in a git repo"
    return 1
  }

  local selection branch local_branch
  selection=$(
    git for-each-ref --sort=-committerdate \
      --format='%(refname:short)\t%(committerdate:relative)\t%(subject)' \
      refs/heads refs/remotes |
      command grep -v $'^[^[:space:]]+/HEAD\t' |
      fzf --ansi --height=50% --delimiter=$'\t' --with-nth=1,2,3 \
        --prompt='Branch> ' \
        --preview 'git log --oneline --decorate --color=always -20 {1}' \
        --preview-window=right,60%,border-left,wrap
  ) || return 0

  branch=${selection%%$'\t'*}

  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git checkout "$branch"
    return
  fi

  if git show-ref --verify --quiet "refs/remotes/$branch"; then
    local_branch=${branch#*/}
    if git show-ref --verify --quiet "refs/heads/$local_branch"; then
      git checkout "$local_branch"
    else
      git checkout --track "$branch"
    fi
    return
  fi

  echo "Branch '$branch' was not found"
  return 1
}
